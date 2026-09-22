//! `ownership` — does this account own these listings?

use super::Ctx;
use crate::cli::OwnershipArgs;
use crate::error::Result;
use crate::output::{owned_cell, table, Outcome};
use serde_json::json;

/// Run `ownership`.
pub fn run(ctx: &Ctx, args: &OwnershipArgs) -> Result<Outcome> {
    let ids: Vec<String> = args
        .listings
        .iter()
        .map(|id| id.trim().to_string())
        .collect();
    let records = ctx.provider.ownership(&ids)?;

    let owned = records.iter().filter(|r| r.owned == Some(true)).count();
    let data = json!({
        "results": records,
        "requested": ids.len(),
        "owned": owned,
    });

    let rows: Vec<Vec<String>> = records
        .iter()
        .map(|record| {
            vec![
                record.listing_id.clone(),
                owned_cell(record.owned),
                if record.licenses.is_empty() {
                    "-".into()
                } else {
                    record.licenses.join(", ")
                },
            ]
        })
        .collect();
    let human = format!(
        "{}\n{owned} of {} owned.",
        table(&["LISTING", "OWNED", "LICENSES"], &rows),
        ids.len()
    );

    Ok(Outcome::read("ownership", data, human))
}
