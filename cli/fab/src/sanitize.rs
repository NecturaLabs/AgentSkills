//! Defences applied to text that necturalabs-fab did not author.
//!
//! Two different jobs:
//!
//! * [`text`] cleans marketplace-supplied strings (titles, descriptions, seller
//!   names). They are third-party data displayed to — and reasoned over by — an
//!   agent, so they must not be able to smuggle terminal escapes or invisible
//!   control characters into output an operator reads.
//! * [`redact`] scrubs credential-shaped substrings out of provider diagnostics
//!   before they are echoed anywhere.

/// Longest description necturalabs-fab emits unless the caller asks for the full text.
pub const DESCRIPTION_LIMIT: usize = 600;

/// Longest single short string (titles, seller names, tags).
pub const SHORT_LIMIT: usize = 200;

/// Normalize untrusted text: drop control characters and ANSI escapes, collapse
/// runs of whitespace, trim, and truncate to `limit` characters (ellipsised).
///
/// Returns `None` for input that is empty once cleaned, so a blank upstream
/// field becomes an explicit `null` rather than an empty string.
pub fn text(raw: &str, limit: usize) -> Option<String> {
    let mut out = String::with_capacity(raw.len().min(limit + 1));
    let mut chars = raw.chars().peekable();
    let mut pending_space = false;

    while let Some(ch) = chars.next() {
        // Swallow CSI / OSC sequences wholesale rather than leaving the payload.
        if ch == '\u{1b}' {
            match chars.peek() {
                Some('[') => {
                    chars.next();
                    for c in chars.by_ref() {
                        if ('\u{40}'..='\u{7e}').contains(&c) {
                            break;
                        }
                    }
                }
                Some(']') => {
                    chars.next();
                    for c in chars.by_ref() {
                        if c == '\u{7}' || c == '\u{1b}' {
                            break;
                        }
                    }
                }
                _ => {}
            }
            continue;
        }
        if ch.is_whitespace() {
            pending_space = !out.is_empty();
            continue;
        }
        // Control characters and the bidi/zero-width family never survive.
        if ch.is_control()
            || matches!(ch, '\u{200b}'..='\u{200f}' | '\u{202a}'..='\u{202e}' | '\u{2066}'..='\u{2069}' | '\u{feff}')
        {
            continue;
        }
        if pending_space {
            out.push(' ');
            pending_space = false;
        }
        out.push(ch);
    }

    if out.is_empty() {
        return None;
    }
    if out.chars().count() > limit {
        let truncated: String = out.chars().take(limit.saturating_sub(1)).collect();
        return Some(format!("{}…", truncated.trim_end()));
    }
    Some(out)
}

/// [`text`] with the short-string limit.
pub fn short(raw: &str) -> Option<String> {
    text(raw, SHORT_LIMIT)
}

/// Replace credential-shaped substrings with `[redacted]`.
///
/// The input is split into word runs and the separators between them, and only
/// word runs are ever replaced, so the surrounding structure survives: a JSON
/// line stays valid JSON and a structured provider error stays parseable.
///
/// A word is redacted when it looks like a token on its own (a JWT, or a long
/// opaque mixed-case blob), or when it is the value following a
/// credential-named key (`token=`, `"refresh_token":`, `session_id 9f8e…`,
/// `Bearer …`). Over-redacting a diagnostic is cheap; leaking a session cookie
/// into a log is not. Prose such as "session expired" is left alone: a value
/// after a bare space must look like a secret (contain a digit, 8+ chars).
pub fn redact(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len());
    let mut previous_word: Option<&str> = None;
    let mut gap = String::new();
    let mut rest = raw;

    while !rest.is_empty() {
        let split = rest
            .char_indices()
            .find(|(_, c)| !is_word_char(*c))
            .map(|(i, _)| i)
            .unwrap_or(rest.len());
        if split == 0 {
            let ch = rest.chars().next().expect("non-empty");
            gap.push(ch);
            out.push(ch);
            rest = &rest[ch.len_utf8()..];
            continue;
        }
        let word = &rest[..split];
        rest = &rest[split..];
        let after_key = previous_word.is_some_and(is_secret_key);
        let assignment = gap.contains(['=', ':']);
        let bearer = previous_word.is_some_and(|w| w.eq_ignore_ascii_case("bearer"));
        let value_like = word.len() >= 8 && word.chars().any(|c| c.is_ascii_digit());
        let redact_it = looks_like_token(word)
            || (after_key
                && !gap.contains(['\n', ',', ';', '{', '}', '[', ']'])
                && (assignment || bearer || value_like));
        if redact_it {
            out.push_str("[redacted]");
        } else {
            out.push_str(word);
        }
        previous_word = Some(word);
        gap.clear();
    }
    out
}

fn is_word_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-' | '+' | '/' | '~')
}

fn is_secret_key(key: &str) -> bool {
    let lower = key.to_ascii_lowercase();
    [
        "token",
        "secret",
        "password",
        "passwd",
        "cookie",
        "session",
        "authorization",
        "credential",
        "bearer",
        "apikey",
        "api_key",
    ]
    .iter()
    .any(|needle| lower.contains(needle))
}

fn looks_like_token(word: &str) -> bool {
    if word.starts_with("eyJ") && word.len() > 20 {
        return true; // JWT
    }
    if word.len() < 32 {
        return false;
    }
    let has_digit = word.chars().any(|c| c.is_ascii_digit());
    let has_alpha = word.chars().any(|c| c.is_ascii_alphabetic());
    // A path or a sentence fragment is not a token; an opaque mixed blob is.
    has_digit && has_alpha && !word.contains("..") && word.matches('/').count() < 3
}

/// Redact every string inside a JSON value, and blank the value of any
/// credential-named key outright.
pub fn redact_json(value: &mut serde_json::Value) {
    match value {
        serde_json::Value::String(text) => *text = redact(text),
        serde_json::Value::Array(items) => items.iter_mut().for_each(redact_json),
        serde_json::Value::Object(map) => {
            for (key, item) in map.iter_mut() {
                if is_secret_key(key) && !item.is_object() && !item.is_array() && !item.is_null() {
                    *item = serde_json::Value::String("[redacted]".into());
                } else {
                    redact_json(item);
                }
            }
        }
        _ => {}
    }
}

/// One line of provider progress, safe to echo to a terminal: credentials
/// redacted, control characters and escape sequences removed.
pub fn progress_line(raw: &str) -> Option<String> {
    text(&redact(raw), 2000)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_ansi_and_control_characters() {
        let dirty = "Medieval \u{1b}[31mCastle\u{1b}[0m\u{7}\tPack";
        assert_eq!(text(dirty, 100).as_deref(), Some("Medieval Castle Pack"));
    }

    #[test]
    fn strips_zero_width_and_bidi_overrides() {
        let dirty = "Cast\u{200b}le\u{202e}Pack";
        assert_eq!(text(dirty, 100).as_deref(), Some("CastlePack"));
    }

    #[test]
    fn collapses_whitespace_and_truncates_with_ellipsis() {
        let long = "a ".repeat(50);
        let out = text(&long, 10).unwrap();
        assert_eq!(out.chars().count(), 10);
        assert!(out.ends_with('…'));
    }

    #[test]
    fn empty_after_cleaning_is_none() {
        assert_eq!(text("   \u{1b}[0m  ", 50), None);
        assert_eq!(text("", 50), None);
    }

    #[test]
    fn newlines_do_not_survive_into_output() {
        let out = text("line one\nline two", 100).unwrap();
        assert!(!out.contains('\n'), "got {out:?}");
    }

    #[test]
    fn redacts_jwt_and_assignments() {
        let line = "auth failed token=abcDEF1234567890abcDEF1234567890 bearer eyJhbGciOiJIUzI1NiJ9.payload.sig";
        let out = redact(line);
        assert!(!out.contains("abcDEF1234567890"), "{out}");
        assert!(!out.contains("eyJhbGciOiJIUzI1NiJ9"), "{out}");
        assert!(out.contains("auth failed"));
    }

    #[test]
    fn redaction_leaves_ordinary_prose_and_paths_alone() {
        let line =
            "session expired. Run 'fabcli auth login' to refresh /home/u/.config/fabcli/token.json";
        let out = redact(line);
        assert!(out.contains("session expired"), "{out}");
        assert!(out.contains("fabcli auth login"), "{out}");
    }

    #[test]
    fn redaction_keeps_json_structure_intact() {
        let line = r#"{"error":{"kind":"auth_required","message":"refresh failed token=abcDEF1234567890abcDEF1234567890"}}"#;
        let out = redact(line);
        let parsed: serde_json::Value = serde_json::from_str(&out).expect("still valid JSON");
        assert_eq!(parsed["error"]["kind"], "auth_required");
        assert!(!out.contains("abcDEF1234567890"), "{out}");
    }

    #[test]
    fn redacts_short_secrets_behind_credential_keys() {
        let out = redact(
            r#"{"status":401,"refresh_token":"shortsecret123","jwt":"eyJhbGciOiJIUzI1NiJ9.e30.sig"}"#,
        );
        assert!(!out.contains("shortsecret123"), "{out}");
        assert!(!out.contains("eyJhbGci"), "{out}");
        assert!(out.contains("401"));
        assert!(
            redact("Authorization: Bearer abcdEF12345678")
                .matches("[redacted]")
                .count()
                >= 1
        );
        assert!(!redact("Authorization: Bearer abcdEF12345678").contains("abcdEF12345678"));
        assert!(!redact("session_id 9f8e7d6c5b4a3928").contains("9f8e7d6c5b4a3928"));
    }

    #[test]
    fn session_prose_is_not_redacted() {
        assert_eq!(
            redact("Fab session expired. Run 'fabcli auth login' to refresh."),
            "Fab session expired. Run 'fabcli auth login' to refresh."
        );
        assert_eq!(redact("no session — run login"), "no session — run login");
    }

    #[test]
    fn json_values_under_secret_keys_are_blanked() {
        let mut value =
            serde_json::json!({"access_token": "abc", "nested": {"cookie": 42, "note": "fine"}});
        redact_json(&mut value);
        assert_eq!(value["access_token"], "[redacted]");
        assert_eq!(value["nested"]["cookie"], "[redacted]");
        assert_eq!(value["nested"]["note"], "fine");
    }

    #[test]
    fn progress_lines_lose_escape_sequences() {
        let line =
            progress_line("\u{1b}]0;pwned\u{7}\u{1b}[2J\u{1b}[31mprogress 50%\u{1b}[0m").unwrap();
        assert_eq!(line, "progress 50%");
    }

    #[test]
    fn redacts_cookie_header_values() {
        let out = redact("Cookie: fab_sessionid=9f8e7d6c5b4a39281706");
        assert!(out.contains("[redacted]"), "{out}");
        assert!(!out.contains("9f8e7d6c5b4a39281706"), "{out}");
    }
}
