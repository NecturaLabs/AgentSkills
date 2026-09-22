//! Command-line surface.
//!
//! Flag names are part of the contract agents depend on. Adding one is a
//! minor change; renaming or removing one is breaking.

use clap::{Args, Parser, Subcommand};
use std::path::PathBuf;

/// necturalabs-fab's argument tree.
#[derive(Debug, Parser)]
#[command(
    name = "necturalabs-fab",
    version,
    about = "Agent-oriented access to the Fab marketplace: search, inspect, own, claim, download",
    long_about = "necturalabs-fab gives coding agents a stable, machine-readable interface to the Fab \
marketplace. Marketplace access runs through a replaceable provider; FabCLI is the current one.\n\n\
Machine callers should pass --json and branch on the envelope's `ok`, `error.code` and the process \
exit code.",
    disable_help_subcommand = true
)]
pub struct Cli {
    /// Emit the machine envelope (equivalent to --output json).
    #[arg(long, global = true, conflicts_with_all = ["human", "output"])]
    pub json: bool,

    /// Emit human-readable text (equivalent to --output human).
    #[arg(long, global = true, conflicts_with_all = ["json", "output"])]
    pub human: bool,

    /// Output mode: auto (default), json, human.
    #[arg(long, global = true, value_name = "MODE")]
    pub output: Option<String>,

    /// Suppress progress and warnings on stderr. Never affects JSON stdout.
    #[arg(long, short, global = true)]
    pub quiet: bool,

    /// Config file to use instead of the discovered user config.
    #[arg(long, global = true, value_name = "PATH")]
    pub config: Option<PathBuf>,

    /// Provider to use (default: fabcli).
    #[arg(long, global = true, value_name = "ID")]
    pub provider: Option<String>,

    /// Path to the provider executable.
    #[arg(long, global = true, value_name = "PATH")]
    pub fabcli_path: Option<PathBuf>,

    /// Per-call provider timeout in seconds.
    #[arg(long, global = true, value_name = "SECONDS")]
    pub timeout: Option<u64>,

    /// Include the untouched provider payload on each asset. Debugging aid;
    /// large and not part of the stable contract.
    #[arg(long, global = true)]
    pub raw: bool,

    /// The command to run.
    #[command(subcommand)]
    pub command: Command,
}

/// Top-level commands.
#[derive(Debug, Subcommand)]
pub enum Command {
    /// Search the marketplace. Deterministic retrieval, provider order.
    Search(SearchArgs),

    /// Rank candidates for a described need. Search plus deterministic scoring.
    Find(FindArgs),

    /// Recommend the single best candidate, with the reasoning behind it.
    Recommend(FindArgs),

    /// Show everything known about one listing.
    Inspect(InspectArgs),

    /// Report ownership and licence state for listings.
    Ownership(OwnershipArgs),

    /// List — and optionally filter — assets already in the account library.
    Library(LibraryArgs),

    /// Download an owned asset's files.
    Download(DownloadArgs),

    /// Add a free asset to the account library. Account mutation.
    Claim(ClaimArgs),

    /// Fab's limited-time free listings; `promos claim` claims them.
    Promos(PromosArgs),

    /// Session status and sign-in instructions.
    Auth(AuthArgs),

    /// Check the installation, provider, session and skill wiring.
    Doctor,

    /// Report what the active provider supports.
    Capabilities,

    /// Inspect configuration and where each layer came from.
    Config(ConfigArgs),

    /// Check that the agent skill is installed for Claude Code and Codex.
    Skill(SkillArgs),
}

/// Marketplace filters shared by `search`, `find` and `recommend`.
#[derive(Debug, Args, Clone, Default)]
pub struct FilterArgs {
    /// Target engine: unreal, unity, godot, blender, uefn, metahuman.
    #[arg(long, value_name = "ENGINE")]
    pub engine: Option<String>,

    /// Target engine version, e.g. 5.4. Checked against listing detail.
    #[arg(long, value_name = "VERSION")]
    pub engine_version: Option<String>,

    /// Require an asset format, e.g. fbx, blender, unreal-engine. Repeatable.
    #[arg(long = "format", value_name = "SLUG")]
    pub formats: Vec<String>,

    /// Restrict to a marketplace category slug. Repeatable.
    #[arg(long = "category", value_name = "SLUG")]
    pub categories: Vec<String>,

    /// Restrict to a listing type, e.g. 3d-model, tool-and-plugin. Repeatable.
    #[arg(long = "listing-type", value_name = "SLUG")]
    pub listing_types: Vec<String>,

    /// Restrict to a style, e.g. lowpoly, realistic. Repeatable; ANDed by Fab.
    #[arg(long = "style", value_name = "SLUG")]
    pub styles: Vec<String>,

    /// Require a technical feature, e.g. rigged, animated. Repeatable.
    #[arg(long = "feature", value_name = "SLUG")]
    pub features: Vec<String>,

    /// Restrict to a licence slug, e.g. cc-by. Repeatable.
    #[arg(long = "license", value_name = "SLUG")]
    pub licenses: Vec<String>,

    /// Restrict to one seller.
    #[arg(long, value_name = "NAME")]
    pub seller: Option<String>,

    /// Free handling: permanent, limited-time, either, any.
    #[arg(long, value_name = "MODE")]
    pub free: Option<String>,

    /// Shorthand for --free permanent.
    #[arg(long, conflicts_with = "free")]
    pub free_only: bool,

    /// Only assets already in the library. Reads the library, not the search index.
    #[arg(long)]
    pub owned_only: bool,

    /// Annotate results with ownership state. Needs an authenticated session.
    #[arg(long)]
    pub with_ownership: bool,

    /// Maximum price, in the account's currency.
    #[arg(long, value_name = "AMOUNT")]
    pub max_price: Option<crate::model::Amount>,

    /// Minimum price.
    #[arg(long, value_name = "AMOUNT")]
    pub min_price: Option<crate::model::Amount>,

    /// Minimum average rating, 0-5.
    #[arg(long, value_name = "RATING")]
    pub min_rating: Option<f64>,

    /// Only listings published on or after this date (YYYY-MM-DD).
    #[arg(long, value_name = "DATE")]
    pub published_since: Option<String>,

    /// Ordering: relevance, newest, oldest, price-asc, price-desc, rating, discount, title.
    #[arg(long, value_name = "ORDER")]
    pub sort: Option<String>,

    /// Results to request from the marketplace.
    #[arg(long, value_name = "N")]
    pub count: Option<u32>,

    /// Raw provider filter, KEY=VALUE. Escape hatch; forwarded unvalidated.
    #[arg(long = "filter", value_name = "KEY=VALUE")]
    pub raw_filters: Vec<String>,
}

/// `search` arguments.
#[derive(Debug, Args)]
pub struct SearchArgs {
    /// Free-text query.
    pub query: Option<String>,

    /// Pagination cursor from a previous page.
    #[arg(long, value_name = "CURSOR")]
    pub cursor: Option<String>,

    /// Fetch listing detail for the first N results (engines, formats, specs).
    #[arg(long, value_name = "N", default_value_t = 0)]
    pub hydrate: u32,

    /// Shared filters.
    #[command(flatten)]
    pub filters: FilterArgs,
}

/// `find` and `recommend` arguments.
#[derive(Debug, Args)]
pub struct FindArgs {
    /// What you need, in plain words.
    pub intent: String,

    /// How many ranked candidates to return.
    #[arg(long, value_name = "N")]
    pub top: Option<u32>,

    /// How many top candidates to enrich with listing detail.
    #[arg(long, value_name = "N")]
    pub hydrate: Option<u32>,

    /// Drop candidates that positively do not support the target engine.
    #[arg(long)]
    pub require_engine: bool,

    /// Rank owned assets first (default from config).
    #[arg(long, overrides_with = "no_prefer_owned")]
    pub prefer_owned: bool,

    /// Do not prefer owned assets.
    #[arg(long, overrides_with = "prefer_owned")]
    pub no_prefer_owned: bool,

    /// Rank free assets first (default from config).
    #[arg(long, overrides_with = "no_prefer_free")]
    pub prefer_free: bool,

    /// Do not prefer free assets.
    #[arg(long, overrides_with = "prefer_free")]
    pub no_prefer_free: bool,

    /// Shared filters.
    #[command(flatten)]
    pub filters: FilterArgs,
}

/// `inspect` arguments.
#[derive(Debug, Args)]
pub struct InspectArgs {
    /// Listing id.
    pub listing: String,

    /// Skip the formats call (faster, no engine or technical data).
    #[arg(long)]
    pub no_formats: bool,

    /// Also fetch ownership state. Needs an authenticated session.
    #[arg(long)]
    pub ownership: bool,

    /// Do not truncate the description.
    #[arg(long)]
    pub full_description: bool,
}

/// `ownership` arguments.
#[derive(Debug, Args)]
pub struct OwnershipArgs {
    /// One or more listing ids.
    #[arg(required = true)]
    pub listings: Vec<String>,
}

/// `library` arguments.
#[derive(Debug, Args)]
pub struct LibraryArgs {
    /// Match library entries containing these words (title, description, category).
    pub query: Option<String>,

    /// Only entries that ship for this engine.
    #[arg(long, value_name = "ENGINE")]
    pub engine: Option<String>,

    /// Only entries that ship for this engine version.
    #[arg(long, value_name = "VERSION")]
    pub engine_version: Option<String>,

    /// Entries per page (default 100, at most 500).
    #[arg(long, value_name = "N")]
    pub limit: Option<u32>,

    /// Page to show, starting at 1.
    #[arg(long, value_name = "N", default_value_t = 1)]
    pub page: u32,

    /// Fetch each entry's real description from its listing (up to 100).
    /// Automatic when 10 or fewer entries match.
    #[arg(long, conflicts_with = "no_details")]
    pub details: bool,

    /// Never fetch listing descriptions.
    #[arg(long)]
    pub no_details: bool,
}

/// `download` arguments.
#[derive(Debug, Args)]
pub struct DownloadArgs {
    /// Listing id.
    pub listing: String,

    /// Destination directory. Defaults to the configured download directory.
    #[arg(long, short = 'o', value_name = "DIR")]
    pub out: Option<PathBuf>,

    /// Engine version to fetch when the listing ships several, e.g. 5.4.
    #[arg(long, value_name = "VERSION")]
    pub engine_version: Option<String>,

    /// Platform to fetch when the listing ships several, e.g. Windows.
    #[arg(long, value_name = "PLATFORM")]
    pub platform: Option<String>,

    /// Collision policy: refuse (default), force, require-empty.
    #[arg(long, value_name = "POLICY")]
    pub overwrite: Option<String>,

    /// Parallel chunk workers.
    #[arg(long, value_name = "N")]
    pub jobs: Option<u32>,

    /// Report what would happen and write nothing.
    #[arg(long)]
    pub dry_run: bool,

    /// Do not write the necturalabs-fab sidecar next to the files.
    #[arg(long)]
    pub no_sidecar: bool,
}

/// `claim` arguments.
#[derive(Debug, Args)]
pub struct ClaimArgs {
    /// Listing id.
    pub listing: String,

    /// Confirm the account mutation. Ask the person you work for first.
    #[arg(long)]
    pub approve: bool,

    /// Show the plan and change nothing.
    #[arg(long, conflicts_with = "approve")]
    pub dry_run: bool,
}

/// `promos` arguments.
#[derive(Debug, Args)]
pub struct PromosArgs {
    /// Omit to list the current limited-time free listings.
    #[command(subcommand)]
    pub command: Option<PromosCommand>,
}

/// `promos` subcommands.
#[derive(Debug, Subcommand)]
pub enum PromosCommand {
    /// Claim the current limited-time free listings you do not own yet.
    Claim {
        /// Claim only these listing ids, and only while they are still promos.
        /// Pass the ids from a dry run to approve exactly what was shown.
        listings: Vec<String>,
        /// Confirm the account mutation. Ask the person you work for first.
        #[arg(long)]
        approve: bool,
        /// Show what would be claimed and change nothing.
        #[arg(long, conflicts_with = "approve")]
        dry_run: bool,
    },
}

/// `auth` arguments.
#[derive(Debug, Args)]
pub struct AuthArgs {
    /// Auth subcommand.
    #[command(subcommand)]
    pub command: AuthCommand,
}

/// `auth` subcommands.
#[derive(Debug, Subcommand)]
pub enum AuthCommand {
    /// Report session state for reads and for account actions.
    Status,
    /// Sign in. Without --run, prints what to do; with --run, starts it.
    Login {
        /// Start the interactive sign-in (needs a terminal). Opens your browser.
        #[arg(long)]
        run: bool,
        /// Sign in for account actions (claim, ownership) instead. Opens a
        /// sign-in window; only needed when one of those is used.
        #[arg(long)]
        account: bool,
    },
}

/// `config` arguments.
#[derive(Debug, Args)]
pub struct ConfigArgs {
    /// Config subcommand.
    #[command(subcommand)]
    pub command: ConfigCommand,
}

/// `config` subcommands.
#[derive(Debug, Subcommand)]
pub enum ConfigCommand {
    /// Print the effective configuration and its layers.
    Show,
    /// Print the config file paths necturalabs-fab reads.
    Path,
    /// Write a commented starter config.
    Init {
        /// Write a project config in the working directory instead of the user config.
        #[arg(long)]
        project: bool,
        /// Overwrite an existing file.
        #[arg(long)]
        force: bool,
    },
}

/// `skill` arguments.
#[derive(Debug, Args)]
pub struct SkillArgs {
    /// Skill subcommand.
    #[command(subcommand)]
    pub command: SkillCommand,
}

/// `skill` subcommands.
#[derive(Debug, Subcommand)]
pub enum SkillCommand {
    /// Report whether the plugin is installed for Claude Code and Codex.
    Status,
}
