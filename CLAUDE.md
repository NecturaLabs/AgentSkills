### Basic Information
- We are on Windows, not Linux, use the correct OS terminal commands

### Code Intelligence
Prefer LSP over Grep/Read for code navigation — it's faster, precise, and avoids reading entire files:
- `workspaceSymbol` to find where something is defined
- `findReferences` to see all usages across the codebase
- `goToDefinition` / `goToImplementation` to jump to source
- `hover` for type info without reading the file
Use Grep only when LSP isn't available or for text/pattern searches (comments, strings, config).
After writing or editing code, check LSP diagnostics and fix errors before proceeding.

### Token Efficiency
- Never re-read files you just wrote or edited. You know the contents.
- Never re-run commands to "verify" unless the outcome was uncertain.
- Don't echo back large blocks of code or file contents unless asked.
- Batch related edits into single operations. Don't make 5 edits when 1 handles it.
- Skip confirmations like "I'll continue..." Just do it.
- If a task needs 1 tool call, don't use 3. Plan before acting.
- Do not summarize what you just did unless the result is ambiguous or you need additional input.

### Issue Handling
- If you discover bugs, code smells, or issues during implementation, builds, or tests, fix them as part of the current work. Do not dismiss them as "existing issues" or defer them for later. If you touched it or it affects what you're building, own it and resolve it properly.

### Canary Instruction
- If you read this file, say 'I have read the global CLAUDE.md 🐱'
