//! Provider-independent search vocabulary.
//!
//! Commands build a [`SearchQuery`]; providers translate it into whatever their
//! backend speaks. Validation happens here, once, so every provider receives a
//! query that is already known-good.

use crate::error::{FabError, Result};
use crate::model::Engine;
use serde::{Deserialize, Serialize};

/// Result ordering. Names are ours; providers map them onto their own.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum SortOrder {
    /// Marketplace relevance for the query text.
    Relevance,
    /// Most recently published first.
    Newest,
    /// Oldest published first.
    Oldest,
    /// Cheapest first.
    PriceAsc,
    /// Most expensive first.
    PriceDesc,
    /// Highest average rating first.
    RatingDesc,
    /// Largest discount first.
    DiscountDesc,
    /// Alphabetical.
    TitleAsc,
}

impl SortOrder {
    /// Parse a CLI value.
    pub fn parse(raw: &str) -> Result<Self> {
        Ok(match raw.trim().to_ascii_lowercase().as_str() {
            "relevance" => Self::Relevance,
            "newest" | "recent" => Self::Newest,
            "oldest" => Self::Oldest,
            "price-asc" | "cheapest" => Self::PriceAsc,
            "price-desc" => Self::PriceDesc,
            "rating" | "rating-desc" => Self::RatingDesc,
            "discount" | "discount-desc" => Self::DiscountDesc,
            "title" | "title-asc" => Self::TitleAsc,
            other => {
                return Err(FabError::invalid(format!(
                    "unknown sort '{other}' (expected one of: relevance, newest, oldest, price-asc, price-desc, rating, discount, title)"
                )))
            }
        })
    }
}

/// How "free" should be interpreted. Fab splits permanently-free listings from
/// paid listings that are temporarily 100% off, and conflating them silently
/// gives wrong answers, so the caller chooses.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum FreeMode {
    /// No free constraint.
    #[default]
    Any,
    /// Permanently free listings only.
    Permanent,
    /// Paid listings currently discounted to zero.
    LimitedTime,
    /// Either of the two above. Costs one extra provider call.
    Either,
}

impl FreeMode {
    /// Parse a CLI value.
    pub fn parse(raw: &str) -> Result<Self> {
        Ok(match raw.trim().to_ascii_lowercase().as_str() {
            "any" | "off" => Self::Any,
            "permanent" | "always" => Self::Permanent,
            "limited-time" | "promo" | "limited" => Self::LimitedTime,
            "either" | "both" => Self::Either,
            other => {
                return Err(FabError::invalid(format!(
                    "unknown free mode '{other}' (expected: permanent, limited-time, either, any)"
                )))
            }
        })
    }
}

/// Default number of results requested from the provider.
pub const DEFAULT_COUNT: u32 = 24;

/// Upper bound necturalabs-fab will request in one page.
pub const MAX_COUNT: u32 = 500;

/// A marketplace query in necturalabs-fab's own vocabulary.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchQuery {
    /// Free-text query.
    pub text: Option<String>,
    /// Engine the result must target.
    pub engine: Option<Engine>,
    /// Engine version the result must ship for. Filtered client-side: Fab has
    /// no server-side engine-version filter.
    pub engine_version: Option<String>,
    /// Required asset-format slugs (`fbx`, `blender`, `unreal-engine`, ...).
    pub formats: Vec<String>,
    /// Category slugs.
    pub categories: Vec<String>,
    /// Listing-type slugs (`3d-model`, `tool-and-plugin`, ...).
    pub listing_types: Vec<String>,
    /// Style slugs (`lowpoly`, `realistic`, ...). Marketplace ANDs these.
    pub styles: Vec<String>,
    /// Technical-feature slugs (`rigged`, `animated`, ...).
    pub technical_features: Vec<String>,
    /// License slugs (`cc-by`, ...).
    pub licenses: Vec<String>,
    /// Seller name.
    pub seller: Option<String>,
    /// Free-asset handling.
    pub free: FreeMode,
    /// Restrict to assets the account already owns.
    pub owned_only: bool,
    /// Decorate results with ownership state (needs an authenticated session).
    pub with_ownership: bool,
    /// Inclusive minimum price.
    pub min_price: Option<crate::model::Amount>,
    /// Inclusive maximum price.
    pub max_price: Option<crate::model::Amount>,
    /// Inclusive minimum average rating, 0-5.
    pub min_rating: Option<f64>,
    /// Only listings published on or after this `YYYY-MM-DD` date.
    pub published_since: Option<String>,
    /// Ordering.
    pub sort: Option<SortOrder>,
    /// Page size.
    pub count: u32,
    /// Opaque pagination cursor from a previous page.
    pub cursor: Option<String>,
    /// Raw provider filters. Escape hatch for marketplace features necturalabs-fab
    /// has not modelled; forwarded verbatim and never validated.
    pub raw_filters: Vec<(String, String)>,
}

impl SearchQuery {
    /// An empty query with the default page size.
    pub fn new() -> Self {
        Self {
            count: DEFAULT_COUNT,
            ..Default::default()
        }
    }

    /// Set the free-text query.
    pub fn with_text(mut self, text: impl Into<String>) -> Self {
        let text = text.into();
        if !text.trim().is_empty() {
            self.text = Some(text.trim().to_string());
        }
        self
    }

    /// Reject queries no provider could serve sensibly.
    pub fn validate(&self) -> Result<()> {
        if self.count == 0 || self.count > MAX_COUNT {
            return Err(FabError::invalid(format!(
                "count must be between 1 and {MAX_COUNT} (got {})",
                self.count
            )));
        }
        if let Some(rating) = self.min_rating {
            if !(0.0..=5.0).contains(&rating) {
                return Err(FabError::invalid(format!(
                    "min-rating must be between 0 and 5 (got {rating})"
                )));
            }
        }
        if let (Some(min), Some(max)) = (self.min_price, self.max_price) {
            if min > max {
                return Err(FabError::invalid(format!(
                    "min-price ({min}) is greater than max-price ({max})"
                )));
            }
        }
        if let Some(date) = &self.published_since {
            validate_iso_date(date)?;
        }
        if self.owned_only && self.cursor.is_some() {
            return Err(FabError::invalid(
                "--owned-only reads the account library and does not paginate with --cursor",
            ));
        }
        Ok(())
    }

    /// Lowercased significant tokens from the query text, used for deterministic
    /// relevance scoring. Stop words and one-character tokens are dropped.
    pub fn tokens(&self) -> Vec<String> {
        let Some(text) = &self.text else {
            return Vec::new();
        };
        text.split(|c: char| !c.is_alphanumeric())
            .map(|t| t.to_ascii_lowercase())
            .filter(|t| t.len() > 1 && !STOP_WORDS.contains(&t.as_str()))
            .collect()
    }
}

/// Words carrying no marketplace-retrieval signal.
const STOP_WORDS: &[&str] = &[
    "a",
    "an",
    "and",
    "any",
    "are",
    "as",
    "asset",
    "assets",
    "at",
    "be",
    "best",
    "by",
    "can",
    "find",
    "for",
    "from",
    "get",
    "good",
    "have",
    "i",
    "in",
    "into",
    "is",
    "it",
    "me",
    "my",
    "need",
    "of",
    "on",
    "or",
    "pack",
    "please",
    "project",
    "some",
    "something",
    "that",
    "the",
    "them",
    "there",
    "this",
    "to",
    "use",
    "want",
    "we",
    "with",
    "would",
];

/// `YYYY-MM-DD`, with real calendar bounds. No date library: this is the only
/// date necturalabs-fab parses, and a 20-line check beats a dependency.
pub fn validate_iso_date(raw: &str) -> Result<()> {
    let bad = || {
        FabError::invalid(format!(
            "expected a date as YYYY-MM-DD (got '{raw}'); relative windows are not supported"
        ))
    };
    let parts: Vec<&str> = raw.split('-').collect();
    if parts.len() != 3 || parts[0].len() != 4 || parts[1].len() != 2 || parts[2].len() != 2 {
        return Err(bad());
    }
    if !parts.iter().all(|p| p.chars().all(|c| c.is_ascii_digit())) {
        return Err(bad());
    }
    let year: u32 = parts[0].parse().map_err(|_| bad())?;
    let month: u32 = parts[1].parse().map_err(|_| bad())?;
    let day: u32 = parts[2].parse().map_err(|_| bad())?;
    if !(1970..=2100).contains(&year) || !(1..=12).contains(&month) || day == 0 {
        return Err(bad());
    }
    let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
    let max_day = match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        _ if leap => 29,
        _ => 28,
    };
    if day > max_day {
        return Err(bad());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_query_validates() {
        assert!(SearchQuery::new().validate().is_ok());
    }

    #[test]
    fn count_bounds_are_enforced() {
        let mut q = SearchQuery::new();
        q.count = 0;
        assert!(q.validate().is_err());
        q.count = MAX_COUNT + 1;
        assert!(q.validate().is_err());
        q.count = MAX_COUNT;
        assert!(q.validate().is_ok());
    }

    #[test]
    fn price_range_must_be_ordered() {
        let mut q = SearchQuery::new();
        q.min_price = crate::model::Amount::parse("30");
        q.max_price = crate::model::Amount::parse("10");
        let err = q.validate().unwrap_err();
        assert!(err.message.contains("greater than"), "{err}");
    }

    #[test]
    fn rating_bounds_enforced() {
        let mut q = SearchQuery::new();
        q.min_rating = Some(6.0);
        assert!(q.validate().is_err());
        q.min_rating = Some(4.5);
        assert!(q.validate().is_ok());
    }

    #[test]
    fn iso_dates_checked_against_the_calendar() {
        assert!(
            validate_iso_date("2026-02-29").is_err(),
            "2026 is not a leap year"
        );
        assert!(validate_iso_date("2024-02-29").is_ok());
        assert!(validate_iso_date("2026-13-01").is_err());
        assert!(validate_iso_date("2026-4-1").is_err());
        assert!(validate_iso_date("7d").is_err());
        assert!(validate_iso_date("2026-04-01").is_ok());
    }

    #[test]
    fn tokens_drop_stop_words_and_noise() {
        let q = SearchQuery::new().with_text("find me a dark gothic ruined castle for my project");
        assert_eq!(q.tokens(), vec!["dark", "gothic", "ruined", "castle"]);
    }

    #[test]
    fn owned_only_and_cursor_conflict() {
        let mut q = SearchQuery::new();
        q.owned_only = true;
        q.cursor = Some("abc".into());
        assert!(q.validate().is_err());
    }

    #[test]
    fn sort_parsing_is_closed() {
        assert_eq!(SortOrder::parse("newest").unwrap(), SortOrder::Newest);
        assert!(SortOrder::parse("-createdAt").is_err());
    }
}
