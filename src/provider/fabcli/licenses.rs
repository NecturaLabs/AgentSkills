//! Licences established from Fab's licence search filter, and the on-disk
//! cache that keeps them between runs.
//!
//! A listing's licence rarely changes, while establishing it costs marketplace
//! searches, so every verdict is kept for [`TTL_SECONDS`]. The cache only ever
//! saves time: a missing, unreadable or corrupt file is treated as empty, and
//! a failed write is ignored.

use std::collections::HashMap;
use std::io::Write;
use std::path::{Path, PathBuf};

/// How long a verdict is trusted: publishers move legacy listings to the
/// Standard License over time, so a week keeps the answer fresh enough.
pub const TTL_SECONDS: u64 = 7 * 24 * 60 * 60;

/// Largest cache file read. Far above any real one (an entry is ~80 bytes).
const MAX_FILE_BYTES: u64 = 8 * 1024 * 1024;

/// Most entries kept; the oldest go first.
const MAX_ENTRIES: usize = 50_000;

/// Cache file format version.
const VERSION: u64 = 1;

/// What Fab's licence filter says about one listing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LicenseKind {
    /// The Standard License. Fab requires both of its tiers on every such
    /// listing, so one tier's filter proves both.
    Standard,
    /// Creative Commons Attribution 4.0.
    CcBy,
    /// The listing is on the marketplace under neither: a licence the filter
    /// does not name, such as the legacy UE Marketplace License.
    Unlisted,
}

impl LicenseKind {
    fn slug(self) -> &'static str {
        match self {
            Self::Standard => "standard",
            Self::CcBy => "cc-by",
            Self::Unlisted => "unlisted",
        }
    }

    fn from_slug(slug: &str) -> Option<Self> {
        match slug {
            "standard" => Some(Self::Standard),
            "cc-by" => Some(Self::CcBy),
            "unlisted" => Some(Self::Unlisted),
            _ => None,
        }
    }
}

/// Verdicts by listing id, with when each was established (Unix seconds).
#[derive(Debug, Default)]
pub struct LicenseCache {
    path: Option<PathBuf>,
    entries: HashMap<String, (LicenseKind, u64)>,
    changed: bool,
}

impl LicenseCache {
    /// A cache that lives only as long as the process.
    pub fn in_memory() -> Self {
        Self::default()
    }

    /// Load the cache at `path`, keeping only valid, unexpired entries.
    pub fn load(path: PathBuf, now: u64) -> Self {
        let entries = read_entries(&path, now).unwrap_or_default();
        Self {
            path: Some(path),
            entries,
            changed: false,
        }
    }

    /// The verdict for `id`, if one is known.
    pub fn get(&self, id: &str) -> Option<LicenseKind> {
        self.entries.get(id).map(|(kind, _)| *kind)
    }

    /// Record a verdict.
    pub fn insert(&mut self, id: &str, kind: LicenseKind, now: u64) {
        self.entries.insert(id.to_string(), (kind, now));
        self.changed = true;
    }

    /// Write new verdicts to disk, merged with whatever another run saved in
    /// the meantime. Best effort: a cache that cannot be written is skipped.
    pub fn save(&mut self, now: u64) {
        let Some(path) = self.path.clone() else {
            return;
        };
        if !self.changed {
            return;
        }
        let mut merged = read_entries(&path, now).unwrap_or_default();
        for (id, entry) in &self.entries {
            match merged.get(id) {
                Some((_, checked)) if *checked > entry.1 => {}
                _ => {
                    merged.insert(id.clone(), *entry);
                }
            }
        }
        let mut rows: Vec<(&String, &(LicenseKind, u64))> = merged.iter().collect();
        rows.sort_by(|a, b| b.1 .1.cmp(&a.1 .1).then_with(|| a.0.cmp(b.0)));
        rows.truncate(MAX_ENTRIES);
        let body = serde_json::json!({
            "version": VERSION,
            "entries": rows
                .iter()
                .map(|(id, (kind, checked))| {
                    ((*id).clone(), serde_json::json!({"kind": kind.slug(), "checked": checked}))
                })
                .collect::<serde_json::Map<_, _>>(),
        });
        if write_atomically(&path, &body.to_string()).is_ok() {
            self.changed = false;
        }
    }
}

fn read_entries(path: &Path, now: u64) -> Option<HashMap<String, (LicenseKind, u64)>> {
    let meta = std::fs::metadata(path).ok()?;
    if !meta.is_file() || meta.len() > MAX_FILE_BYTES {
        return None;
    }
    let text = std::fs::read_to_string(path).ok()?;
    let value: serde_json::Value = serde_json::from_str(&text).ok()?;
    if value.get("version").and_then(serde_json::Value::as_u64) != Some(VERSION) {
        return None;
    }
    let rows = value.get("entries")?.as_object()?;
    Some(
        rows.iter()
            .filter_map(|(id, row)| {
                let id = crate::model::validate_listing_id(id).ok()?;
                let kind = LicenseKind::from_slug(row.get("kind")?.as_str()?)?;
                let checked = row.get("checked")?.as_u64()?;
                // Expired, or stamped in the future by a skewed clock.
                (checked <= now && now - checked < TTL_SECONDS).then_some((id, (kind, checked)))
            })
            .collect(),
    )
}

/// Write a fresh, uniquely named file and rename it over the cache, so a
/// reader never sees half a file and a planted link is replaced, not followed.
fn write_atomically(path: &Path, text: &str) -> std::io::Result<()> {
    let dir = path
        .parent()
        .ok_or_else(|| std::io::Error::other("cache path has no directory"))?;
    std::fs::create_dir_all(dir)?;
    let staging = dir.join(format!(
        ".licenses-{}-{}.tmp",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.subsec_nanos())
            .unwrap_or(0)
    ));
    let result = (|| {
        let mut file = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&staging)?;
        file.write_all(text.as_bytes())?;
        file.sync_all()?;
        std::fs::rename(&staging, path)
    })();
    if result.is_err() {
        let _ = std::fs::remove_file(&staging);
    }
    result
}

/// Seconds since the Unix epoch.
pub fn now() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    const ID: &str = "11111111-1111-4111-8111-111111111111";
    const OTHER: &str = "22222222-2222-4222-8222-222222222222";

    #[test]
    fn verdicts_survive_a_restart() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("licenses.json");
        let mut cache = LicenseCache::load(path.clone(), 1_000);
        cache.insert(ID, LicenseKind::CcBy, 1_000);
        cache.insert(OTHER, LicenseKind::Unlisted, 1_000);
        cache.save(1_000);

        let reloaded = LicenseCache::load(path, 1_001);
        assert_eq!(reloaded.get(ID), Some(LicenseKind::CcBy));
        assert_eq!(reloaded.get(OTHER), Some(LicenseKind::Unlisted));
    }

    #[test]
    fn expired_and_future_verdicts_are_dropped() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("licenses.json");
        let mut cache = LicenseCache::load(path.clone(), 1_000);
        cache.insert(ID, LicenseKind::Standard, 1_000);
        cache.insert(OTHER, LicenseKind::Standard, 5_000);
        cache.save(5_000);

        let reloaded = LicenseCache::load(path, 1_000 + TTL_SECONDS);
        assert_eq!(reloaded.get(ID), None, "a week-old verdict is stale");
        assert_eq!(reloaded.get(OTHER), Some(LicenseKind::Standard));

        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("licenses.json");
        let mut cache = LicenseCache::load(path.clone(), 9_000);
        cache.insert(ID, LicenseKind::Standard, 9_000);
        cache.save(9_000);
        assert_eq!(LicenseCache::load(path, 100).get(ID), None);
    }

    #[test]
    fn a_corrupt_or_hostile_file_is_ignored_entry_by_entry() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("licenses.json");
        std::fs::write(&path, "{not json").unwrap();
        assert_eq!(LicenseCache::load(path.clone(), 10).get(ID), None);

        std::fs::write(
            &path,
            format!(
                r#"{{"version": 1, "entries": {{
                    "{ID}": {{"kind": "cc-by", "checked": 5}},
                    "../../etc": {{"kind": "cc-by", "checked": 5}},
                    "{OTHER}": {{"kind": "public-domain", "checked": 5}}}}}}"#
            ),
        )
        .unwrap();
        let cache = LicenseCache::load(path, 10);
        assert_eq!(cache.get(ID), Some(LicenseKind::CcBy));
        assert_eq!(cache.get("../../etc"), None);
        assert_eq!(cache.get(OTHER), None);
    }

    #[test]
    fn saving_keeps_what_another_run_wrote() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("licenses.json");
        let mut first = LicenseCache::load(path.clone(), 100);
        let mut second = LicenseCache::load(path.clone(), 100);
        first.insert(ID, LicenseKind::CcBy, 100);
        first.save(100);
        second.insert(OTHER, LicenseKind::Standard, 100);
        second.save(100);

        let merged = LicenseCache::load(path, 101);
        assert_eq!(merged.get(ID), Some(LicenseKind::CcBy));
        assert_eq!(merged.get(OTHER), Some(LicenseKind::Standard));
    }
}
