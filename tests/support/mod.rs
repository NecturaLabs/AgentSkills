//! Shared harness for the CLI integration tests.
//!
//! Every test runs the real `necturalabs-fab` binary against the `mock-fabcli`
//! test double in a throwaway HOME and working directory, so nothing touches
//! the developer's config, skills, library or Fab account.

#![allow(dead_code)]

use assert_cmd::cargo::cargo_bin;
use serde_json::Value;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

/// Environment variables that would otherwise leak a developer's settings in.
const LEAKY_VARS: &[&str] = &[
    "NECTURALABS_FAB_CONFIG",
    "NECTURALABS_FAB_PROVIDER",
    "NECTURALABS_FAB_FABCLI_PATH",
    "NECTURALABS_FAB_TIMEOUT_SECONDS",
    "NECTURALABS_FAB_DOWNLOAD_TIMEOUT_SECONDS",
    "NECTURALABS_FAB_VERSION_REQUIREMENT",
    "NECTURALABS_FAB_LIBRARY_CACHE",
    "NECTURALABS_FAB_DOWNLOAD_DIR",
    "NECTURALABS_FAB_OVERWRITE",
    "NECTURALABS_FAB_ENGINE",
    "NECTURALABS_FAB_ENGINE_VERSION",
    "NECTURALABS_FAB_PREFER_OWNED",
    "NECTURALABS_FAB_PREFER_FREE",
    "NECTURALABS_FAB_COUNT",
    "NECTURALABS_FAB_APPROVAL_CLAIM",
    "NECTURALABS_FAB_OUTPUT",
    "CODEX_HOME",
    "CLAUDE_CONFIG_DIR",
];

/// An isolated necturalabs-fab installation.
pub struct Harness {
    root: tempfile::TempDir,
    fixtures: PathBuf,
    extra_env: Vec<(String, String)>,
}

impl Harness {
    /// Build a harness using the named fixture set from `tests/fixtures`.
    pub fn new(fixture_set: &str) -> Self {
        let root = tempfile::tempdir().expect("tempdir");
        let fixtures = root.path().join("fixtures");
        std::fs::create_dir_all(&fixtures).unwrap();
        let source = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("tests")
            .join("fixtures")
            .join(fixture_set);
        for entry in std::fs::read_dir(&source).expect("fixture set exists") {
            let entry = entry.unwrap();
            std::fs::copy(entry.path(), fixtures.join(entry.file_name())).unwrap();
        }
        std::fs::create_dir_all(root.path().join("work")).unwrap();
        std::fs::create_dir_all(root.path().join("home")).unwrap();
        Self {
            root,
            fixtures,
            extra_env: Vec::new(),
        }
    }

    /// Working directory commands run in.
    pub fn work(&self) -> PathBuf {
        self.root.path().join("work")
    }

    /// Fake HOME.
    pub fn home(&self) -> PathBuf {
        self.root.path().join("home")
    }

    /// Fixture directory handed to the mock provider.
    pub fn fixtures(&self) -> &Path {
        &self.fixtures
    }

    /// Set an environment variable for subsequent runs.
    pub fn env(mut self, key: &str, value: &str) -> Self {
        self.extra_env.push((key.to_string(), value.to_string()));
        self
    }

    /// Write a project config into the working directory.
    pub fn with_project_config(self, body: &str) -> Self {
        std::fs::write(self.work().join(".necturalabs-fab.toml"), body).unwrap();
        self
    }

    /// Write a file relative to the working directory.
    pub fn write(&self, relative: &str, body: &str) -> PathBuf {
        let path = self.work().join(relative);
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).unwrap();
        }
        std::fs::write(&path, body).unwrap();
        path
    }

    /// Replace one fixture file.
    pub fn write_fixture(&self, name: &str, body: &str) {
        std::fs::write(self.fixtures.join(name), body).unwrap();
    }

    /// Run necturalabs-fab with `args`.
    pub fn run(&self, args: &[&str]) -> Output {
        let mut command = Command::new(cargo_bin("necturalabs-fab"));
        command
            .args(args)
            .current_dir(self.work())
            .env("HOME", self.home())
            .env("USERPROFILE", self.home())
            .env("XDG_CONFIG_HOME", self.home().join(".config"))
            .env("XDG_CACHE_HOME", self.home().join(".cache"))
            .env("NECTURALABS_FAB_FABCLI_PATH", cargo_bin("mock-fabcli"))
            .env("MOCK_FABCLI_DIR", &self.fixtures);
        for key in LEAKY_VARS {
            if *key != "NECTURALABS_FAB_FABCLI_PATH" {
                command.env_remove(key);
            }
        }
        for (key, value) in &self.extra_env {
            command.env(key, value);
        }
        command.output().expect("necturalabs-fab runs")
    }

    /// Run and parse the JSON envelope, asserting stdout holds exactly one
    /// JSON document and nothing else.
    pub fn json(&self, args: &[&str]) -> (Value, Output) {
        let mut full = vec!["--json"];
        full.extend_from_slice(args);
        let output = self.run(&full);
        let stdout = String::from_utf8_lossy(&output.stdout);
        assert_eq!(
            stdout.trim_end().lines().count(),
            1,
            "stdout must hold exactly one JSON line, got:\n{stdout}"
        );
        let value: Value = serde_json::from_str(stdout.trim()).unwrap_or_else(|err| {
            panic!(
                "stdout was not JSON ({err}):\n{stdout}\nstderr:\n{}",
                stderr(&output)
            )
        });
        (value, output)
    }

    /// Every provider invocation, as recorded by the mock.
    pub fn calls(&self) -> Vec<String> {
        std::fs::read_to_string(self.fixtures.join("calls.log"))
            .map(|text| text.lines().map(str::to_string).collect())
            .unwrap_or_default()
    }

    /// Whether the provider was asked to run `subcommand`.
    pub fn called(&self, subcommand: &str) -> bool {
        self.calls()
            .iter()
            .any(|line| line.split_whitespace().next() == Some(subcommand))
    }
}

/// Exit code of a finished command.
pub fn code(output: &Output) -> i32 {
    output.status.code().expect("process exited normally")
}

/// Captured stderr as text.
pub fn stderr(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).into_owned()
}

/// Captured stdout as text.
pub fn stdout(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).into_owned()
}
