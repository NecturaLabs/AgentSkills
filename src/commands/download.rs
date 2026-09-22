//! `download` — put an owned asset's files on disk.
//!
//! Downloads are the only command that writes outside the config directory,
//! so the checks live here: where the files go, what happens to files already
//! there, and what the caller is told about both before anything is written.

use super::{validate_listing_id, Ctx};
use crate::approval::{gate, ActionPlan};
use crate::cli::DownloadArgs;
use crate::error::{ErrorCode, FabError, Result};
use crate::output::Outcome;
use crate::provider::{DownloadReceipt, DownloadRequest, OverwritePolicy};
use serde_json::json;
use std::fs;
use std::path::{Path, PathBuf};

/// Metadata file necturalabs-fab writes beside a downloaded asset.
pub const SIDECAR_NAME: &str = "necturalabs-fab.asset.json";

/// Run `download`.
pub fn run(ctx: &Ctx, args: &DownloadArgs) -> Result<Outcome> {
    let listing_id = validate_listing_id(&args.listing)?;
    if !ctx.provider.capabilities().download {
        return Err(crate::provider::Capabilities::unsupported(
            ctx.provider.id(),
            "download",
        ));
    }

    let overwrite = match &args.overwrite {
        Some(raw) => OverwritePolicy::parse(raw)?,
        None => ctx.config.download.overwrite,
    };
    let output_dir = resolve_output_dir(ctx, args, &listing_id);
    let state = inspect_dir(&output_dir)?;

    if state.sidecar_is_link {
        return Err(FabError::new(
            ErrorCode::OutputConflict,
            format!(
                "{} in {} is a link; refusing to write through it",
                SIDECAR_NAME,
                output_dir.display()
            ),
        )
        .with_hint("remove the link, or choose another --out directory")
        .with_detail("outputDir", json!(output_dir.display().to_string())));
    }
    if state.sidecar_present && overwrite == OverwritePolicy::Refuse {
        let holder = state
            .existing_sidecar
            .clone()
            .unwrap_or_else(|| "an unreadable record".to_string());
        return Err(FabError::new(
            ErrorCode::OutputConflict,
            format!(
                "{} already holds a necturalabs-fab download ({holder})",
                output_dir.display()
            ),
        )
        .with_hint("pass --overwrite force to replace it, or choose another --out directory")
        .with_detail("outputDir", json!(output_dir.display().to_string()))
        .with_detail("existingListingId", json!(state.existing_sidecar)));
    }
    if state.non_empty && overwrite == OverwritePolicy::RequireEmpty {
        return Err(FabError::new(
            ErrorCode::OutputNotEmpty,
            format!("{} is not empty", output_dir.display()),
        )
        .with_hint("choose an empty directory, or use --overwrite refuse/force")
        .with_detail("outputDir", json!(output_dir.display().to_string())));
    }

    let effects = vec![
        format!("writes asset files into {}", output_dir.display()),
        match overwrite {
            OverwritePolicy::Force => "overwrites files already there".to_string(),
            OverwritePolicy::Refuse => "refuses if any file would be overwritten".to_string(),
            OverwritePolicy::RequireEmpty => "requires the directory to be empty".to_string(),
        },
    ];
    let plan = gate(
        ActionPlan::local_write("download", output_dir.display().to_string(), effects),
        ctx.config.approval.download,
        true,
    )?;

    let request = DownloadRequest {
        listing_id: listing_id.clone(),
        output_dir: output_dir.clone(),
        engine_version: args.engine_version.clone(),
        platform: args.platform.clone(),
        overwrite,
        jobs: args.jobs.or(ctx.config.download.jobs),
        dry_run: args.dry_run,
    };

    if args.dry_run {
        let receipt = ctx.provider.download(&request)?;
        let data = json!({
            "dryRun": true,
            "plan": {
                "listingId": listing_id,
                "title": receipt.title,
                "outputDir": output_dir,
                "outputDirExists": state.exists,
                "outputDirEmpty": !state.non_empty,
                "overwrite": overwrite,
                "engineVersions": receipt.engine_versions,
                "platforms": receipt.platforms,
                "wouldWriteSidecar": !args.no_sidecar,
            },
            "note": "file and byte counts are only known once the provider fetches the manifest",
        });
        let human = format!(
            "Dry run: would download {listing_id} into {} ({} policy). Nothing written.",
            output_dir.display(),
            match overwrite {
                OverwritePolicy::Force => "force",
                OverwritePolicy::Refuse => "refuse",
                OverwritePolicy::RequireEmpty => "require-empty",
            }
        );
        return Ok(Outcome::read("download", data, human).with_action(plan));
    }

    let created = ensure_writable(&output_dir)?;
    let receipt = match ctx.provider.download(&request) {
        Ok(receipt) => receipt,
        Err(err) => {
            // Undo only what this run created, and only while it is still
            // empty: files a partial download left are the user's to judge.
            for dir in created.iter().rev() {
                if fs::remove_dir(dir).is_err() {
                    break;
                }
            }
            return Err(err);
        }
    };

    let mut warnings = Vec::new();
    let sidecar_path = if args.no_sidecar {
        None
    } else {
        match write_sidecar(&output_dir, &receipt, ctx.provider.id()) {
            Ok(path) => Some(path),
            Err(err) => {
                warnings.push(format!("could not write {SIDECAR_NAME}: {}", err.message));
                None
            }
        }
    };

    let data = json!({
        "receipt": receipt,
        "outputDir": output_dir,
        "sidecar": sidecar_path,
        "providerSidecar": receipt.provider_sidecar,
    });
    let human = format!(
        "Downloaded {} file(s), {} into {}",
        receipt
            .files
            .map(|f| f.to_string())
            .unwrap_or_else(|| "?".into()),
        receipt
            .bytes
            .map(human_bytes)
            .unwrap_or_else(|| "unknown size".into()),
        output_dir.display()
    );

    let mut outcome = Outcome::read("download", data, human).with_action(plan);
    outcome.warnings = warnings;
    Ok(outcome)
}

/// Where the files go: `--out` verbatim, otherwise a per-listing directory
/// under the configured download root, so two downloads never collide.
pub fn resolve_output_dir(ctx: &Ctx, args: &DownloadArgs, listing_id: &str) -> PathBuf {
    let base = match &args.out {
        Some(out) => out.clone(),
        None => ctx.config.download.directory.join(listing_id),
    };
    let joined = if base.is_absolute() {
        base
    } else {
        ctx.cwd.join(base)
    };
    // Rebuilt from components so the reported path uses the platform's own
    // separator even when the user typed `assets/castle` on Windows.
    joined.components().collect()
}

/// What the destination currently holds.
#[derive(Debug, Default)]
pub struct DirState {
    /// Directory exists.
    pub exists: bool,
    /// Directory exists and holds at least one entry.
    pub non_empty: bool,
    /// A necturalabs-fab sidecar (file or anything else) is present.
    pub sidecar_present: bool,
    /// The sidecar path is a symbolic link.
    pub sidecar_is_link: bool,
    /// Listing id recorded by a previous necturalabs-fab download, if readable.
    pub existing_sidecar: Option<String>,
}

/// Inspect the destination without creating it.
pub fn inspect_dir(path: &Path) -> Result<DirState> {
    if !path.exists() {
        return Ok(DirState::default());
    }
    if !path.is_dir() {
        return Err(FabError::new(
            ErrorCode::InvalidInput,
            format!("{} exists and is not a directory", path.display()),
        ));
    }
    let mut state = DirState {
        exists: true,
        ..Default::default()
    };
    let entries = fs::read_dir(path).map_err(|err| {
        FabError::new(
            map_io(&err),
            format!("cannot read {}: {err}", path.display()),
        )
    })?;
    state.non_empty = entries.count() > 0;
    let sidecar = path.join(SIDECAR_NAME);
    if let Ok(meta) = fs::symlink_metadata(&sidecar) {
        state.sidecar_present = true;
        state.sidecar_is_link = meta.file_type().is_symlink();
    }
    if state.sidecar_is_link {
        return Ok(state);
    }
    if let Ok(text) = fs::read_to_string(&sidecar) {
        state.existing_sidecar = serde_json::from_str::<serde_json::Value>(&text)
            .ok()
            .and_then(|v| {
                v.get("listingId")
                    .and_then(|id| id.as_str())
                    .map(str::to_string)
            });
    }
    Ok(state)
}

/// Create `path` if needed and prove it writable. Returns the directories
/// this call created, outermost first.
fn ensure_writable(path: &Path) -> Result<Vec<PathBuf>> {
    let created: Vec<PathBuf> = {
        let mut missing: Vec<PathBuf> = path
            .ancestors()
            .take_while(|p| !p.as_os_str().is_empty() && !p.exists())
            .map(Path::to_path_buf)
            .collect();
        missing.reverse();
        missing
    };
    fs::create_dir_all(path).map_err(|err| {
        FabError::new(
            map_io(&err),
            format!("cannot create {}: {err}", path.display()),
        )
        .with_hint("choose a directory you can write to with --out")
    })?;
    // A fresh, uniquely named file created with create_new: an existing entry
    // at that path — including a planted symlink — makes this fail instead of
    // being written through.
    let probe = path.join(unique_name(".necturalabs-fab-probe"));
    fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&probe)
        .map_err(|err| {
            FabError::new(
                map_io(&err),
                format!("cannot write into {}: {err}", path.display()),
            )
            .with_hint("choose a writable directory with --out")
        })?;
    let _ = fs::remove_file(probe);
    Ok(created)
}

fn map_io(err: &std::io::Error) -> ErrorCode {
    match err.kind() {
        std::io::ErrorKind::PermissionDenied => ErrorCode::PermissionDenied,
        _ => ErrorCode::DownloadFailed,
    }
}

/// Write the necturalabs-fab sidecar: provider-independent metadata a later
/// import step can rely on without re-querying the marketplace.
fn write_sidecar(dir: &Path, receipt: &DownloadReceipt, provider: &str) -> Result<PathBuf> {
    let path = dir.join(SIDECAR_NAME);
    let body = json!({
        "schema": "necturalabs-fab/asset@1",
        "necturalabsFabVersion": crate::VERSION,
        "provider": provider,
        "listingId": receipt.listing_id,
        "title": receipt.title,
        "url": crate::model::Asset::fab_url(&receipt.listing_id),
        "files": receipt.files,
        "bytes": receipt.bytes,
        "engineVersions": receipt.engine_versions,
        "platforms": receipt.platforms,
        "providerSidecar": receipt.provider_sidecar,
    });
    let text = format!("{}\n", serde_json::to_string_pretty(&body)?);
    // Write a fresh, uniquely named file and rename it into place: rename
    // replaces whatever sits at the destination, a symlink included, without
    // following it, and create_new refuses to reuse an existing entry.
    let staging = dir.join(unique_name(".necturalabs-fab-sidecar"));
    let result = (|| -> std::io::Result<()> {
        use std::io::Write;
        let mut file = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&staging)?;
        file.write_all(text.as_bytes())?;
        file.sync_all()?;
        fs::rename(&staging, &path)
    })();
    if let Err(err) = result {
        let _ = fs::remove_file(&staging);
        return Err(FabError::new(
            map_io(&err),
            format!("cannot write {}: {err}", path.display()),
        ));
    }
    Ok(path)
}

fn unique_name(prefix: &str) -> String {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.subsec_nanos())
        .unwrap_or(0);
    format!("{prefix}-{}-{nanos}.tmp", std::process::id())
}

fn human_bytes(bytes: u64) -> String {
    const UNITS: [&str; 5] = ["B", "KiB", "MiB", "GiB", "TiB"];
    let mut value = bytes as f64;
    let mut unit = 0;
    while value >= 1024.0 && unit < UNITS.len() - 1 {
        value /= 1024.0;
        unit += 1;
    }
    if unit == 0 {
        format!("{bytes} B")
    } else {
        format!("{value:.1} {}", UNITS[unit])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn byte_sizes_are_readable() {
        assert_eq!(human_bytes(512), "512 B");
        assert_eq!(human_bytes(2048), "2.0 KiB");
        assert_eq!(human_bytes(3_221_225_472), "3.0 GiB");
    }

    #[test]
    fn dir_state_detects_a_previous_download() {
        let tmp = tempfile::tempdir().unwrap();
        let state = inspect_dir(tmp.path()).unwrap();
        assert!(state.exists && !state.non_empty && state.existing_sidecar.is_none());

        fs::write(
            tmp.path().join(SIDECAR_NAME),
            r#"{"listingId":"abc","schema":"necturalabs-fab/asset@1"}"#,
        )
        .unwrap();
        let state = inspect_dir(tmp.path()).unwrap();
        assert!(state.non_empty);
        assert_eq!(state.existing_sidecar.as_deref(), Some("abc"));
    }

    #[test]
    fn a_file_where_a_directory_belongs_is_invalid_input() {
        let tmp = tempfile::tempdir().unwrap();
        let file = tmp.path().join("not-a-dir");
        fs::write(&file, b"x").unwrap();
        let err = inspect_dir(&file).unwrap_err();
        assert_eq!(err.code, ErrorCode::InvalidInput);
    }

    #[test]
    fn missing_directory_reports_absent_rather_than_failing() {
        let tmp = tempfile::tempdir().unwrap();
        let state = inspect_dir(&tmp.path().join("nope")).unwrap();
        assert!(!state.exists);
    }

    #[cfg(unix)]
    #[test]
    fn the_sidecar_write_replaces_a_late_planted_link_instead_of_following_it() {
        // The pre-flight check refuses a linked sidecar, but a download can run
        // for hours: the write itself must not follow a link planted meanwhile.
        let tmp = tempfile::tempdir().unwrap();
        let victim = tmp.path().join("victim.txt");
        fs::write(&victim, "precious").unwrap();
        let dir = tmp.path().join("out");
        fs::create_dir_all(&dir).unwrap();
        std::os::unix::fs::symlink(&victim, dir.join(SIDECAR_NAME)).unwrap();
        let receipt = DownloadReceipt {
            listing_id: "abc".into(),
            output_dir: dir.clone(),
            ..Default::default()
        };
        let path = write_sidecar(&dir, &receipt, "fabcli").unwrap();
        assert_eq!(fs::read_to_string(&victim).unwrap(), "precious");
        assert!(!fs::symlink_metadata(&path)
            .unwrap()
            .file_type()
            .is_symlink());
        assert!(fs::read_to_string(&path)
            .unwrap()
            .contains("\"listingId\": \"abc\""));
    }

    #[test]
    fn sidecar_records_a_provider_independent_record() {
        let tmp = tempfile::tempdir().unwrap();
        let receipt = DownloadReceipt {
            listing_id: "abc".into(),
            output_dir: tmp.path().to_path_buf(),
            files: Some(12),
            bytes: Some(2048),
            title: Some("Castle".into()),
            engine_versions: vec!["UE_5.4".into()],
            platforms: vec!["Windows".into()],
            provider_sidecar: Some(".fabcli-asset.json".into()),
            elapsed_seconds: Some(1.5),
        };
        let path = write_sidecar(tmp.path(), &receipt, "fabcli").unwrap();
        let body: serde_json::Value =
            serde_json::from_str(&fs::read_to_string(path).unwrap()).unwrap();
        assert_eq!(body["schema"], "necturalabs-fab/asset@1");
        assert_eq!(body["listingId"], "abc");
        assert_eq!(body["engineVersions"][0], "UE_5.4");
        assert_eq!(body["url"], "https://www.fab.com/listings/abc");
    }
}
