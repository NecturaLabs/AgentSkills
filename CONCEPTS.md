# Concepts: Skills, MCP, LSP, and RAG

A guide to the four key technologies that extend AI coding agents. Understanding when to use each — and when to combine them — is essential for getting the most out of Claude Code and similar tools.

## Skills

**What:** Modular instruction packages (Markdown files) that teach Claude how to approach specific tasks. Each skill is a folder with a `SKILL.md` containing structured guidance, workflows, and checklists that Claude follows when invoked.

**How it works:** Skill descriptions are loaded into context so Claude knows what's available. Full content loads only when triggered — either automatically (Claude detects relevance) or manually (`/skill-name`). Skills can include reference files, scripts, and templates.

**When to use:**
- Teaching Claude org-specific conventions and workflows
- Automating repetitive processes (code review, deployment, commit messages)
- Sharing best practices across a team
- Building reusable task templates

**When to use something else:**
- Need to connect Claude to external systems (APIs, databases) → use **MCP**
- Need code navigation and type info → use **LSP**
- Simple one-off instructions → just ask Claude directly

## MCP (Model Context Protocol)

**What:** An open standard protocol for secure, bidirectional connections between AI tools and external data sources, tools, and services. MCP servers expose three capabilities: Tools (executable actions), Resources (read-only data), and Prompts (pre-crafted workflows).

**How it works:** Claude Code acts as an MCP client connecting to MCP servers (separate processes). Communication uses JSON-RPC 2.0 over stdio or HTTP. Servers can run locally or remotely and are shared across teams — update the server, everyone gets the update.

**When to use:**
- Connecting Claude to external APIs, databases, or services
- Sharing versioned tool integrations across teams
- Building reliable integrations with formal specs and SDKs
- Strict capability namespacing (`github:*` tools separate from `slack:*` tools)

**When to use something else:**
- Simple local instructions → use **Skills** (no server needed)
- Code intelligence → use **LSP** (purpose-built for code)
- Document retrieval → consider **RAG**

## LSP (Language Server Protocol)

**What:** A standardized protocol that lets AI tools query code structure, definitions, references, and type information from language servers. Instead of text-based searching (grep), LSP provides precise, instant, semantic code intelligence.

**How it works:** Language servers (installed separately per language) deeply understand your code. Claude Code's LSP plugins query them for definitions, references, types, and symbols. Finding all call sites: ~50ms with LSP vs ~45 seconds with text search.

**When to use:**
- Navigating large codebases (definitions, references, call hierarchy)
- Understanding types and interfaces without reading entire files
- Refactoring with confidence (find all usages before changing)
- Any project with 10,000+ lines of code

**When to use something else:**
- Searching for text patterns, comments, or config values → use **Grep**
- Small projects where text search is fast enough
- Connecting to external services → use **MCP**

## RAG (Retrieval-Augmented Generation)

**What:** A technique where the AI retrieves relevant documents from a knowledge base before generating responses, grounding its output in actual data rather than training knowledge alone. For coding, this typically combines vector search with generation.

**How it works:** Documents (code, docs, specs) are chunked, embedded as vectors, and stored in a database. When Claude needs information, the system retrieves relevant chunks via similarity search and feeds them as context. Note: Claude Code's team increasingly favors *agentic search* (iterative exploration) over traditional RAG for coding tasks.

**When to use:**
- Incorporating large external docs, specs, or domain knowledge
- Cross-repo knowledge that LSP can't reach
- Reducing hallucination by grounding in actual documentation
- Search-heavy workflows where document retrieval is a bottleneck

**When to use something else:**
- Code navigation → use **LSP** (precise, no similarity matching needed)
- Small codebase or fits in prompt → just provide context directly
- Real-time data → use **MCP** (live API access)
- Simple lookups → use **Grep** or **LSP**

## When to Use What

| Scenario | Use |
|----------|-----|
| Teach Claude your team's workflow | **Skills** |
| Connect Claude to GitHub, Slack, or a database | **MCP** |
| Navigate a large codebase precisely | **LSP** |
| Search across external docs or specs | **RAG** |
| Enforce code review standards | **Skills** (with LSP for precision) |
| Build a shared tool for your org | **MCP** |
| Get type info without reading files | **LSP** |
| Ground responses in real documentation | **RAG** |

## Combining Approaches

These are complementary, not competing:

- **Skills + MCP**: Skills teach methodology, MCP provides tools. Example: a code review skill that uses MCP to post findings to GitHub.
- **Skills + LSP**: Skills guide reasoning, LSP provides code intelligence. Example: a security audit skill that uses LSP to trace data flow.
- **LSP + RAG**: LSP for code structure, RAG for external knowledge. Example: checking code against API documentation.
- **All four**: A comprehensive agent setup uses skills for process, MCP for connectivity, LSP for code intelligence, and RAG for knowledge grounding.

## Quick Start

1. **Start with Skills** — lowest barrier, highest immediate impact
2. **Add LSP** — essential for any non-trivial codebase
3. **Add MCP** — when you need external system integration
4. **Consider RAG** — for large knowledge bases or cross-repo reasoning
