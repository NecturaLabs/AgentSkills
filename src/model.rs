//! The normalized asset model.
//!
//! Provider payloads are mapped into these types once, at the provider
//! boundary. Nothing above the provider layer sees Fab's or FabCLI's field
//! names, so replacing the provider cannot change what agents parse.
//!
//! Absence is explicit: an unknown scalar is omitted from JSON (`None`), never
//! reported as "false" or "zero". Empty lists are omitted too, so an absent
//! list means "empty or unknown"; callers that need to tell "no engines" from
//! "engines never fetched" read [`Asset::coverage`].

use crate::sanitize;
use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Engine ecosystem an asset targets. `Other` keeps unknown Fab channels usable
/// instead of dropping them.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Engine {
    /// Unreal Engine.
    Unreal,
    /// Unity.
    Unity,
    /// Godot.
    Godot,
    /// Blender (DCC, not a game engine, but a first-class Fab channel).
    Blender,
    /// Unreal Editor for Fortnite.
    Uefn,
    /// MetaHuman.
    Metahuman,
    /// Any channel necturalabs-fab does not model explicitly.
    Other(String),
}

impl Engine {
    /// Parse a user-facing engine name. Accepts common aliases.
    pub fn parse(raw: &str) -> Self {
        match raw.trim().to_ascii_lowercase().as_str() {
            "unreal" | "ue" | "ue4" | "ue5" | "unreal-engine" | "unrealengine" => Self::Unreal,
            "unity" | "unity3d" => Self::Unity,
            "godot" => Self::Godot,
            "blender" => Self::Blender,
            "uefn" | "fortnite" => Self::Uefn,
            "metahuman" => Self::Metahuman,
            other => Self::Other(other.to_string()),
        }
    }

    /// The slug Fab uses for this engine's channel, when it has one.
    pub fn channel_slug(&self) -> Option<&str> {
        match self {
            Self::Unreal => Some("unreal-engine"),
            Self::Unity => Some("unity"),
            Self::Uefn => Some("uefn"),
            Self::Metahuman => Some("metahuman"),
            // Fab exposes these as asset formats rather than channels.
            Self::Godot | Self::Blender => None,
            Self::Other(s) => Some(s),
        }
    }

    /// The `asset_formats` slug Fab uses, when the engine maps to one.
    pub fn format_slug(&self) -> Option<&str> {
        match self {
            Self::Unreal => Some("unreal-engine"),
            Self::Unity => Some("unity"),
            Self::Godot => Some("godot"),
            Self::Blender => Some("blender"),
            Self::Uefn => Some("uefn"),
            Self::Metahuman => Some("metahuman"),
            Self::Other(s) => Some(s),
        }
    }

    /// Canonical lowercase name.
    pub fn as_str(&self) -> &str {
        match self {
            Self::Unreal => "unreal",
            Self::Unity => "unity",
            Self::Godot => "godot",
            Self::Blender => "blender",
            Self::Uefn => "uefn",
            Self::Metahuman => "metahuman",
            Self::Other(s) => s,
        }
    }
}

/// Coarse asset classification, derived from Fab's `listingType`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum AssetKind {
    /// Meshes and model packs.
    Model3d,
    /// Materials, textures, smart materials.
    Material,
    /// Editor tools and plugins.
    Tool,
    /// Sound effects and music.
    Audio,
    /// Environment / level kits.
    Environment,
    /// Animation packs.
    Animation,
    /// VFX, particles.
    Vfx,
    /// Anything else the marketplace reports.
    Other(String),
}

impl AssetKind {
    /// Map a Fab `listingType` slug onto a kind.
    pub fn from_listing_type(raw: &str) -> Self {
        match raw.trim().to_ascii_lowercase().as_str() {
            "3d-model" | "3d-models" => Self::Model3d,
            "material" | "materials" => Self::Material,
            "tool-and-plugin" | "tool" | "plugin" => Self::Tool,
            "audio" | "sound" | "music" => Self::Audio,
            "environment" | "environments" => Self::Environment,
            "animation" | "animations" => Self::Animation,
            "vfx" | "visual-effects" => Self::Vfx,
            other => Self::Other(other.to_string()),
        }
    }
}

/// A non-negative money amount, held exactly in hundredths of the currency
/// unit. Every currency Fab prices in has at most two decimals; a value with
/// more is treated as unknown rather than rounded. Serialized as a decimal
/// string (`"19.99"`) so no consumer ever sees a binary float.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Amount(i64);

impl Amount {
    /// Zero.
    pub const ZERO: Amount = Amount(0);

    /// Largest accepted whole-unit part: far above any listing price, and far
    /// below `i64` overflow.
    const MAX_WHOLE_DIGITS: usize = 12;

    /// Parse plain decimal text: digits, optionally `.` and one or two digits.
    pub fn parse(text: &str) -> Option<Amount> {
        let (whole, fraction) = match text.split_once('.') {
            Some((whole, fraction)) => (whole, Some(fraction)),
            None => (text, None),
        };
        if whole.is_empty()
            || whole.len() > Self::MAX_WHOLE_DIGITS
            || !whole.bytes().all(|b| b.is_ascii_digit())
        {
            return None;
        }
        let cents = match fraction {
            None => 0,
            Some(f) if (1..=2).contains(&f.len()) && f.bytes().all(|b| b.is_ascii_digit()) => {
                let value: i64 = f.parse().ok()?;
                if f.len() == 1 {
                    value * 10
                } else {
                    value
                }
            }
            Some(_) => return None,
        };
        Some(Amount(whole.parse::<i64>().ok()? * 100 + cents))
    }

    /// Read a provider JSON number exactly as it was written.
    ///
    /// serde_json prints a parsed number with the shortest text that reads
    /// back to the same value, which for any price with at most two decimals
    /// is the text the provider sent.
    pub fn from_json(value: &serde_json::Value) -> Option<Amount> {
        match value {
            serde_json::Value::Number(n) => Amount::parse(&n.to_string()),
            _ => None,
        }
    }

    /// The amount in hundredths of the currency unit.
    pub fn hundredths(self) -> i64 {
        self.0
    }

    /// Whether the amount is zero.
    pub fn is_zero(self) -> bool {
        self.0 == 0
    }
}

impl std::fmt::Display for Amount {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}.{:02}", self.0 / 100, self.0 % 100)
    }
}

impl std::str::FromStr for Amount {
    type Err = String;

    fn from_str(text: &str) -> std::result::Result<Self, Self::Err> {
        Amount::parse(text.trim()).ok_or_else(|| {
            format!(
                "'{text}' is not an amount: use a non-negative number with at most two decimals"
            )
        })
    }
}

impl Serialize for Amount {
    fn serialize<S: serde::Serializer>(
        &self,
        serializer: S,
    ) -> std::result::Result<S::Ok, S::Error> {
        serializer.collect_str(self)
    }
}

impl<'de> Deserialize<'de> for Amount {
    fn deserialize<D: serde::Deserializer<'de>>(
        deserializer: D,
    ) -> std::result::Result<Self, D::Error> {
        let text = String::deserialize(deserializer)?;
        Amount::parse(&text)
            .ok_or_else(|| serde::de::Error::custom(format!("invalid amount '{text}'")))
    }
}

/// Money. Amounts are the marketplace's own decimal values, held exactly;
/// currency is always carried alongside so an amount is never interpreted in
/// the wrong unit.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Price {
    /// Effective price a buyer pays now, in `currency`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub amount: Option<Amount>,
    /// List price before any discount.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub original: Option<Amount>,
    /// ISO-4217 code, when the provider reports one.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub currency: Option<String>,
    /// Current discount, 0-100.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub discount_percent: Option<u32>,
    /// True when the asset can be added to a library at no cost.
    ///
    /// Mirrors the marketplace's own definition: flagged free, priced zero, or
    /// discounted to zero. `None` means the provider gave no pricing at all.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub free: Option<bool>,
    /// True when `free` is only true because of a time-limited 100% discount.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub temporarily_free: Option<bool>,
    /// When a time-limited discount ends (RFC 3339, UTC), if reported.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub free_until: Option<String>,
}

impl Price {
    /// Whether this price permits a no-cost claim.
    pub fn is_free(&self) -> bool {
        self.free == Some(true)
    }
}

/// Aggregate review signal.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Rating {
    /// Mean rating, 0-5.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub average: Option<f64>,
    /// Number of ratings behind `average`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub count: Option<u64>,
}

/// Seller identity.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Publisher {
    /// Display name.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    /// Stable seller id, when exposed.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<String>,
    /// Public profile URL.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
}

/// Marketplace category.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Category {
    /// Human-readable name.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    /// URL slug.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub slug: Option<String>,
    /// Full category path, when the provider reports one.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
}

/// One distributable format of an asset (a Fab "asset format").
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AssetFormat {
    /// Format slug, e.g. `unreal-engine`, `fbx`, `blender`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub code: Option<String>,
    /// Display name.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    /// How the format is delivered (e.g. `asset-pack`, `complete-project`).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub distribution_method: Option<String>,
    /// Engine versions this format ships for.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub engine_versions: Vec<String>,
    /// Target platforms this format ships for.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub platforms: Vec<String>,
}

/// Where a piece of technical metadata came from.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum MetadataSource {
    /// A structured field the provider returned.
    Structured,
    /// Extracted from the seller's free-text technical description.
    ParsedText,
}

/// Technical properties an agent needs to judge fitness.
///
/// Fab exposes most of this only as seller-authored free text, so anything
/// recovered from that text is marked [`MetadataSource::ParsedText`] and is
/// advisory, not authoritative.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TechnicalMetadata {
    /// Triangle count, when stated.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub triangles: Option<u64>,
    /// Vertex count, when stated.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub vertices: Option<u64>,
    /// Number of LODs, when stated.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lods: Option<u32>,
    /// Texture resolutions mentioned, e.g. `["2048x2048", "4096x4096"]`.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub texture_resolutions: Vec<String>,
    /// Whether the asset ships rigged, when stated.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rigged: Option<bool>,
    /// Whether the asset ships animated, when stated.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub animated: Option<bool>,
    /// Whether meshes are skeletal (`true`) or static (`false`), when stated.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub skeletal: Option<bool>,
    /// Number of animation tracks, when stated.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub animation_tracks: Option<u32>,
    /// Number of unique meshes, when stated.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub meshes: Option<u32>,
    /// Number of materials, when stated.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub materials: Option<u32>,
    /// Number of textures, when stated.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub textures: Option<u32>,
    /// Whether the meshes are Nanite-enabled (Unreal), when stated.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub nanite: Option<bool>,
    /// Provenance for the fields above.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source: Option<MetadataSource>,
    /// The seller's technical blurb, cleaned and truncated.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
}

impl TechnicalMetadata {
    /// True when nothing at all was recovered.
    pub fn is_empty(&self) -> bool {
        self.triangles.is_none()
            && self.vertices.is_none()
            && self.lods.is_none()
            && self.texture_resolutions.is_empty()
            && self.rigged.is_none()
            && self.animated.is_none()
            && self.skeletal.is_none()
            && self.animation_tracks.is_none()
            && self.meshes.is_none()
            && self.materials.is_none()
            && self.textures.is_none()
            && self.nanite.is_none()
            && self.notes.is_none()
    }
}

/// Ownership and licensing state for the authenticated account.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Ownership {
    /// Listing this record describes.
    pub listing_id: String,
    /// `None` means ownership could not be determined (e.g. not signed in).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub owned: Option<bool>,
    /// Entitlement id, when the provider exposes one.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub entitlement_id: Option<String>,
    /// License names/tiers held or offered.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub licenses: Vec<String>,
    /// Whether the account has wishlisted the listing.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub wishlisted: Option<bool>,
    /// Which provider surface answered.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
}

/// How completely an [`Asset`] is populated.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum DetailLevel {
    /// Came from a search or library listing: cheap fields only.
    Summary,
    /// Came from a listing lookup, including formats where available.
    Detail,
}

/// Whether a group of fields was actually retrievable.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Availability {
    /// The provider returned this group.
    Available,
    /// The provider was not asked (cheap path).
    NotRequested,
    /// The provider was asked and could not answer.
    Unavailable,
}

/// Per-field-group availability, so `null` is never ambiguous.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Coverage {
    /// Formats, engines, engine versions, platforms.
    pub formats: Availability,
    /// Ownership state.
    pub ownership: Availability,
    /// Technical metadata.
    pub technical: Availability,
    /// Pricing.
    pub pricing: Availability,
}

impl Default for Coverage {
    fn default() -> Self {
        Self {
            formats: Availability::NotRequested,
            ownership: Availability::NotRequested,
            technical: Availability::NotRequested,
            pricing: Availability::NotRequested,
        }
    }
}

/// The stable asset shape every necturalabs-fab command emits.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Asset {
    /// Marketplace listing identifier. Stable across providers for Fab.
    pub id: String,
    /// Provider that produced this record.
    pub provider: String,
    /// Listing title (sanitized).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    /// Canonical marketplace URL.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    /// Description (sanitized, truncated unless the caller asked for full text).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    /// Seller.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub publisher: Option<Publisher>,
    /// Primary category.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub category: Option<Category>,
    /// Raw marketplace listing type slug.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub listing_type: Option<String>,
    /// Normalized kind.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub kind: Option<AssetKind>,
    /// Tag slugs.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub tags: Vec<String>,
    /// Pricing. In search and ranked results this is the marketplace list
    /// price (the same currency across every result, usually USD), so
    /// candidates compare directly.
    pub price: Price,
    /// The price in the account's own currency, when listing detail reported
    /// one that differs from `price`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub local_price: Option<Price>,
    /// Whether the authenticated account owns it. `None` = unknown.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub owned: Option<bool>,
    /// License names, when known.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub licenses: Vec<String>,
    /// Distributable formats.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub formats: Vec<AssetFormat>,
    /// Engines derived from formats and channels.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub engines: Vec<Engine>,
    /// Engine versions across all formats.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub engine_versions: Vec<String>,
    /// Target platforms across all formats.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub platforms: Vec<String>,
    /// Technical properties.
    pub technical: TechnicalMetadata,
    /// Review aggregate.
    pub rating: Rating,
    /// Number of written reviews, when distinct from rating count.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub review_count: Option<u64>,
    /// Thumbnail URL.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub thumbnail: Option<String>,
    /// First publication timestamp, ISO-8601 as the provider reported it.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub published_at: Option<String>,
    /// Creation timestamp, ISO-8601.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub created_at: Option<String>,
    /// Mature-content flag.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mature: Option<bool>,
    /// How complete this record is.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub detail_level: Option<DetailLevel>,
    /// Which field groups were retrievable.
    pub coverage: Coverage,
    /// Untouched provider payload. Only populated when the caller passes
    /// `--raw`; it is a debugging aid and is not part of the stable contract.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub raw: Option<Value>,
}

impl Asset {
    /// A new, empty asset for `provider`.
    pub fn new(id: impl Into<String>, provider: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            provider: provider.into(),
            ..Default::default()
        }
    }

    /// Fab's canonical listing URL.
    pub fn fab_url(uid: &str) -> String {
        format!("https://www.fab.com/listings/{uid}")
    }

    /// Whether this asset advertises support for `engine`.
    ///
    /// `None` when the asset carries no engine information at all, so callers
    /// can distinguish "incompatible" from "unknown".
    pub fn supports_engine(&self, engine: &Engine) -> Option<bool> {
        if self.engines.is_empty() {
            return None;
        }
        Some(self.engines.contains(engine))
    }

    /// Whether this asset advertises `version` (exact string match against the
    /// provider's own version labels, plus a `UE_5.4` / `5.4` equivalence).
    pub fn supports_engine_version(&self, version: &str) -> Option<bool> {
        if self.engine_versions.is_empty() {
            return None;
        }
        let wanted = normalize_engine_version(version);
        Some(
            self.engine_versions
                .iter()
                .any(|have| normalize_engine_version(have) == wanted),
        )
    }

    /// Drop the description down to the summary limit.
    pub fn truncate_description(&mut self) {
        if let Some(desc) = &self.description {
            self.description = sanitize::text(desc, sanitize::DESCRIPTION_LIMIT);
        }
    }
}

/// Accept only listing ids that are safe to put in a path or a command line.
///
/// Ids reach necturalabs-fab from agents and from marketplace responses, become
/// provider arguments, and name the default download directory. Anything
/// outside `[A-Za-z0-9._-]`, a leading `-` (it would read as a flag) or `.`, a
/// trailing `.`, or a Windows reserved device name is rejected here rather
/// than sanitised into something that merely looks valid.
pub fn validate_listing_id(raw: &str) -> crate::error::Result<String> {
    let id = raw.trim();
    let invalid = |why: &str| {
        crate::error::FabError::invalid(format!("'{id}' is not a valid listing id ({why})"))
            .with_hint("copy the id from `necturalabs-fab search --json` output")
    };
    if id.is_empty() || id.len() > 128 {
        return Err(invalid("must be 1 to 128 characters"));
    }
    if !id
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.'))
    {
        return Err(invalid(
            "only letters, digits, '-', '_' and '.' are allowed",
        ));
    }
    if id.starts_with(['-', '.']) || id.ends_with('.') {
        return Err(invalid("must not start with '-' or '.', or end with '.'"));
    }
    let stem = id.split('.').next().unwrap_or(id).to_ascii_uppercase();
    let reserved = matches!(stem.as_str(), "CON" | "PRN" | "AUX" | "NUL")
        || ((stem.starts_with("COM") || stem.starts_with("LPT"))
            && stem.len() == 4
            && stem.as_bytes()[3].is_ascii_digit());
    if reserved {
        return Err(invalid("reserved device name"));
    }
    Ok(id.to_string())
}

/// `UE_5.4`, `ue5.4`, `5.4` all normalize to `5.4`.
pub fn normalize_engine_version(raw: &str) -> String {
    let lower = raw.trim().to_ascii_lowercase();
    let stripped = lower
        .strip_prefix("ue_")
        .or_else(|| lower.strip_prefix("ue-"))
        .or_else(|| lower.strip_prefix("ue"))
        .unwrap_or(&lower);
    stripped
        .trim_matches(|c: char| !c.is_ascii_digit() && c != '.')
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn amounts_are_exact_hundredths_parsed_from_decimal_text() {
        assert_eq!(Amount::parse("19.99").unwrap().hundredths(), 1999);
        assert_eq!(Amount::parse("20").unwrap().hundredths(), 2000);
        assert_eq!(Amount::parse("0.5").unwrap().hundredths(), 50);
        assert_eq!(Amount::parse("0").unwrap(), Amount::ZERO);
        // 0.1 + 0.2 style drift cannot happen: the text is the value.
        assert_eq!(Amount::parse("0.30").unwrap().hundredths(), 30);
        for bad in [
            "",
            "-1",
            "1.234",
            "1e3",
            "abc",
            "1.",
            ".5",
            "NaN",
            "99999999999999999",
        ] {
            assert!(Amount::parse(bad).is_none(), "{bad:?} should be rejected");
        }
    }

    #[test]
    fn amounts_render_and_serialize_as_decimal_strings() {
        let amount = Amount::parse("89.9").unwrap();
        assert_eq!(amount.to_string(), "89.90");
        assert_eq!(
            serde_json::to_value(amount).unwrap(),
            serde_json::json!("89.90")
        );
        let back: Amount = serde_json::from_value(serde_json::json!("89.90")).unwrap();
        assert_eq!(back, amount);
    }

    #[test]
    fn amounts_read_from_provider_json_keep_the_written_decimal() {
        let json: serde_json::Value =
            serde_json::from_str(r#"{"a": 301.41, "b": 0.0, "c": 17.99, "d": 1.005}"#).unwrap();
        assert_eq!(Amount::from_json(&json["a"]).unwrap().hundredths(), 30141);
        assert_eq!(Amount::from_json(&json["b"]).unwrap(), Amount::ZERO);
        assert_eq!(Amount::from_json(&json["c"]).unwrap().hundredths(), 1799);
        assert!(
            Amount::from_json(&json["d"]).is_none(),
            "sub-cent values are unknown, not rounded"
        );
        assert!(Amount::from_json(&serde_json::json!(-5)).is_none());
        assert!(
            Amount::from_json(&serde_json::json!("12.00")).is_none(),
            "provider numbers only"
        );
    }

    #[test]
    fn engine_aliases_normalize() {
        assert_eq!(Engine::parse("UE5"), Engine::Unreal);
        assert_eq!(Engine::parse("  unreal  "), Engine::Unreal);
        assert_eq!(Engine::parse("unreal-engine"), Engine::Unreal);
        assert_eq!(Engine::parse("Unity3D"), Engine::Unity);
        assert_eq!(
            Engine::parse("cryengine"),
            Engine::Other("cryengine".into())
        );
    }

    #[test]
    fn engine_version_equivalence() {
        assert_eq!(normalize_engine_version("UE_5.4"), "5.4");
        assert_eq!(normalize_engine_version("5.4"), "5.4");
        assert_eq!(normalize_engine_version("ue5.4"), "5.4");
    }

    #[test]
    fn unknown_engine_support_is_none_not_false() {
        let asset = Asset::new("uid", "fabcli");
        assert_eq!(asset.supports_engine(&Engine::Unreal), None);
        assert_eq!(asset.supports_engine_version("5.4"), None);
    }

    #[test]
    fn known_engine_support_is_decided() {
        let mut asset = Asset::new("uid", "fabcli");
        asset.engines = vec![Engine::Unreal];
        asset.engine_versions = vec!["UE_5.4".into()];
        assert_eq!(asset.supports_engine(&Engine::Unreal), Some(true));
        assert_eq!(asset.supports_engine(&Engine::Unity), Some(false));
        assert_eq!(asset.supports_engine_version("5.4"), Some(true));
        assert_eq!(asset.supports_engine_version("5.0"), Some(false));
    }

    #[test]
    fn listing_ids_that_could_escape_a_path_or_become_a_flag_are_rejected() {
        assert!(validate_listing_id("a55fc08e-82ec-4332-8bed-dde44fff7847").is_ok());
        for bad in [
            "../etc/passwd",
            "a/b",
            "a\\b",
            ".hidden",
            "trailing.",
            "",
            "a b",
            "a;rm -rf /",
            "a$(x)",
            "-x",
            "--force",
            "CON",
            "nul.txt",
            "com1",
            "LPT9",
        ] {
            assert!(validate_listing_id(bad).is_err(), "accepted {bad:?}");
        }
        assert!(validate_listing_id(&"x".repeat(200)).is_err());
        assert!(
            validate_listing_id("console").is_ok(),
            "only exact device names are reserved"
        );
    }

    #[test]
    fn coverage_defaults_to_not_requested() {
        let asset = Asset::new("uid", "fabcli");
        assert_eq!(asset.coverage.formats, Availability::NotRequested);
    }
}

#[cfg(test)]
mod serialization_tests {
    use super::*;

    #[test]
    fn unknown_fields_are_omitted_rather_than_emitted_as_null() {
        let asset = Asset::new("uid", "fabcli");
        let json = serde_json::to_value(&asset).unwrap();
        assert!(json.get("title").is_none(), "unknown title must be omitted");
        assert!(json.get("engines").is_none(), "empty lists must be omitted");
        // Identity and coverage are always present: they are how a reader
        // tells "absent because unknown" from "absent because not fetched".
        assert_eq!(json["id"], "uid");
        assert_eq!(json["provider"], "fabcli");
        assert_eq!(json["coverage"]["formats"], "not-requested");
    }

    #[test]
    fn known_false_values_are_still_emitted() {
        let mut asset = Asset::new("uid", "fabcli");
        asset.owned = Some(false);
        asset.price.free = Some(false);
        let json = serde_json::to_value(&asset).unwrap();
        assert_eq!(json["owned"], false);
        assert_eq!(json["price"]["free"], false);
    }
}
