//! Normalization: FabCLI JSON in, [`crate::model`] types out.
//!
//! This is the only module that knows Fab's field names. It is deliberately
//! total — a missing or unexpected field produces `None`, never a panic and
//! never a fabricated value — because the upstream API is undocumented and
//! changes without notice.

use crate::error::{ErrorCode, FabError, Result};
use crate::model::{
    Amount, Asset, AssetFormat, AssetKind, Availability, Category, DetailLevel, Engine,
    MetadataSource, Ownership, Price, Publisher, Rating, TechnicalMetadata,
};
use crate::provider::{AuthStatus, ClaimOutcome, SearchPage};
use crate::sanitize;
use serde_json::Value;

/// Provider id recorded on every asset this module produces.
pub const PROVIDER: &str = "fabcli";

/// Fab's licence search facets, as its `licenses` filter spells them, and the
/// name each one is reported under. Fab's listing detail names the licences,
/// but FabCLI 0.1 drops them from its output, so they are recovered from which
/// licence-filtered searches return a listing.
pub const LICENSE_FACETS: [(&str, &str); 3] = [
    ("personal", "Standard License (Personal)"),
    ("professional", "Standard License (Professional)"),
    ("cc-by", "CC BY 4.0"),
];

/// Index of the CC BY facet in [`LICENSE_FACETS`]. Fab offers a listing under
/// either CC BY or the Standard License, never both
/// (<https://dev.epicgames.com/documentation/fab/licenses-and-pricing-in-fab>).
pub const CC_BY_FACET: usize = 2;

/// Map `fabcli search` output into a page of normalized assets.
pub fn search_page(value: &Value, include_raw: bool) -> Result<SearchPage> {
    let results = value
        .get("results")
        .and_then(Value::as_array)
        .ok_or_else(|| {
            FabError::new(
                ErrorCode::ProviderProtocol,
                "search response has no 'results' array",
            )
            .with_provider(PROVIDER)
        })?;

    let assets = results
        .iter()
        .filter_map(|row| search_listing(row, include_raw))
        .collect();

    Ok(SearchPage {
        assets,
        total: value.get("count").and_then(Value::as_u64),
        // A cursor is opaque but is echoed back to the provider and printed, so
        // one carrying anything but printable ASCII is dropped, not repaired.
        next_cursor: value
            .get("cursors")
            .and_then(|c| c.get("next"))
            .and_then(Value::as_str)
            .filter(|c| c.len() <= 1024 && c.chars().all(|ch| ch.is_ascii_graphic()))
            .map(str::to_string),
    })
}

/// Map one search-result row. Rows without a usable `uid` are dropped: an
/// asset with no safe identity cannot be inspected, downloaded or claimed.
pub fn search_listing(row: &Value, include_raw: bool) -> Option<Asset> {
    let uid = row
        .get("uid")
        .and_then(Value::as_str)
        .and_then(|uid| crate::model::validate_listing_id(uid).ok())?;
    let mut asset = base_asset(&uid, row, include_raw);
    asset.detail_level = Some(DetailLevel::Summary);
    asset.owned = row.get("owned").and_then(Value::as_bool);
    asset.coverage.ownership = if asset.owned.is_some() {
        Availability::Available
    } else {
        Availability::NotRequested
    };
    asset.coverage.pricing = if row.get("startingPrice").is_some() || row.get("isFree").is_some() {
        Availability::Available
    } else {
        Availability::Unavailable
    };
    Some(asset)
}

/// Map `fabcli listing <uid>` output.
pub fn listing_detail(value: &Value, include_raw: bool) -> Result<Asset> {
    let uid = value
        .get("uid")
        .and_then(Value::as_str)
        .and_then(|uid| crate::model::validate_listing_id(uid).ok())
        .ok_or_else(|| {
            FabError::new(
                ErrorCode::ProviderProtocol,
                "listing response has no usable 'uid'",
            )
            .with_provider(PROVIDER)
        })?;
    let mut asset = base_asset(&uid, value, include_raw);
    asset.detail_level = Some(DetailLevel::Detail);
    asset.description = value
        .get("description")
        .and_then(Value::as_str)
        .and_then(description_text);
    asset.created_at = value
        .get("createdAt")
        .and_then(Value::as_str)
        .map(str::to_string);
    asset.review_count = value.get("reviewCount").and_then(Value::as_u64);
    asset.coverage.pricing =
        if value.get("startingPrice").is_some() || value.get("isFree").is_some() {
            Availability::Available
        } else {
            Availability::Unavailable
        };
    Ok(asset)
}

/// Fields shared by search rows and listing detail.
fn base_asset(uid: &str, row: &Value, include_raw: bool) -> Asset {
    let mut asset = Asset::new(uid, PROVIDER);
    asset.title = row
        .get("title")
        .and_then(Value::as_str)
        .and_then(sanitize::short);
    asset.url = Some(Asset::fab_url(uid));
    asset.listing_type = row
        .get("listingType")
        .and_then(Value::as_str)
        .map(str::to_string);
    asset.kind = asset
        .listing_type
        .as_deref()
        .map(AssetKind::from_listing_type);
    asset.publisher = publisher(row.get("user"));
    asset.category = category(row.get("category"));
    asset.tags = tags(row.get("tags"));
    asset.price = price(
        row.get("isFree").and_then(Value::as_bool),
        row.get("startingPrice"),
    );
    asset.rating = rating(row.get("ratings"));
    asset.thumbnail = row
        .get("thumbnails")
        .and_then(Value::as_array)
        .and_then(|thumbs| thumbs.first())
        .and_then(|t| t.get("mediaUrl"))
        .and_then(Value::as_str)
        .map(str::to_string);
    asset.published_at = row
        .get("publishedAt")
        .and_then(Value::as_str)
        .map(str::to_string);
    asset.mature = row.get("isMature").and_then(Value::as_bool);
    if include_raw {
        asset.raw = Some(row.clone());
    }
    asset
}

fn publisher(value: Option<&Value>) -> Option<Publisher> {
    let user = value?;
    let publisher = Publisher {
        name: user
            .get("sellerName")
            .and_then(Value::as_str)
            .and_then(sanitize::short),
        id: user
            .get("sellerId")
            .and_then(Value::as_str)
            .and_then(sanitize::short),
        url: user
            .get("profileUrl")
            .and_then(Value::as_str)
            .map(str::to_string),
    };
    if publisher.name.is_none() && publisher.id.is_none() && publisher.url.is_none() {
        return None;
    }
    Some(publisher)
}

fn category(value: Option<&Value>) -> Option<Category> {
    let cat = value?;
    let category = Category {
        name: cat
            .get("name")
            .and_then(Value::as_str)
            .and_then(sanitize::short),
        slug: cat
            .get("slug")
            .and_then(Value::as_str)
            .and_then(sanitize::short),
        path: cat
            .get("path")
            .and_then(Value::as_str)
            .and_then(sanitize::short),
    };
    if category.name.is_none() && category.slug.is_none() {
        return None;
    }
    Some(category)
}

fn tags(value: Option<&Value>) -> Vec<String> {
    value
        .and_then(Value::as_array)
        .map(|tags| {
            tags.iter()
                .filter_map(|t| {
                    t.get("slug")
                        .or_else(|| t.get("name"))
                        .and_then(Value::as_str)
                        .and_then(sanitize::short)
                })
                .collect()
        })
        .unwrap_or_default()
}

/// Build a [`Price`] from Fab's `isFree` flag and `startingPrice` object.
///
/// Mirrors FabCLI's own free test (flagged free, zero price, or zero
/// discounted price). Keeping the definitions identical matters: a divergence
/// would let necturalabs-fab call something free that the provider then refuses to
/// claim, or worse, the reverse.
pub fn price(is_free: Option<bool>, starting_price: Option<&Value>) -> Price {
    let mut price = Price::default();
    let sp = starting_price.filter(|v| !v.is_null());

    if let Some(sp) = sp {
        let list = sp.get("price").and_then(Amount::from_json);
        let discounted = sp.get("discountedPrice").and_then(Amount::from_json);
        price.currency = sp
            .get("currencyCode")
            .and_then(Value::as_str)
            .and_then(sanitize::short)
            .or_else(|| currency_from_tier(sp, list));
        price.discount_percent = ["discountPercentage", "effectiveDiscountPercentage"]
            .iter()
            .find_map(|key| sp.get(*key).and_then(Value::as_u64))
            .map(|v| v.min(100) as u32);
        price.amount = discounted.or(list);
        price.original = match (list, discounted) {
            (Some(list), Some(disc)) if disc < list => Some(list),
            _ => None,
        };
        let zero = list.is_some_and(Amount::is_zero) || discounted.is_some_and(Amount::is_zero);
        price.free = Some(is_free == Some(true) || zero);
        // Search rows omit the discount entirely: unknown, not "not free".
        price.temporarily_free = match (is_free, discounted) {
            (Some(true), _) => Some(false),
            (_, Some(disc)) => Some(disc.is_zero() && list.is_some_and(|l| !l.is_zero())),
            (_, None) => None,
        };
        if price.temporarily_free == Some(true) {
            price.free_until = sp
                .get("discountEndDate")
                .and_then(Value::as_str)
                .filter(|d| {
                    d.len() <= 40
                        && d.chars()
                            .all(|c| c.is_ascii_digit() || "TZ:+-.".contains(c))
                })
                .map(str::to_string);
        }
    } else if let Some(flag) = is_free {
        price.free = Some(flag);
        if flag {
            price.amount = Some(Amount::ZERO);
            price.temporarily_free = Some(false);
        }
    }
    price
}

/// Fab's `priceTierId` looks like `<hash>_<ISO currency>_<minor units>_<ts>`.
/// Search rows carry no `currencyCode`, so the currency is read from the tier —
/// but only when the tier's minor units equal the list price, which proves the
/// tier and the price describe the same amount in the same currency.
fn currency_from_tier(sp: &Value, list: Option<Amount>) -> Option<String> {
    let tier = sp.get("priceTierId")?.as_str()?;
    let parts: Vec<&str> = tier.split('_').collect();
    let position = parts
        .iter()
        .position(|p| p.len() == 3 && p.chars().all(|c| c.is_ascii_uppercase()))?;
    let currency = parts[position];
    let minor: i64 = parts.get(position + 1)?.parse().ok()?;
    if list?.hundredths() != minor {
        return None;
    }
    Some(currency.to_string())
}

fn rating(value: Option<&Value>) -> Rating {
    let Some(ratings) = value.filter(|v| !v.is_null()) else {
        return Rating::default();
    };
    Rating {
        average: ratings.get("averageRating").and_then(Value::as_f64),
        count: ratings
            .get("total")
            .or_else(|| ratings.get("count"))
            .and_then(Value::as_u64),
    }
}

/// Fold `fabcli formats <uid>` output into an asset.
///
/// The response is an array of format objects; each carries engine versions
/// and platforms per downloadable version. Sets `coverage.formats` so callers
/// can tell "no engines listed" from "engines never fetched".
pub fn apply_formats(asset: &mut Asset, formats: &Value) {
    let Some(entries) = formats.as_array() else {
        asset.coverage.formats = Availability::Unavailable;
        return;
    };

    let mut engine_versions: Vec<String> = Vec::new();
    let mut platforms: Vec<String> = Vec::new();
    let mut engines: Vec<Engine> = Vec::new();
    let mut technical_notes: Vec<String> = Vec::new();
    let mut structured = TechnicalMetadata::default();

    for entry in entries {
        let code = entry
            .get("assetFormatType")
            .and_then(|t| t.get("code"))
            .and_then(Value::as_str);
        let name = entry
            .get("assetFormatType")
            .and_then(|t| t.get("name"))
            .and_then(Value::as_str)
            .and_then(sanitize::short);

        let mut format = AssetFormat {
            code: code.and_then(sanitize::short),
            name,
            distribution_method: entry
                .get("distributionMethod")
                .and_then(Value::as_str)
                .and_then(sanitize::short),
            engine_versions: Vec::new(),
            platforms: Vec::new(),
        };

        if let Some(versions) = entry.get("versions").and_then(Value::as_array) {
            for version in versions {
                collect_strings(version.get("engineVersions"), &mut format.engine_versions);
                collect_strings(version.get("targetPlatforms"), &mut format.platforms);
            }
        }
        collect_strings(entry.get("developmentPlatforms"), &mut format.platforms);

        if let Some(engine) = code.and_then(engine_from_format_code) {
            if !engines.contains(&engine) {
                engines.push(engine);
            }
        }
        if let Some(notes) = entry.get("technicalDetails").and_then(Value::as_str) {
            technical_notes.push(strip_html(notes));
        }
        if let Some(details) = entry.get("techDetails").and_then(Value::as_object) {
            for block in details.values().filter(|v| v.is_object()) {
                if let Some(info) = block.get("additionalInformation").and_then(Value::as_str) {
                    technical_notes.push(strip_html(info));
                }
                merge_structured(&mut structured, block);
            }
        }

        dedupe(&mut format.engine_versions);
        dedupe(&mut format.platforms);
        engine_versions.extend(format.engine_versions.iter().cloned());
        platforms.extend(format.platforms.iter().cloned());
        asset.formats.push(format);
    }

    dedupe(&mut engine_versions);
    dedupe(&mut platforms);
    asset.engine_versions = engine_versions;
    asset.platforms = platforms;
    asset.engines = engines;
    asset.coverage.formats = Availability::Available;

    // Structured fields are authoritative; seller prose only fills gaps and
    // is only used on its own when nothing structured was published.
    let parsed = technical_from_text(&technical_notes.join(" "));
    asset.technical = if structured.is_empty() {
        parsed
    } else {
        structured.source = Some(MetadataSource::Structured);
        structured.notes = parsed.notes.clone();
        structured
    };
    asset.coverage.technical = if asset.technical.is_empty() {
        Availability::Unavailable
    } else {
        Availability::Available
    };
}

fn collect_strings(value: Option<&Value>, out: &mut Vec<String>) {
    let Some(array) = value.and_then(Value::as_array) else {
        return;
    };
    for item in array {
        if let Some(text) = item.as_str().and_then(sanitize::short) {
            out.push(text);
        }
    }
}

fn dedupe(values: &mut Vec<String>) {
    values.sort();
    values.dedup();
}

/// Fold one `techDetails` block (e.g. `threeDModel`) into `into`, keeping the
/// first value seen for each field. Counts arrive as half-open ranges; only an
/// exact range (`upper == lower + 1`) with a non-zero value becomes a number,
/// because Fab uses `[0, 1)` as a placeholder for "not stated".
fn merge_structured(into: &mut TechnicalMetadata, block: &Value) {
    let exact = |key: &str| -> Option<u64> {
        let range = block.get(key)?;
        let lower = range.get("lower")?.as_u64()?;
        let upper = range.get("upper")?.as_u64()?;
        (upper == lower + 1 && lower > 0).then_some(lower)
    };
    let count = |key: &str| block.get(key).and_then(Value::as_u64).map(|v| v as u32);
    let flag = |key: &str| block.get(key).and_then(Value::as_bool);

    into.triangles = into.triangles.or_else(|| exact("trianglesCountRange"));
    into.vertices = into.vertices.or_else(|| exact("vertexCountRange"));
    into.lods = into.lods.or_else(|| count("lodsCount"));
    into.animation_tracks = into
        .animation_tracks
        .or_else(|| count("animationTracksCount"));
    into.meshes = into.meshes.or_else(|| count("uniqueMeshesCount"));
    into.materials = into.materials.or_else(|| count("materialsCount"));
    into.textures = into.textures.or_else(|| count("texturesCount"));
    into.nanite = into.nanite.or_else(|| flag("isNaniteEnabled"));
    into.rigged = into.rigged.or_else(|| {
        flag("hasRiggedAnimations")
            .or_else(|| block.get("riggedTo").filter(|v| !v.is_null()).map(|_| true))
    });
    into.animated = into.animated.or_else(|| {
        flag("isAnimated").or_else(|| {
            block
                .get("animationTracksCount")
                .and_then(Value::as_u64)
                .map(|n| n > 0)
        })
    });
    if into.texture_resolutions.is_empty() {
        if let Some(resolution) = exact("textureResolutionRange") {
            into.texture_resolutions.push(resolution.to_string());
        }
    }
}

/// Seller text arrives as HTML. Drop the tags and decode the handful of
/// entities Fab emits, leaving plain text for parsing and display.
/// Descriptions are seller-authored HTML; agents and terminals get the text.
fn description_text(raw: &str) -> Option<String> {
    let text = strip_html(raw)
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    sanitize::text(&text, sanitize::DESCRIPTION_LIMIT)
}

fn strip_html(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len());
    let mut in_tag = false;
    for ch in raw.chars() {
        match ch {
            '<' => {
                in_tag = true;
                out.push(' ');
            }
            '>' if in_tag => in_tag = false,
            _ if !in_tag => out.push(ch),
            _ => {}
        }
    }
    out.replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&nbsp;", " ")
}

/// Map a Fab asset-format slug onto an engine, when it names one. Interchange
/// formats (`fbx`, `gltf`, ...) map to no engine on purpose.
pub fn engine_from_format_code(code: &str) -> Option<Engine> {
    match code.trim().to_ascii_lowercase().as_str() {
        "unreal-engine" | "ue" => Some(Engine::Unreal),
        "unity" => Some(Engine::Unity),
        "godot" => Some(Engine::Godot),
        "blender" => Some(Engine::Blender),
        "uefn" => Some(Engine::Uefn),
        "metahuman" => Some(Engine::Metahuman),
        _ => None,
    }
}

/// Recover technical facts from a seller's free-text technical description.
///
/// Everything here is advisory: sellers write this field by hand in no fixed
/// format. Anything not stated unambiguously stays `None` rather than being
/// guessed, and the result is tagged [`MetadataSource::ParsedText`].
pub fn technical_from_text(raw: &str) -> TechnicalMetadata {
    let cleaned = sanitize::text(raw, 4000).unwrap_or_default();
    let lower = cleaned.to_ascii_lowercase();
    let mut meta = TechnicalMetadata {
        notes: sanitize::text(&cleaned, sanitize::DESCRIPTION_LIMIT),
        source: Some(MetadataSource::ParsedText),
        ..Default::default()
    };

    meta.triangles = number_after(
        &lower,
        &["triangles", "tris", "tri count", "polygons", "polys"],
    );
    meta.vertices = number_after(&lower, &["vertices", "verts", "vertex count"]);
    meta.lods = number_after(&lower, &["lods", "lod levels", "number of lods"]).map(|v| v as u32);
    meta.texture_resolutions = texture_resolutions(&cleaned);
    meta.rigged = flag(&lower, "rigged").or_else(|| flag(&lower, "rigging"));
    meta.animated = flag(&lower, "animated").or_else(|| flag(&lower, "animations"));
    meta.skeletal = match (flag(&lower, "skeletal"), flag(&lower, "static mesh")) {
        (Some(true), _) => Some(true),
        (_, Some(true)) => Some(false),
        _ => None,
    };

    if meta.is_empty() {
        return TechnicalMetadata::default();
    }
    meta
}

/// First integer appearing within 40 characters after any of `keys`.
fn number_after(haystack: &str, keys: &[&str]) -> Option<u64> {
    for key in keys {
        let mut from = 0usize;
        while let Some(found) = haystack[from..].find(key) {
            let start = from + found + key.len();
            let window = &haystack[start..haystack.len().min(start + 40)];
            if let Some(value) = first_number(window) {
                return Some(value);
            }
            from = start;
            if from >= haystack.len() {
                break;
            }
        }
    }
    None
}

fn first_number(window: &str) -> Option<u64> {
    let mut digits = String::new();
    let mut started = false;
    for ch in window.chars() {
        if ch.is_ascii_digit() {
            digits.push(ch);
            started = true;
        } else if started && (ch == ',' || ch == '.' || ch == ' ') {
            // Thousands separators inside a number only; stop at a second group break.
            if digits.len() > 12 {
                break;
            }
            continue;
        } else if started {
            break;
        } else if ch.is_alphabetic() {
            // A word before any digit means this mention carries no count.
            return None;
        }
    }
    digits.parse().ok().filter(|n| *n > 0)
}

/// `2048x2048`, `4096 x 4096` — explicit dimensions only. `4K` is deliberately
/// not expanded: it is ambiguous between 3840 and 4096.
fn texture_resolutions(text: &str) -> Vec<String> {
    let bytes: Vec<char> = text.chars().collect();
    let mut found: Vec<String> = Vec::new();
    let mut idx = 0;
    while idx < bytes.len() {
        if !bytes[idx].is_ascii_digit() {
            idx += 1;
            continue;
        }
        let start = idx;
        while idx < bytes.len() && bytes[idx].is_ascii_digit() {
            idx += 1;
        }
        let first: String = bytes[start..idx].iter().collect();
        let mut cursor = idx;
        while cursor < bytes.len() && bytes[cursor] == ' ' {
            cursor += 1;
        }
        if cursor < bytes.len()
            && (bytes[cursor] == 'x' || bytes[cursor] == 'X' || bytes[cursor] == '×')
        {
            cursor += 1;
            while cursor < bytes.len() && bytes[cursor] == ' ' {
                cursor += 1;
            }
            let second_start = cursor;
            while cursor < bytes.len() && bytes[cursor].is_ascii_digit() {
                cursor += 1;
            }
            if cursor > second_start {
                let second: String = bytes[second_start..cursor].iter().collect();
                if first.len() <= 5 && second.len() <= 5 {
                    let value = format!("{first}x{second}");
                    if !found.contains(&value) {
                        found.push(value);
                    }
                }
                idx = cursor;
            }
        }
    }
    found
}

/// Yes/no detection for a keyword, honouring nearby negation.
fn flag(haystack: &str, keyword: &str) -> Option<bool> {
    let pos = haystack.find(keyword)?;
    let prefix_start = pos.saturating_sub(16);
    let prefix = &haystack[prefix_start..pos];
    let negated = ["not ", "no ", "non-", "without ", "un"]
        .iter()
        .any(|needle| prefix.trim_end().ends_with(needle.trim_end()));
    let after = &haystack[pos + keyword.len()..haystack.len().min(pos + keyword.len() + 8)];
    if after.trim_start().starts_with("no") || after.trim_start().starts_with(": no") {
        return Some(false);
    }
    Some(!negated)
}

/// Map an ownership row (`fabcli ownership`, single or batch element).
pub fn ownership_row(row: &Value) -> Option<Ownership> {
    let listing_id = row
        .get("listingUid")
        .or_else(|| row.get("uid"))
        .and_then(Value::as_str)?
        .to_string();
    let state = row.get("state");
    Some(Ownership {
        listing_id,
        owned: row.get("owned").and_then(Value::as_bool),
        entitlement_id: state
            .and_then(|s| s.get("entitlementId"))
            .and_then(Value::as_str)
            .and_then(sanitize::short),
        licenses: state
            .and_then(|s| s.get("ownership"))
            .and_then(|o| o.get("licenses"))
            .and_then(Value::as_array)
            .map(|licenses| {
                licenses
                    .iter()
                    .filter_map(|l| {
                        l.get("name")
                            .or_else(|| l.get("slug"))
                            .and_then(Value::as_str)
                            .and_then(sanitize::short)
                    })
                    .collect()
            })
            .unwrap_or_default(),
        wishlisted: state
            .and_then(|s| s.get("wishlisted"))
            .and_then(Value::as_bool),
        source: row
            .get("source")
            .and_then(Value::as_str)
            .and_then(sanitize::short),
    })
}

/// Map `fabcli ownership` output in either single or batch shape.
pub fn ownership_response(value: &Value) -> Result<Vec<Ownership>> {
    if let Some(rows) = value.get("results").and_then(Value::as_array) {
        return Ok(rows.iter().filter_map(ownership_row).collect());
    }
    ownership_row(value).map(|row| vec![row]).ok_or_else(|| {
        FabError::new(
            ErrorCode::ProviderProtocol,
            "ownership response had neither 'results' nor a listing row",
        )
        .with_provider(PROVIDER)
    })
}

/// Map `fabcli library` output into owned assets.
///
/// Library entries are Epic catalog records, not Fab listings: they carry the
/// listing uid in `customAttributes.ListingIdentifier`. Entries without one
/// keep their Epic `assetId` as the identifier and are marked so callers do
/// not try to `inspect` them.
pub fn library_assets(value: &Value, include_raw: bool) -> Result<Vec<Asset>> {
    let rows = value
        .get("results")
        .and_then(Value::as_array)
        .ok_or_else(|| {
            FabError::new(
                ErrorCode::ProviderProtocol,
                "library response has no 'results' array",
            )
            .with_provider(PROVIDER)
        })?;

    Ok(rows
        .iter()
        .filter_map(|row| library_asset(row, include_raw))
        .collect())
}

fn library_asset(row: &Value, include_raw: bool) -> Option<Asset> {
    let listing_uid = row
        .get("customAttributes")
        .and_then(Value::as_array)
        .and_then(|attrs| {
            attrs
                .iter()
                .find_map(|a| a.get("ListingIdentifier").and_then(Value::as_str))
        })
        .map(str::to_string);
    let asset_id = row
        .get("assetId")
        .and_then(Value::as_str)
        .map(str::to_string);
    // Same rule as search rows: an id that could not safely become an argument
    // or a directory name drops the row.
    let id = listing_uid
        .clone()
        .or(asset_id)
        .and_then(|id| crate::model::validate_listing_id(&id).ok())?;
    let listing_uid = listing_uid.filter(|uid| uid == &id);

    let mut asset = Asset::new(&id, PROVIDER);
    asset.title = row
        .get("title")
        .and_then(Value::as_str)
        .and_then(sanitize::short);
    // The library endpoint fills `description` with the title for almost
    // every entry; a copy of the title is no description at all.
    asset.description = row
        .get("description")
        .and_then(Value::as_str)
        .and_then(description_text)
        .filter(|d| Some(d) != asset.title.as_ref());
    asset.url = row
        .get("url")
        .and_then(Value::as_str)
        .map(str::to_string)
        .or_else(|| listing_uid.as_deref().map(Asset::fab_url));
    asset.owned = Some(true);
    asset.coverage.ownership = Availability::Available;
    asset.detail_level = Some(DetailLevel::Summary);
    asset.category = row
        .get("categories")
        .and_then(Value::as_array)
        .and_then(|cats| cats.first())
        .map(|c| Category {
            name: c
                .get("name")
                .and_then(Value::as_str)
                .and_then(sanitize::short),
            slug: c
                .get("id")
                .and_then(Value::as_str)
                .and_then(sanitize::short),
            path: None,
        });
    asset.thumbnail = row
        .get("images")
        .and_then(Value::as_array)
        .and_then(|images| images.first())
        .and_then(|i| i.get("url"))
        .and_then(Value::as_str)
        .map(str::to_string);

    let mut engine_versions = Vec::new();
    let mut platforms = Vec::new();
    if let Some(versions) = row.get("projectVersions").and_then(Value::as_array) {
        for version in versions {
            collect_strings(version.get("engineVersions"), &mut engine_versions);
            collect_strings(version.get("targetPlatforms"), &mut platforms);
        }
    }
    dedupe(&mut engine_versions);
    dedupe(&mut platforms);
    // Library engine versions are Epic's `UE_x.y` labels, so their presence
    // identifies the entry as an Unreal distribution. No other engine appears
    // in this endpoint today.
    if !engine_versions.is_empty() {
        asset.engines = vec![Engine::Unreal];
    }
    asset.engine_versions = engine_versions;
    asset.platforms = platforms;
    if let Some(method) = row.get("distributionMethod").and_then(Value::as_str) {
        asset.formats.push(AssetFormat {
            code: None,
            name: None,
            distribution_method: sanitize::short(method),
            engine_versions: asset.engine_versions.clone(),
            platforms: asset.platforms.clone(),
        });
    }
    asset.coverage.formats = if asset.formats.is_empty() {
        Availability::Unavailable
    } else {
        Availability::Available
    };
    // The library endpoint reports no prices; owned assets have already been
    // paid for or claimed, which is not the same as being free to acquire.
    asset.coverage.pricing = Availability::NotRequested;
    if include_raw {
        asset.raw = Some(row.clone());
    }
    Some(asset)
}

/// Map `fabcli claim` output.
///
/// FabCLI reports a refused paid claim as a successful command with
/// `ok:false, reason:"not_free"`; necturalabs-fab turns that into a hard error so
/// an agent cannot mistake it for a claim that happened.
pub fn claim_outcome(value: &Value, listing_id: &str) -> Result<ClaimOutcome> {
    let ok = value.get("ok").and_then(Value::as_bool).unwrap_or(false);
    if !ok {
        let reason = value
            .get("reason")
            .and_then(Value::as_str)
            .unwrap_or("unknown");
        if reason == "not_free" {
            let price = value.get("price").and_then(Value::as_f64);
            let currency = value.get("currency").and_then(Value::as_str).unwrap_or("");
            return Err(FabError::new(
                ErrorCode::AssetNotFree,
                format!(
                    "listing {listing_id} is not free ({}{}) and necturalabs-fab never purchases",
                    price.map(|p| format!("{p:.2} ")).unwrap_or_default(),
                    currency
                ),
            )
            .with_hint("buy it on fab.com yourself if you want it, then run download")
            .with_detail("listingId", Value::String(listing_id.to_string()))
            .with_detail("price", price.map(Value::from).unwrap_or(Value::Null))
            .with_detail("currency", Value::String(currency.to_string()))
            .with_provider(PROVIDER));
        }
        return Err(FabError::new(
            ErrorCode::ProviderFailed,
            format!("claim refused for {listing_id}: {reason}"),
        )
        .with_provider(PROVIDER));
    }

    Ok(ClaimOutcome {
        listing_id: listing_id.to_string(),
        claimed: value
            .get("claimed")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        already_owned: value
            .get("already_owned")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        title: value
            .get("title")
            .and_then(Value::as_str)
            .and_then(sanitize::short),
    })
}

/// Map `fabcli auth status` output.
pub fn auth_status(value: &Value) -> AuthStatus {
    let fab = value.get("fab");
    AuthStatus {
        authenticated: value
            .get("authenticated")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        expires_at: value
            .get("expires_at")
            .and_then(Value::as_str)
            .map(str::to_string),
        account_actions_available: fab
            .and_then(|f| f.get("session_present"))
            .and_then(Value::as_bool)
            .unwrap_or(false),
        account_session_expires_at: fab
            .and_then(|f| f.get("expires_at"))
            .and_then(Value::as_str)
            .map(str::to_string),
        account_session_days_remaining: fab
            .and_then(|f| f.get("days_remaining"))
            .and_then(Value::as_i64),
        // A missing account session is normal (it is only needed for claims
        // and ownership); only an expiring one that exists needs attention.
        needs_reauth: !value
            .get("authenticated")
            .and_then(Value::as_bool)
            .unwrap_or(false)
            || (fab
                .and_then(|f| f.get("session_present"))
                .and_then(Value::as_bool)
                .unwrap_or(false)
                && fab
                    .and_then(|f| f.get("needs_refresh"))
                    .and_then(Value::as_bool)
                    .unwrap_or(false)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn search_page_maps_identity_price_and_cursor() {
        let raw = json!({
            "results": [{
                "uid": "a55fc08e",
                "title": "Steam Integration",
                "listingType": "tool-and-plugin",
                "isFree": false,
                "isMature": false,
                "publishedAt": "2026-02-16T10:00:00Z",
                "user": {"sellerName": "PloxTools", "sellerId": "o-hz52h7n"},
                "category": {"name": "Engine Tools", "slug": "engine-tools", "path": "engine-tools"},
                "ratings": {"averageRating": 4.5, "total": 12},
                "startingPrice": {"price": 49.99, "currencyCode": "USD"},
                "tags": [{"name": "Steam", "slug": "steam"}],
                "thumbnails": [{"mediaUrl": "https://media.fab.com/img.jpg"}],
                "owned": true
            }],
            "count": 142,
            "cursors": {"next": "cD0y", "previous": null}
        });
        let page = search_page(&raw, false).unwrap();
        assert_eq!(page.total, Some(142));
        assert_eq!(page.next_cursor.as_deref(), Some("cD0y"));
        let asset = &page.assets[0];
        assert_eq!(asset.id, "a55fc08e");
        assert_eq!(
            asset.url.as_deref(),
            Some("https://www.fab.com/listings/a55fc08e")
        );
        assert_eq!(asset.kind, Some(AssetKind::Tool));
        assert_eq!(asset.price.amount, crate::model::Amount::parse("49.99"));
        assert_eq!(asset.price.free, Some(false));
        assert_eq!(asset.owned, Some(true));
        assert_eq!(asset.rating.average, Some(4.5));
        assert_eq!(asset.rating.count, Some(12));
        assert_eq!(asset.tags, vec!["steam"]);
        assert_eq!(asset.detail_level, Some(DetailLevel::Summary));
        assert!(asset.raw.is_none(), "raw is opt-in");
    }

    #[test]
    fn cursors_with_control_characters_are_dropped() {
        let raw = json!({"results": [], "cursors": {"next": "abc\u{1b}[2J"}});
        assert_eq!(search_page(&raw, false).unwrap().next_cursor, None);
        let raw = json!({"results": [], "cursors": {"next": "cD0yMDI2"}});
        assert_eq!(
            search_page(&raw, false).unwrap().next_cursor.as_deref(),
            Some("cD0yMDI2")
        );
    }

    #[test]
    fn rows_without_a_uid_are_dropped_not_faked() {
        let raw = json!({"results": [{"title": "no identity"}, {"uid": "--force"}, {"uid": "ok"}]});
        let page = search_page(&raw, false).unwrap();
        assert_eq!(page.assets.len(), 1);
        assert_eq!(page.assets[0].id, "ok");
    }

    #[test]
    fn missing_results_array_is_a_protocol_error() {
        let err = search_page(&json!({"unexpected": true}), false).unwrap_err();
        assert_eq!(err.code, ErrorCode::ProviderProtocol);
    }

    #[test]
    fn ownership_is_unknown_when_not_decorated() {
        let raw = json!({"results": [{"uid": "x"}]});
        let page = search_page(&raw, false).unwrap();
        assert_eq!(page.assets[0].owned, None);
        assert_eq!(
            page.assets[0].coverage.ownership,
            Availability::NotRequested
        );
    }

    #[test]
    fn free_definition_matches_the_providers() {
        // flagged free
        assert_eq!(price(Some(true), None).free, Some(true));
        // zero list price
        let p = price(
            Some(false),
            Some(&json!({"price": 0.0, "currencyCode": "USD"})),
        );
        assert_eq!(p.free, Some(true));
        // 100% discount: free now, but not permanently
        let p = price(
            Some(false),
            Some(&json!({"price": 29.99, "discountedPrice": 0.0, "discountPercentage": 100})),
        );
        assert_eq!(p.free, Some(true));
        assert_eq!(p.temporarily_free, Some(true));
        assert_eq!(p.amount, crate::model::Amount::parse("0.0"));
        assert_eq!(p.original, crate::model::Amount::parse("29.99"));
        // paid, discount unreported (live search rows): unknown, not "not free"
        let p = price(Some(false), Some(&json!({"price": 29.99})));
        assert_eq!(p.free, Some(false));
        assert_eq!(p.temporarily_free, None);
        // paid, discount reported and nonzero
        let p = price(
            Some(false),
            Some(&json!({"price": 29.99, "discountedPrice": 14.99})),
        );
        assert_eq!(p.temporarily_free, Some(false));
    }

    #[test]
    fn currency_is_recovered_from_a_self_consistent_price_tier() {
        // Fab search rows carry no currencyCode; the tier id embeds it.
        let sp = json!({"offerId": "o", "price": 149.99, "priceTierId": "abc123_USD_14999_1701881426024"});
        let p = price(Some(false), Some(&sp));
        assert_eq!(p.currency.as_deref(), Some("USD"));
        assert_eq!(p.amount, crate::model::Amount::parse("149.99"));
    }

    #[test]
    fn a_price_tier_that_disagrees_with_the_price_is_not_trusted() {
        let sp = json!({"price": 452.14, "priceTierId": "abc123_USD_14999_1701881426024"});
        assert_eq!(price(Some(false), Some(&sp)).currency, None);
        let sp = json!({"price": 1.0, "priceTierId": "garbage"});
        assert_eq!(price(Some(false), Some(&sp)).currency, None);
    }

    #[test]
    fn an_explicit_currency_code_wins_over_the_tier() {
        let sp = json!({"price": 452.14, "currencyCode": "ILS", "priceTierId": "abc_USD_14999_1"});
        assert_eq!(
            price(Some(false), Some(&sp)).currency.as_deref(),
            Some("ILS")
        );
    }

    #[test]
    fn structured_tech_details_are_preferred_over_seller_text() {
        let mut asset = Asset::new("uid", PROVIDER);
        let formats = json!([{
            "assetFormatType": {"code": "fbx", "name": "FBX"},
            "technicalDetails": "<ul><li>Textures 4K</li></ul>",
            "techDetails": {"animation": null, "threeDModel": {
                "animationTracksCount": 12,
                "hasRiggedAnimations": true,
                "materialsCount": 3,
                "texturesCount": 6,
                "uniqueMeshesCount": 2,
                "lodsCount": null,
                "isNaniteEnabled": false,
                "trianglesCountRange": {"bounds": "[)", "lower": 5120, "upper": 5121},
                "vertexCountRange": {"bounds": "[)", "lower": 2800, "upper": 2801},
                "textureResolutionRange": {"bounds": "[)", "lower": 2048, "upper": 2049}
            }},
            "versions": []
        }]);
        apply_formats(&mut asset, &formats);
        let t = &asset.technical;
        assert_eq!(t.source, Some(MetadataSource::Structured));
        assert_eq!(t.triangles, Some(5120));
        assert_eq!(t.vertices, Some(2800));
        assert_eq!(t.rigged, Some(true));
        assert_eq!(t.animated, Some(true));
        assert_eq!(t.animation_tracks, Some(12));
        assert_eq!(t.materials, Some(3));
        assert_eq!(t.textures, Some(6));
        assert_eq!(t.meshes, Some(2));
        assert_eq!(t.nanite, Some(false));
        assert_eq!(t.lods, None, "null stays unknown");
        assert_eq!(t.texture_resolutions, vec!["2048"]);
        assert_eq!(asset.coverage.technical, Availability::Available);
    }

    #[test]
    fn zero_placeholder_ranges_are_unknown_not_zero() {
        let mut asset = Asset::new("uid", PROVIDER);
        let formats = json!([{
            "assetFormatType": {"code": "blender"},
            "techDetails": {"threeDModel": {
                "trianglesCountRange": {"bounds": "[)", "lower": 0, "upper": 1},
                "textureResolutionRange": {"bounds": "[)", "lower": 0, "upper": 1},
                "vertexCountRange": {"bounds": "[)", "lower": 100, "upper": 500}
            }}
        }]);
        apply_formats(&mut asset, &formats);
        assert_eq!(asset.technical.triangles, None);
        assert!(asset.technical.texture_resolutions.is_empty());
        assert_eq!(
            asset.technical.vertices, None,
            "a real range is not an exact count"
        );
    }

    #[test]
    fn seller_html_is_reduced_to_text_before_parsing() {
        let mut asset = Asset::new("uid", PROVIDER);
        let formats = json!([{
            "assetFormatType": {"code": "unreal-engine"},
            "technicalDetails": null,
            "techDetails": {"threeDModel": {"additionalInformation":
                "<p><strong>Triangles:</strong> 12,000</p><p>Textures: 2048x2048 &amp; 1024x1024</p>"}}
        }]);
        apply_formats(&mut asset, &formats);
        let t = &asset.technical;
        assert_eq!(t.source, Some(MetadataSource::ParsedText));
        assert_eq!(t.triangles, Some(12000));
        assert_eq!(t.texture_resolutions, vec!["2048x2048", "1024x1024"]);
        assert!(
            !t.notes.clone().unwrap_or_default().contains('<'),
            "{:?}",
            t.notes
        );
    }

    #[test]
    fn absent_pricing_is_unknown_not_free() {
        let p = price(None, None);
        assert_eq!(p.free, None);
        assert_eq!(p.amount, None);
        assert!(!p.is_free());
    }

    #[test]
    fn formats_populate_engines_versions_and_platforms() {
        let mut asset = Asset::new("uid", PROVIDER);
        let formats = json!([
            {
                "assetFormatType": {"code": "unreal-engine", "name": "Unreal Engine"},
                "distributionMethod": "asset-pack",
                "technicalDetails": "Triangles: 12,000  Vertices: 8000  LODs: 3  Textures: 2048x2048",
                "versions": [
                    {"engineVersions": ["UE_5.4", "UE_5.5"], "targetPlatforms": ["Windows", "Linux"]},
                    {"engineVersions": ["UE_5.4"], "targetPlatforms": ["Windows"]}
                ]
            },
            {"assetFormatType": {"code": "fbx", "name": "FBX"}, "versions": []}
        ]);
        apply_formats(&mut asset, &formats);
        assert_eq!(asset.engines, vec![Engine::Unreal]);
        assert_eq!(asset.engine_versions, vec!["UE_5.4", "UE_5.5"]);
        assert_eq!(asset.platforms, vec!["Linux", "Windows"]);
        assert_eq!(asset.formats.len(), 2);
        assert_eq!(asset.coverage.formats, Availability::Available);
        assert_eq!(asset.technical.triangles, Some(12000));
        assert_eq!(asset.technical.vertices, Some(8000));
        assert_eq!(asset.technical.lods, Some(3));
        assert_eq!(asset.technical.texture_resolutions, vec!["2048x2048"]);
        assert_eq!(asset.technical.source, Some(MetadataSource::ParsedText));
    }

    #[test]
    fn formats_that_are_not_an_array_mark_coverage_unavailable() {
        let mut asset = Asset::new("uid", PROVIDER);
        apply_formats(&mut asset, &json!({"unexpected": "shape"}));
        assert_eq!(asset.coverage.formats, Availability::Unavailable);
        assert!(asset.engines.is_empty());
    }

    #[test]
    fn technical_text_without_facts_yields_nothing() {
        let meta = technical_from_text("A lovely pack of assets for your game.");
        assert!(meta.triangles.is_none());
        assert!(meta.texture_resolutions.is_empty());
    }

    #[test]
    fn technical_text_honours_negation() {
        let yes = technical_from_text("Characters are rigged and animated");
        assert_eq!(yes.rigged, Some(true));
        assert_eq!(yes.animated, Some(true));
        let no = technical_from_text("Meshes are not rigged, no animations included");
        assert_eq!(no.rigged, Some(false));
        assert_eq!(no.animated, Some(false));
    }

    #[test]
    fn technical_text_distinguishes_skeletal_from_static() {
        assert_eq!(
            technical_from_text("Skeletal meshes included").skeletal,
            Some(true)
        );
        assert_eq!(
            technical_from_text("Static mesh only").skeletal,
            Some(false)
        );
        assert_eq!(technical_from_text("Nothing stated").skeletal, None);
    }

    #[test]
    fn four_k_shorthand_is_not_invented_into_a_resolution() {
        let meta = technical_from_text("Textures are 4K PBR");
        assert!(meta.texture_resolutions.is_empty());
    }

    #[test]
    fn ownership_single_and_batch_shapes_both_map() {
        let single = json!({
            "listingUid": "abc",
            "owned": true,
            "source": "fab_session",
            "state": {"acquired": true, "entitlementId": "ent-1", "wishlisted": false,
                      "ownership": {"licenses": [{"name": "Standard License"}]}}
        });
        let rows = ownership_response(&single).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].owned, Some(true));
        assert_eq!(rows[0].entitlement_id.as_deref(), Some("ent-1"));
        assert_eq!(rows[0].licenses, vec!["Standard License"]);

        let batch = json!({"ok": true, "results": [single.clone(), {"listingUid": "def", "owned": false}], "meta": {"total": 2}});
        let rows = ownership_response(&batch).unwrap();
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[1].owned, Some(false));
        assert!(rows[1].licenses.is_empty());
    }

    #[test]
    fn listing_descriptions_arrive_as_plain_text() {
        let raw = json!({
            "uid": "listing-1",
            "title": "Cathedral",
            "description": "<h4><strong>Watch </strong><a href=\"https://youtu.be/x\">Trailer</a></h4><p>Modular &amp; <u>easy</u> to assemble.</p>"
        });
        let asset = listing_detail(&raw, false).unwrap();
        let description = asset.description.unwrap();
        assert!(!description.contains('<'), "{description}");
        assert!(description.contains("Watch Trailer"), "{description}");
        assert!(
            description.contains("Modular & easy to assemble."),
            "{description}"
        );
    }

    #[test]
    fn library_descriptions_arrive_as_plain_text() {
        let raw = json!({"results": [{
            "assetId": "a", "title": "Rocks",
            "description": "<p>Hand-painted <b>rocks</b> &amp; cliffs</p>",
            "customAttributes": [{"ListingIdentifier": "listing-1"}]
        }]});
        let assets = library_assets(&raw, false).unwrap();
        assert_eq!(
            assets[0].description.as_deref(),
            Some("Hand-painted rocks & cliffs")
        );
    }

    #[test]
    fn library_entries_use_the_listing_uid_and_are_owned() {
        let raw = json!({
            "cursors": {"next": null},
            "results": [{
                "assetId": "epic-asset-1",
                "assetNamespace": "ns",
                "title": "Castle Pack",
                "description": "Ruined castle",
                "url": "https://www.fab.com/listings/listing-1",
                "distributionMethod": "ASSET_PACK",
                "categories": [{"id": "environments", "name": "Environments"}],
                "customAttributes": [{"ListingIdentifier": "listing-1"}],
                "images": [{"url": "https://media.fab.com/a.jpg", "height": "480", "width": "640", "type": "t", "uploadedDate": "x"}],
                "projectVersions": [
                    {"artifactId": "art-1", "engineVersions": ["UE_5.4"], "targetPlatforms": ["Windows"], "buildVersions": []}
                ]
            }]
        });
        let assets = library_assets(&raw, false).unwrap();
        assert_eq!(assets.len(), 1);
        let asset = &assets[0];
        assert_eq!(asset.id, "listing-1");
        assert_eq!(asset.owned, Some(true));
        assert_eq!(asset.engines, vec![Engine::Unreal]);
        assert_eq!(asset.engine_versions, vec!["UE_5.4"]);
        assert_eq!(asset.coverage.pricing, Availability::NotRequested);
    }

    #[test]
    fn a_refused_paid_claim_is_an_error_not_a_success() {
        let raw = json!({"ok": false, "reason": "not_free", "uid": "u", "title": "Paid", "price": 29.99, "currency": "USD"});
        let err = claim_outcome(&raw, "u").unwrap_err();
        assert_eq!(err.code, ErrorCode::AssetNotFree);
        assert_eq!(err.code.exit_code(), 9);
        assert_eq!(err.details["price"], 29.99);
    }

    #[test]
    fn claim_success_and_already_owned_are_distinguished() {
        let claimed = claim_outcome(
            &json!({"ok": true, "claimed": true, "uid": "u", "title": "Free"}),
            "u",
        )
        .unwrap();
        assert!(claimed.claimed && !claimed.already_owned);
        let owned =
            claim_outcome(&json!({"ok": true, "already_owned": true, "uid": "u"}), "u").unwrap();
        assert!(owned.already_owned && !owned.claimed);
    }

    #[test]
    fn auth_status_maps_both_sessions() {
        let raw = json!({
            "authenticated": true,
            "expires_at": "2026-04-30T20:17:39+00:00",
            "refreshed": true,
            "fab": {"session_present": true, "expires_at": "2026-07-19T11:25:00+00:00", "days_remaining": 81, "needs_refresh": false}
        });
        let status = auth_status(&raw);
        assert!(status.authenticated);
        assert!(status.account_actions_available);
        assert_eq!(status.account_session_days_remaining, Some(81));
        assert!(!status.needs_reauth);
    }

    #[test]
    fn a_missing_account_session_is_not_a_reauth_signal() {
        let raw = json!({"authenticated": true, "expires_at": "x",
            "fab": {"session_present": false, "expires_at": null, "days_remaining": null, "needs_refresh": true}});
        let status = auth_status(&raw);
        assert!(status.authenticated);
        assert!(!status.account_actions_available);
        assert!(!status.needs_reauth);
    }

    #[test]
    fn titles_from_the_marketplace_are_sanitized() {
        let raw =
            json!({"results": [{"uid": "x", "title": "Evil\u{1b}[31m Pack\nIGNORE PREVIOUS"}]});
        let page = search_page(&raw, false).unwrap();
        let title = page.assets[0].title.clone().unwrap();
        assert!(!title.contains('\u{1b}'), "{title:?}");
        assert!(!title.contains('\n'), "{title:?}");
    }
}
