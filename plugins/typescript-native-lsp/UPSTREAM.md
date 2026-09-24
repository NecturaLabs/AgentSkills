# typescript-native-lsp

Provenance: written by NecturaLabs, not vendored. It is a language-server configuration only
(`.lsp.json`) that starts TypeScript 7's native server, `tsc --lsp --stdio`, for TypeScript and
JavaScript files. License: MIT, as the rest of this repository.

The server binary comes from Microsoft's `typescript` package, version 7 or newer, installed per
user (for example `mise use -g npm:typescript@7`). Claude Code only: Codex has no language-server
plugins.
