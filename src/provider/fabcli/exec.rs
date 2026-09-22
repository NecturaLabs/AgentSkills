//! Subprocess plumbing for the FabCLI provider.
//!
//! FabCLI is executed, never linked. That keeps its GPL-3.0 licence at arm's
//! length (see `docs/licensing.md`) and means a FabCLI crash cannot take
//! necturalabs-fab with it.
//!
//! Three invariants this module exists to hold:
//!
//! 1. Child stdout and stderr are drained concurrently, so a chatty progress
//!    stream can never deadlock a large JSON response.
//! 2. Every invocation has a deadline; a hung child is killed, not waited on.
//! 3. Nothing the child writes to stderr reaches our output without passing
//!    through [`crate::sanitize::redact`].

use crate::error::{ErrorCode, FabError, Result};
use crate::sanitize;
use std::io::{BufRead, BufReader, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{mpsc, Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};
use wait_timeout::ChildExt;

/// Hard cap on captured child output. A runaway provider must not exhaust
/// memory; 32 MiB is far above any real Fab JSON payload.
const CAPTURE_LIMIT: usize = 32 * 1024 * 1024;

/// Longest provider stderr fragment quoted back in an error message.
const STDERR_QUOTE_LIMIT: usize = 400;

/// How the child's stderr is handled.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StderrMode {
    /// Capture only. Used in machine mode so nothing pollutes the terminal.
    Capture,
    /// Capture and echo to our own stderr, line by line, as it arrives. Used
    /// for long operations where a human wants progress. Never touches stdout.
    Tee,
}

/// A configured FabCLI executable.
#[derive(Debug, Clone)]
pub struct Exec {
    /// Program to run; resolved through `PATH` when not absolute.
    pub program: PathBuf,
    /// Per-invocation deadline.
    pub timeout: Duration,
    /// Environment overrides applied on top of the inherited environment.
    pub env: Vec<(String, String)>,
    /// stderr handling.
    pub stderr: StderrMode,
    /// Give the child this process's stdin. Only interactive sign-in does.
    pub inherit_stdin: bool,
}

/// A finished invocation.
#[derive(Debug, Clone)]
pub struct Output {
    /// Exit status, `None` if the child was killed by a signal.
    pub status: Option<i32>,
    /// Captured stdout.
    pub stdout: String,
    /// Captured stderr, verbatim. It can carry credentials: never emit it
    /// without going through [`quote_stderr`] or `sanitize::redact`.
    pub stderr: String,
    /// Wall-clock duration.
    pub elapsed: Duration,
}

impl Output {
    /// Whether the child exited zero.
    pub fn success(&self) -> bool {
        self.status == Some(0)
    }
}

impl Exec {
    /// Build an executor with defaults suitable for read commands.
    pub fn new(program: impl Into<PathBuf>, timeout: Duration) -> Self {
        Self {
            program: program.into(),
            timeout,
            env: Vec::new(),
            stderr: StderrMode::Capture,
            inherit_stdin: false,
        }
    }

    /// Let the child read this process's stdin (interactive sign-in only).
    pub fn with_inherited_stdin(mut self) -> Self {
        self.inherit_stdin = true;
        self
    }

    /// Set an environment variable for the child.
    pub fn with_env(mut self, key: &str, value: &str) -> Self {
        self.env.push((key.to_string(), value.to_string()));
        self
    }

    /// Choose stderr handling.
    pub fn with_stderr(mut self, mode: StderrMode) -> Self {
        self.stderr = mode;
        self
    }

    /// Run the provider with `args` and return its captured output.
    ///
    /// Only transport-level problems are errors here: a non-zero exit is a
    /// normal [`Output`], because FabCLI uses exit codes to carry meaning that
    /// the caller must interpret.
    pub fn run(&self, args: &[String]) -> Result<Output> {
        let started = Instant::now();
        let mut command = Command::new(&self.program);
        command
            .args(args)
            .stdin(if self.inherit_stdin {
                Stdio::inherit()
            } else {
                Stdio::null()
            })
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        for (key, value) in &self.env {
            command.env(key, value);
        }

        let mut child = match command.spawn() {
            Ok(child) => child,
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => {
                return Err(FabError::new(
                    ErrorCode::ProviderNotInstalled,
                    format!("provider executable '{}' was not found", self.program.display()),
                )
                .with_hint(
                    "install FabCLI and put it on PATH, or set fabcli.path in the necturalabs-fab config",
                )
                .with_provider("fabcli"));
            }
            Err(err) if err.kind() == std::io::ErrorKind::PermissionDenied => {
                return Err(FabError::new(
                    ErrorCode::ProviderNotInstalled,
                    format!(
                        "provider executable '{}' is not executable",
                        self.program.display()
                    ),
                )
                .with_hint("check the file's permissions (chmod +x)")
                .with_provider("fabcli"));
            }
            Err(err) => {
                return Err(FabError::new(
                    ErrorCode::ProviderFailed,
                    format!("could not start '{}': {err}", self.program.display()),
                )
                .with_provider("fabcli"));
            }
        };

        let stdout_pipe = child.stdout.take().expect("stdout piped");
        let stderr_pipe = child.stderr.take().expect("stderr piped");
        let stdout_buf = Arc::new(Mutex::new(Vec::new()));
        let stdout_overflowed = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let stderr_buf = Arc::new(Mutex::new(Vec::new()));
        let (done_tx, done_rx) = mpsc::channel::<()>();

        {
            let buf = Arc::clone(&stdout_buf);
            let overflowed = Arc::clone(&stdout_overflowed);
            let done = done_tx.clone();
            thread::spawn(move || {
                if drain(stdout_pipe, &buf, CAPTURE_LIMIT) {
                    overflowed.store(true, std::sync::atomic::Ordering::SeqCst);
                }
                let _ = done.send(());
            });
        }
        {
            let buf = Arc::clone(&stderr_buf);
            let tee = self.stderr == StderrMode::Tee;
            let done = done_tx;
            thread::spawn(move || {
                drain_stderr(stderr_pipe, &buf, tee);
                let _ = done.send(());
            });
        }

        let status = match child.wait_timeout(self.timeout) {
            Ok(Some(status)) => status.code(),
            Ok(None) => {
                let _ = child.kill();
                let _ = child.wait();
                // A grandchild may still hold the pipes open; never wait on it.
                wait_for_drains(&done_rx, DRAIN_GRACE_AFTER_KILL);
                return Err(FabError::new(
                    ErrorCode::Timeout,
                    format!("provider did not finish within {}s", self.timeout.as_secs()),
                )
                .with_hint("raise fabcli.timeout-seconds, or warm the library cache first")
                .with_provider("fabcli"));
            }
            Err(err) => {
                let _ = child.kill();
                return Err(FabError::new(
                    ErrorCode::ProviderFailed,
                    format!("waiting for the provider failed: {err}"),
                )
                .with_provider("fabcli"));
            }
        };

        // The child has exited, so everything it wrote is already in the
        // pipes. EOF only arrives once every holder of the write end closes
        // it, and a background process the provider spawned may never do so:
        // wait a bounded time, then take what has been read.
        wait_for_drains(&done_rx, DRAIN_GRACE_AFTER_EXIT);

        // A truncated JSON document could still parse as a shorter, wrong one.
        if stdout_overflowed.load(std::sync::atomic::Ordering::SeqCst) {
            return Err(FabError::new(
                ErrorCode::ProviderProtocol,
                format!(
                    "provider output exceeded {} MiB and was not parsed",
                    CAPTURE_LIMIT / (1024 * 1024)
                ),
            )
            .with_hint("narrow the request (a smaller --count, one listing at a time)")
            .with_provider("fabcli"));
        }

        Ok(Output {
            status,
            stdout: take_text(&stdout_buf),
            stderr: take_text(&stderr_buf),
            elapsed: started.elapsed(),
        })
    }
}

/// How long to keep reading after the child exits, for output still in flight.
const DRAIN_GRACE_AFTER_EXIT: Duration = Duration::from_secs(2);

/// How long to keep reading after a timeout kill.
const DRAIN_GRACE_AFTER_KILL: Duration = Duration::from_millis(200);

fn wait_for_drains(done: &mpsc::Receiver<()>, grace: Duration) {
    let deadline = Instant::now() + grace;
    for _ in 0..2 {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if done.recv_timeout(remaining).is_err() {
            return;
        }
    }
}

fn take_text(buf: &Arc<Mutex<Vec<u8>>>) -> String {
    let bytes = buf.lock().map(|b| b.clone()).unwrap_or_default();
    String::from_utf8_lossy(&bytes).into_owned()
}

/// Read everything into `buf`, keeping at most `limit` bytes. Returns whether
/// anything past the limit was discarded. The reader is drained to EOF either
/// way, so the child never blocks on a full pipe.
fn drain<R: Read>(mut reader: R, buf: &Arc<Mutex<Vec<u8>>>, limit: usize) -> bool {
    let mut chunk = [0u8; 8192];
    let mut overflowed = false;
    loop {
        match reader.read(&mut chunk) {
            Ok(0) | Err(_) => break,
            Ok(n) => {
                if let Ok(mut guard) = buf.lock() {
                    let room = limit.saturating_sub(guard.len());
                    guard.extend_from_slice(&chunk[..n.min(room)]);
                    overflowed |= n > room;
                }
            }
        }
    }
    overflowed
}

fn drain_stderr<R: Read>(reader: R, buf: &Arc<Mutex<Vec<u8>>>, tee: bool) {
    let mut lines = BufReader::new(reader);
    let mut line = Vec::new();
    loop {
        line.clear();
        match lines.read_until(b'\n', &mut line) {
            Ok(0) | Err(_) => break,
            Ok(_) => {}
        }
        // A structured `{"error":...}` line is the provider's failure report,
        // which necturalabs-fab maps and renders itself; echoing it would print it
        // twice, once raw.
        let is_error_report = line.trim_ascii_start().starts_with(b"{\"error\"");
        if tee && !is_error_report {
            // Progress is echoed for a human, so it gets both defences: no
            // credentials, and no escape sequences that could drive the terminal.
            if let Some(clean) = sanitize::progress_line(&String::from_utf8_lossy(&line)) {
                let mut handle = std::io::stderr().lock();
                let _ = writeln!(handle, "{clean}");
                let _ = handle.flush();
            }
        }
        if let Ok(mut guard) = buf.lock() {
            if guard.len() < CAPTURE_LIMIT {
                guard.extend_from_slice(&line);
            }
        }
    }
}

/// Resolve a program name against `PATH`, returning the absolute path.
///
/// Used by `doctor` to report where the provider actually lives. Returns
/// `None` when the name cannot be resolved.
pub fn which(program: &Path) -> Option<PathBuf> {
    if program.components().count() > 1 || program.is_absolute() {
        return program.canonicalize().ok();
    }
    let path = std::env::var_os("PATH")?;
    let exts: Vec<String> = if cfg!(windows) {
        std::env::var("PATHEXT")
            .unwrap_or_else(|_| ".EXE;.CMD;.BAT;.COM".into())
            .split(';')
            .map(|e| e.to_ascii_lowercase())
            .collect()
    } else {
        vec![String::new()]
    };
    for dir in std::env::split_paths(&path) {
        for ext in &exts {
            let candidate = if ext.is_empty() {
                dir.join(program)
            } else {
                dir.join(format!("{}{ext}", program.display()))
            };
            if candidate.is_file() {
                return candidate.canonicalize().ok().or(Some(candidate));
            }
        }
    }
    None
}

/// Quote provider output for inclusion in an error: credentials redacted,
/// control characters removed, length capped.
pub fn quote_stderr(stderr: &str) -> String {
    sanitize::text(&sanitize::redact(stderr), STDERR_QUOTE_LIMIT)
        .unwrap_or_else(|| "<no output>".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    // These scripts are POSIX sh; the behaviours they exercise are
    // platform-independent and CI covers Windows through the CLI suites.
    #[cfg(unix)]
    fn shell(script: &str) -> (PathBuf, Vec<String>) {
        (PathBuf::from("sh"), vec!["-c".into(), script.into()])
    }

    #[test]
    fn capture_reports_output_past_the_limit_instead_of_silently_truncating() {
        let buf = Arc::new(Mutex::new(Vec::new()));
        let overflowed = drain(std::io::Cursor::new(vec![b'x'; 100]), &buf, 64);
        assert!(overflowed);
        assert!(buf.lock().unwrap().len() <= 64);

        let buf = Arc::new(Mutex::new(Vec::new()));
        assert!(!drain(std::io::Cursor::new(vec![b'x'; 64]), &buf, 64));
        assert_eq!(buf.lock().unwrap().len(), 64);
    }

    #[test]
    fn missing_executable_is_provider_not_installed() {
        let exec = Exec::new("definitely-not-a-real-binary-xyz", Duration::from_secs(5));
        let err = exec.run(&[]).unwrap_err();
        assert_eq!(err.code, ErrorCode::ProviderNotInstalled);
        assert_eq!(err.code.exit_code(), 7);
    }

    #[cfg(unix)]
    #[test]
    fn captures_stdout_and_exit_code() {
        let (program, mut args) = shell("echo hello; exit 3");
        let exec = Exec::new(program, Duration::from_secs(10));
        let out = exec.run(&std::mem::take(&mut args)).unwrap();
        assert_eq!(out.status, Some(3));
        assert!(out.stdout.trim() == "hello", "{:?}", out.stdout);
        assert!(!out.success());
    }

    #[cfg(unix)]
    #[test]
    fn a_hung_child_is_killed_at_the_deadline() {
        let (program, args) = shell("sleep 30");
        let exec = Exec::new(program, Duration::from_millis(300));
        let started = Instant::now();
        let err = exec.run(&args).unwrap_err();
        assert_eq!(err.code, ErrorCode::Timeout);
        assert!(
            started.elapsed() < Duration::from_secs(10),
            "kill did not happen promptly"
        );
    }

    #[cfg(unix)]
    #[test]
    fn large_stderr_does_not_deadlock_stdout() {
        // 200k of stderr with the JSON answer arriving last: a single-threaded
        // read of stdout-then-stderr would block forever here.
        let (program, args) = shell("for i in $(seq 1 4000); do echo 'progress line padding padding padding padding' >&2; done; echo '{\"ok\":true}'");
        let exec = Exec::new(program, Duration::from_secs(30));
        let out = exec.run(&args).unwrap();
        assert!(out.stdout.contains("\"ok\":true"));
        assert!(
            out.stderr.len() > 100_000,
            "stderr len {}",
            out.stderr.len()
        );
    }

    #[test]
    fn quoted_stderr_is_redacted() {
        let quoted = quote_stderr("auth failed token=abcDEF1234567890abcDEF1234567890");
        assert!(quoted.contains("[redacted]"), "{quoted}");
        assert!(!quoted.contains("abcDEF1234567890"), "{quoted}");
    }

    #[cfg(unix)]
    #[test]
    fn a_background_grandchild_cannot_hold_a_finished_call_open() {
        let (program, args) = shell("sleep 30 & echo '{\"ok\":true}'");
        let exec = Exec::new(program, Duration::from_secs(20));
        let started = Instant::now();
        let out = exec.run(&args).unwrap();
        assert!(out.stdout.contains("\"ok\":true"), "{:?}", out.stdout);
        assert!(
            started.elapsed() < Duration::from_secs(10),
            "blocked on the grandchild"
        );
    }

    #[cfg(unix)]
    #[test]
    fn a_grandchild_cannot_defeat_the_timeout() {
        let (program, args) = shell("sleep 30 & sleep 30");
        let exec = Exec::new(program, Duration::from_millis(300));
        let started = Instant::now();
        let err = exec.run(&args).unwrap_err();
        assert_eq!(err.code, ErrorCode::Timeout);
        assert!(
            started.elapsed() < Duration::from_secs(10),
            "timeout was defeated"
        );
    }

    #[cfg(unix)]
    #[test]
    fn env_overrides_reach_the_child() {
        let (program, args) = shell("echo $NECTURALABS_FAB_TEST_VALUE");
        let exec = Exec::new(program, Duration::from_secs(10))
            .with_env("NECTURALABS_FAB_TEST_VALUE", "present");
        let out = exec.run(&args).unwrap();
        assert_eq!(out.stdout.trim(), "present");
    }

    #[test]
    fn which_finds_a_program_on_path() {
        let probe = if cfg!(windows) { "cmd" } else { "sh" };
        assert!(which(Path::new(probe)).is_some());
        assert!(which(Path::new("definitely-not-a-real-binary-xyz")).is_none());
    }
}
