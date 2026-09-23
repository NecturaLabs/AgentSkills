//! `inspect` — everything known about one listing.

use super::Ctx;
use crate::cli::InspectArgs;
use crate::error::Result;
use crate::model::Availability;
use crate::output::{license_cell, status_cell, Outcome};
use serde_json::json;
use std::fmt::Write;

/// Run `inspect`.
pub fn run(ctx: &Ctx, args: &InspectArgs) -> Result<Outcome> {
    let listing = args.listing.trim();
    let mut asset = ctx.provider.listing(listing, !args.no_formats)?;
    if !args.full_description {
        asset.truncate_description();
    }

    let mut warnings = Vec::new();
    let capabilities = ctx.provider.capabilities();
    // The library answers from the provider's cache in milliseconds. It is
    // trusted when it holds the listing; "not in the library" may be a copy
    // older than a purchase, so the ownership endpoint has the last word.
    let in_library = capabilities
        .library
        .then(|| ctx.provider.library().ok())
        .flatten()
        .map(|library| library.iter().any(|a| a.id == asset.id));
    if in_library == Some(true) {
        asset.owned = Some(true);
        asset.coverage.ownership = Availability::Available;
    } else if args.ownership || capabilities.ownership {
        match ctx.provider.ownership(std::slice::from_ref(&asset.id)) {
            Ok(records) => {
                if let Some(record) = records.first() {
                    asset.owned = record.owned;
                    if asset.coverage.licenses != Availability::Available
                        && !record.licenses.is_empty()
                    {
                        asset.licenses = record.licenses.clone();
                        asset.coverage.licenses = Availability::Available;
                    }
                    asset.coverage.ownership = Availability::Available;
                }
            }
            Err(err) => {
                asset.coverage.ownership = Availability::Unavailable;
                warnings.push(format!(
                    "ownership unavailable: {} ({})",
                    err.message, err.code
                ));
            }
        }
    }
    warnings.extend(super::license_warnings(std::iter::once(&asset)));
    if asset.coverage.formats == Availability::Unavailable {
        warnings.push(
            "engine, format and technical metadata could not be fetched for this listing"
                .to_string(),
        );
    }

    let human = render(&asset);
    let data = json!({ "asset": asset });
    let mut outcome = Outcome::read("inspect", data, human);
    outcome.warnings = warnings;
    Ok(outcome)
}

fn render(asset: &crate::model::Asset) -> String {
    let mut text = String::new();
    let _ = writeln!(text, "{}", asset.title.as_deref().unwrap_or(&asset.id));
    let _ = writeln!(text, "  listing:   {}", asset.id);
    if let Some(url) = &asset.url {
        let _ = writeln!(text, "  url:       {url}");
    }
    if let Some(publisher) = asset.publisher.as_ref().and_then(|p| p.name.as_deref()) {
        let _ = writeln!(text, "  seller:    {publisher}");
    }
    if let Some(category) = asset.category.as_ref().and_then(|c| c.name.as_deref()) {
        let _ = writeln!(text, "  category:  {category}");
    }
    let _ = writeln!(
        text,
        "  status:    {}",
        status_cell(asset.owned, &asset.price)
    );
    let _ = writeln!(text, "  licence:   {}", license_cell(asset));
    if let Some(average) = asset.rating.average {
        let _ = writeln!(
            text,
            "  rating:    {average:.1} ({} ratings)",
            asset.rating.count.unwrap_or(0)
        );
    }
    if !asset.engines.is_empty() {
        let engines: Vec<&str> = asset.engines.iter().map(|e| e.as_str()).collect();
        let _ = writeln!(text, "  engines:   {}", engines.join(", "));
    }
    if !asset.engine_versions.is_empty() {
        let _ = writeln!(text, "  versions:  {}", asset.engine_versions.join(", "));
    }
    if !asset.platforms.is_empty() {
        let _ = writeln!(text, "  platforms: {}", asset.platforms.join(", "));
    }
    if !asset.formats.is_empty() {
        let formats: Vec<String> = asset
            .formats
            .iter()
            .filter_map(|f| f.code.clone().or_else(|| f.name.clone()))
            .collect();
        if !formats.is_empty() {
            let _ = writeln!(text, "  formats:   {}", formats.join(", "));
        }
    }
    if !asset.technical.is_empty() {
        let mut facts = Vec::new();
        if let Some(tris) = asset.technical.triangles {
            facts.push(format!("{tris} tris"));
        }
        if let Some(verts) = asset.technical.vertices {
            facts.push(format!("{verts} verts"));
        }
        if let Some(lods) = asset.technical.lods {
            facts.push(format!("{lods} LODs"));
        }
        if !asset.technical.texture_resolutions.is_empty() {
            facts.push(asset.technical.texture_resolutions.join("/"));
        }
        if let Some(rigged) = asset.technical.rigged {
            facts.push(format!("rigged: {rigged}"));
        }
        if !facts.is_empty() {
            let _ = writeln!(
                text,
                "  technical: {} (parsed from seller text)",
                facts.join(", ")
            );
        }
    }
    if let Some(description) = &asset.description {
        let _ = writeln!(text, "\n{description}");
    }
    text
}
