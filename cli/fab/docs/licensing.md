# Licensing

- **necturalabs-fab** is MIT-licensed (`LICENSE`).
- **FabCLI** is GPL-3.0-or-later (<https://github.com/zirklerite/FabCLI/blob/master/LICENSE>).

necturalabs-fab contains no FabCLI source, does not link FabCLI or its libraries, and communicates
with it only by executing the `fabcli` program and reading its JSON output. That is the
"separate programs" arrangement the GPL FAQ describes as aggregate use rather than a combined work
(<https://www.gnu.org/licenses/gpl-faq.html#MereAggregation>), so the GPL does not extend to
necturalabs-fab. See ADR 0002.

Keep it that way:

- Do not copy code, tests or fixtures from FabCLI or `egs-api-rs` into this repository. Test
  fixtures here are hand-written to FabCLI's documented output shapes.
- Do not bundle a `fabcli` binary in a necturalabs-fab release. If a package ever does, it must also
  convey FabCLI's source (or a written offer) and its licence text, as GPL section 6 requires.
- A future native provider may link `egs-api-rs` itself, which is MIT-licensed; FabCLI's
  maintenance fork of it (`zirklerite/egs-api-rs`) declares MIT as well. Re-check at the time.

This is an engineering summary, not legal advice.
