//! The response envelope and the two renderings of it.
//!
//! Machine mode writes exactly one JSON document to stdout and nothing else,
//! ever: warnings live inside the envelope, progress goes to stderr, and no
//! ANSI sequence is emitted. Human mode writes plain text tables to stdout and
//! warnings to stderr.

use crate::approval::ActionPlan;
use crate::config::OutputMode;
use crate::error::FabError;
use serde::Serialize;
use serde_json::{json, Map, Value};
use std::io::{IsTerminal, Write};

/// Everything a command produces.
pub struct Outcome {
    /// Machine payload, placed at `data`.
    pub data: Value,
    /// Human rendering, used only in human mode.
    pub human: String,
    /// Non-fatal observations. Emitted in both modes.
    pub warnings: Vec<String>,
    /// What the command did or would do.
    pub action: ActionPlan,
}

impl Outcome {
    /// A read-only outcome with no warnings.
    pub fn read(command: &str, data: Value, human: impl Into<String>) -> Self {
        Self {
            data,
            human: human.into(),
            warnings: Vec::new(),
            action: ActionPlan::read(command),
        }
    }

    /// Attach a warning.
    pub fn warn(mut self, warning: impl Into<String>) -> Self {
        self.warnings.push(warning.into());
        self
    }

    /// Replace the action plan.
    pub fn with_action(mut self, action: ActionPlan) -> Self {
        self.action = action;
        self
    }
}

/// Envelope metadata common to every response.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Meta {
    /// necturalabs-fab's version.
    pub version: String,
    /// Active provider id.
    pub provider: String,
    /// Backing implementation version, when known.
    pub provider_version: Option<String>,
    /// Wall-clock duration of the command.
    pub elapsed_ms: u64,
}

/// Decides how to render and writes the result.
pub struct Renderer {
    mode: OutputMode,
    quiet: bool,
    stdout_is_terminal: bool,
}

impl Renderer {
    /// Build a renderer for `mode`.
    pub fn new(mode: OutputMode, quiet: bool) -> Self {
        Self {
            mode,
            quiet,
            stdout_is_terminal: std::io::stdout().is_terminal(),
        }
    }

    /// Override terminal detection. Tests use this; so does `--json`.
    pub fn with_terminal(mut self, is_terminal: bool) -> Self {
        self.stdout_is_terminal = is_terminal;
        self
    }

    /// Whether output will be JSON.
    pub fn is_json(&self) -> bool {
        match self.mode {
            OutputMode::Json => true,
            OutputMode::Human => false,
            OutputMode::Auto => !self.stdout_is_terminal,
        }
    }

    /// Whether progress may be written to stderr.
    pub fn wants_progress(&self) -> bool {
        !self.quiet && !self.is_json()
    }

    /// Render a successful command.
    pub fn success(&self, command: &str, outcome: &Outcome, meta: &Meta) -> String {
        if self.is_json() {
            let envelope = json!({
                "ok": true,
                "command": command,
                "requiresApproval": outcome.action.requires_approval,
                "action": outcome.action,
                "data": outcome.data,
                "warnings": outcome.warnings,
                "meta": meta,
            });
            return to_line(&envelope);
        }
        let mut text = outcome.human.clone();
        if !text.ends_with('\n') {
            text.push('\n');
        }
        text
    }

    /// Render a failure.
    pub fn failure(
        &self,
        command: &str,
        action: &ActionPlan,
        error: &FabError,
        meta: &Meta,
    ) -> String {
        if self.is_json() {
            let requires_approval = error.code == crate::error::ErrorCode::ApprovalRequired;
            let envelope = json!({
                "ok": false,
                "command": command,
                "requiresApproval": requires_approval,
                "action": action,
                "error": error.to_json(),
                "warnings": [],
                "meta": meta,
            });
            return to_line(&envelope);
        }
        let mut text = format!("error [{}]: {}\n", error.code, error.message);
        if let Some(hint) = &error.hint {
            text.push_str(&format!("hint: {hint}\n"));
        }
        text
    }

    /// Write a rendered document to stdout.
    pub fn write_stdout(&self, rendered: &str) {
        let mut out = std::io::stdout().lock();
        let _ = out.write_all(rendered.as_bytes());
        let _ = out.flush();
    }

    /// Write a failure to the correct stream: stdout in machine mode (it is
    /// the response), stderr in human mode (it is a message).
    pub fn write_failure(&self, rendered: &str) {
        if self.is_json() {
            self.write_stdout(rendered);
        } else {
            let mut err = std::io::stderr().lock();
            let _ = err.write_all(rendered.as_bytes());
            let _ = err.flush();
        }
    }

    /// Emit warnings on stderr in human mode. In machine mode they travel
    /// inside the envelope and must not be duplicated.
    pub fn write_warnings(&self, warnings: &[String]) {
        if self.is_json() || self.quiet {
            return;
        }
        let mut err = std::io::stderr().lock();
        for warning in warnings {
            let _ = writeln!(err, "warning: {warning}");
        }
    }
}

fn to_line(value: &Value) -> String {
    let mut text = serde_json::to_string(value).unwrap_or_else(|_| {
        "{\"ok\":false,\"error\":{\"code\":\"FAB_INTERNAL\",\"message\":\"response serialization failed\"}}".to_string()
    });
    text.push('\n');
    text
}

/// Render a fixed-width text table with a header row.
///
/// Plain ASCII, no colour: the output is frequently piped, and an escape
/// sequence in a title must never reach a terminal through us.
pub fn table(headers: &[&str], rows: &[Vec<String>]) -> String {
    if rows.is_empty() {
        return String::new();
    }
    let mut widths: Vec<usize> = headers.iter().map(|h| h.chars().count()).collect();
    for row in rows {
        for (idx, cell) in row.iter().enumerate() {
            if idx < widths.len() {
                widths[idx] = widths[idx].max(cell.chars().count());
            }
        }
    }
    let mut out = String::new();
    for (idx, header) in headers.iter().enumerate() {
        pad_into(&mut out, header, widths[idx], idx + 1 == headers.len());
    }
    out.push('\n');
    for (idx, width) in widths.iter().enumerate() {
        pad_into(
            &mut out,
            &"-".repeat(*width),
            *width,
            idx + 1 == widths.len(),
        );
    }
    out.push('\n');
    for row in rows {
        for (idx, cell) in row.iter().enumerate() {
            if idx < widths.len() {
                pad_into(&mut out, cell, widths[idx], idx + 1 == row.len());
            }
        }
        out.push('\n');
    }
    out
}

fn pad_into(out: &mut String, cell: &str, width: usize, last: bool) {
    out.push_str(cell);
    if !last {
        let count = cell.chars().count();
        out.push_str(&" ".repeat(width.saturating_sub(count) + 2));
    }
}

/// Human-readable price cell.
pub fn price_cell(price: &crate::model::Price) -> String {
    match (price.free, price.amount) {
        (Some(true), _) => {
            if price.temporarily_free == Some(true) {
                "free (promo)".into()
            } else {
                "free".into()
            }
        }
        (_, Some(amount)) => format!(
            "{amount} {}",
            price.currency.as_deref().unwrap_or("").trim()
        )
        .trim()
        .to_string(),
        _ => "?".into(),
    }
}

/// Ownership and price in one cell: an owned asset's price is not news.
pub fn status_cell(owned: Option<bool>, price: &crate::model::Price) -> String {
    match owned {
        Some(true) => "owned".into(),
        Some(false) => price_cell(price),
        None => format!("{} (owned?)", price_cell(price)),
    }
}

/// Licences in one cell, the Standard License tiers by tier name alone.
pub fn license_cell(licenses: &[String]) -> String {
    if licenses.is_empty() {
        return "?".into();
    }
    licenses
        .iter()
        .map(|name| {
            name.strip_prefix("Standard License (")
                .and_then(|tier| tier.strip_suffix(')'))
                .unwrap_or(name)
        })
        .collect::<Vec<_>>()
        .join(", ")
}

/// Human-readable ownership cell.
pub fn owned_cell(owned: Option<bool>) -> String {
    match owned {
        Some(true) => "yes".into(),
        Some(false) => "no".into(),
        None => "?".into(),
    }
}

/// Truncate a cell so a table stays readable.
pub fn cell(text: Option<&str>, width: usize) -> String {
    let Some(text) = text else {
        return "-".into();
    };
    if text.chars().count() <= width {
        return text.to_string();
    }
    let kept: String = text.chars().take(width.saturating_sub(1)).collect();
    format!("{kept}…")
}

/// Extra fields merged into an envelope's `meta`. Used by commands that need
/// to report provider state alongside their data.
pub fn merge_meta(meta: &Meta, extra: &[(&str, Value)]) -> Value {
    let mut value = serde_json::to_value(meta).unwrap_or(Value::Object(Map::new()));
    if let Some(map) = value.as_object_mut() {
        for (key, item) in extra {
            map.insert((*key).to_string(), item.clone());
        }
    }
    value
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::error::ErrorCode;

    fn meta() -> Meta {
        Meta {
            version: "0.1.0".into(),
            provider: "fabcli".into(),
            provider_version: Some("0.1.0".into()),
            elapsed_ms: 12,
        }
    }

    fn json_renderer() -> Renderer {
        Renderer::new(OutputMode::Json, false)
    }

    #[test]
    fn machine_mode_emits_exactly_one_json_line() {
        let outcome = Outcome::read("search", json!({"results": []}), "no results");
        let rendered = json_renderer().success("search", &outcome, &meta());
        assert_eq!(rendered.matches('\n').count(), 1);
        assert!(rendered.ends_with('\n'));
        let parsed: Value = serde_json::from_str(rendered.trim()).unwrap();
        assert_eq!(parsed["ok"], true);
        assert_eq!(parsed["command"], "search");
        assert_eq!(parsed["requiresApproval"], false);
        assert_eq!(parsed["meta"]["provider"], "fabcli");
    }

    #[test]
    fn warnings_ride_inside_the_envelope_in_machine_mode() {
        let outcome = Outcome::read("search", json!({}), "").warn("ownership unavailable");
        let rendered = json_renderer().success("search", &outcome, &meta());
        let parsed: Value = serde_json::from_str(rendered.trim()).unwrap();
        assert_eq!(parsed["warnings"][0], "ownership unavailable");
    }

    #[test]
    fn errors_render_as_a_json_envelope_with_the_code() {
        let error = FabError::new(ErrorCode::AuthRequired, "no session").with_hint("sign in");
        let rendered =
            json_renderer().failure("library", &ActionPlan::read("library"), &error, &meta());
        let parsed: Value = serde_json::from_str(rendered.trim()).unwrap();
        assert_eq!(parsed["ok"], false);
        assert_eq!(parsed["error"]["code"], "FAB_AUTH_REQUIRED");
        assert_eq!(parsed["error"]["hint"], "sign in");
        assert_eq!(parsed["requiresApproval"], false);
    }

    #[test]
    fn approval_errors_set_the_top_level_flag() {
        let error = FabError::new(ErrorCode::ApprovalRequired, "needs approval");
        let rendered =
            json_renderer().failure("claim", &ActionPlan::read("claim"), &error, &meta());
        let parsed: Value = serde_json::from_str(rendered.trim()).unwrap();
        assert_eq!(parsed["requiresApproval"], true);
    }

    #[test]
    fn human_mode_prints_the_text_rendering_only() {
        let renderer = Renderer::new(OutputMode::Human, false);
        let outcome = Outcome::read("search", json!({"hidden": true}), "2 results");
        let rendered = renderer.success("search", &outcome, &meta());
        assert_eq!(rendered, "2 results\n");
        assert!(!rendered.contains("hidden"));
    }

    #[test]
    fn auto_mode_follows_the_terminal() {
        let piped = Renderer::new(OutputMode::Auto, false).with_terminal(false);
        assert!(piped.is_json());
        let tty = Renderer::new(OutputMode::Auto, false).with_terminal(true);
        assert!(!tty.is_json());
    }

    #[test]
    fn tables_align_and_stay_ascii() {
        let text = table(
            &["ID", "TITLE"],
            &[
                vec!["a".into(), "Short".into()],
                vec!["bbbb".into(), "Longer title".into()],
            ],
        );
        assert!(text.contains("ID    TITLE"), "{text}");
        assert!(!text.contains('\u{1b}'));
    }

    #[test]
    fn an_owned_asset_shows_no_price() {
        use crate::model::{Amount, Price};
        let price = Price {
            amount: Amount::parse("89.99"),
            currency: Some("USD".into()),
            ..Default::default()
        };
        assert!(!status_cell(Some(true), &price).contains("89.99"));
        assert!(status_cell(Some(false), &price).contains("89.99"));
        assert!(status_cell(None, &price).contains("89.99"));
    }

    #[test]
    fn licence_cell_names_the_standard_tiers_and_says_unknown() {
        assert_eq!(license_cell(&[]), "?");
        assert_eq!(
            license_cell(&[
                "Standard License (Personal)".into(),
                "Standard License (Professional)".into()
            ]),
            "Personal, Professional"
        );
        assert_eq!(license_cell(&["CC BY 4.0".into()]), "CC BY 4.0");
    }

    #[test]
    fn price_and_ownership_cells_say_unknown_rather_than_guessing() {
        use crate::model::Price;
        assert_eq!(price_cell(&Price::default()), "?");
        assert_eq!(owned_cell(None), "?");
        assert_eq!(
            price_cell(&Price {
                free: Some(true),
                temporarily_free: Some(true),
                ..Default::default()
            }),
            "free (promo)"
        );
    }
}
