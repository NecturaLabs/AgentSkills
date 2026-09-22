//! necturalabs-fab: a stable, agent-oriented abstraction over Fab marketplace
//! access.
//!
//! Agents talk to this crate's CLI; the CLI talks to a [`provider`]. FabCLI is
//! the first provider and an implementation detail — nothing above
//! [`provider::FabProvider`] knows it exists.

#![warn(missing_docs)]

pub mod approval;
pub mod cli;
pub mod commands;
pub mod config;
pub mod error;
pub mod model;
pub mod output;
pub mod provider;
pub mod query;
pub mod rank;
pub mod sanitize;

/// necturalabs-fab's own version, as published in every response envelope.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");
