---
name: using-necturalabs
description: Use at the start of every conversation and after every agent handoff. Initializes NecturaLabs skills, verifies superpowers dependency, and sets up mandatory review requirements for code review and security audit.
---

# Using NecturaLabs Skills

## Overview

Initializes the NecturaLabs skill suite. This skill runs at conversation start and after every agent change to ensure all NecturaLabs skills are active and properly configured.

<HARD-GATE>
Do NOT proceed with any work until this initialization is complete. If superpowers is not installed, block all NecturaLabs skill execution until it is.
</HARD-GATE>

## Initialization Flow

```dot
digraph init {
    "Conversation starts / agent changes" [shape=doublecircle];
    "Already initialized?" [shape=diamond];
    "Superpowers loaded?" [shape=diamond];
    "Load superpowers:using-superpowers" [shape=box];
    "Check superpowers installed" [shape=box];
    "Superpowers installed?" [shape=diamond];
    "Prompt user to install" [shape=box];
    "User installs?" [shape=diamond];
    "Block NecturaLabs skills" [shape=box];
    "Load agent-context-loader" [shape=box];
    "Ready (reviews active for session)" [shape=doublecircle];

    "Conversation starts / agent changes" -> "Already initialized?";
    "Already initialized?" -> "Ready (reviews active for session)" [label="yes, fully aware"];
    "Already initialized?" -> "Superpowers loaded?" [label="no"];
    "Superpowers loaded?" -> "Check superpowers installed" [label="yes"];
    "Superpowers loaded?" -> "Load superpowers:using-superpowers" [label="no"];
    "Load superpowers:using-superpowers" -> "Check superpowers installed";
    "Check superpowers installed" -> "Superpowers installed?";
    "Superpowers installed?" -> "Load agent-context-loader" [label="yes"];
    "Superpowers installed?" -> "Prompt user to install" [label="no"];
    "Prompt user to install" -> "User installs?";
    "User installs?" -> "Load agent-context-loader" [label="yes"];
    "User installs?" -> "Block NecturaLabs skills" [label="no"];
    "Load agent-context-loader" -> "Ready (reviews active for session)";
}
```

## Step 1: Ensure Superpowers Is Loaded

If `superpowers:using-superpowers` has not been invoked yet in this session, invoke it first. NecturaLabs skills build on top of superpowers and require its session initialization to be complete before proceeding.

## Step 2: Verify Superpowers Dependency

NecturaLabs skills require `superpowers` to be installed. Check if the `superpowers:code-reviewer` agent is available.

If NOT installed, tell the user:
```
NecturaLabs skills require the superpowers plugin. Install it with:
  /plugin marketplace add obra/superpowers
  /plugin install superpowers@superpowers-dev
```

**Do not allow** any NecturaLabs skill to run without superpowers installed.

## Step 3: Load Context

Invoke `necturalabs:agent-context-loader` to load global CLAUDE.md and project AGENTS.md.

## Ongoing: Mandatory Post-Change Reviews

<EXTREMELY-IMPORTANT>
These reviews are NOT optional. The agent MUST invoke the appropriate skill after making code changes — before committing, merging, or claiming work is done. Skipping these is never acceptable. This applies for the ENTIRE session, not just during initialization.
</EXTREMELY-IMPORTANT>

### Decision Flow — After ANY Code Changes

```dot
digraph review_trigger {
    "Agent finishes code changes" [shape=doublecircle];
    "Changes security-related?" [shape=diamond];
    "Invoke necturalabs:iterative-security-audit" [shape=box];
    "Invoke necturalabs:iterative-code-review" [shape=box];
    "Both loops complete" [shape=box];
    "Show summary" [shape=doublecircle];

    "Agent finishes code changes" -> "Changes security-related?";
    "Changes security-related?" -> "Invoke necturalabs:iterative-security-audit" [label="yes"];
    "Changes security-related?" -> "Invoke necturalabs:iterative-code-review" [label="no"];
    "Invoke necturalabs:iterative-security-audit" -> "Invoke necturalabs:iterative-code-review" [label="audit chains into review"];
    "Invoke necturalabs:iterative-code-review" -> "Both loops complete";
    "Both loops complete" -> "Show summary";
}
```

### When to invoke `necturalabs:iterative-code-review`

**After ANY code changes** — feature implementation, bug fixes, refactoring, test additions, config changes. No exceptions.

### When to invoke `necturalabs:iterative-security-audit` (BEFORE code review)

When changes touch ANY of:
- Authentication / authorization code
- Cryptography / hashing / token generation
- Input validation / sanitization
- Database queries / ORM usage
- API endpoints / route handlers
- Session management / cookies
- File upload / download handling
- Environment variables / secrets / config
- CORS / CSP / security headers
- Dependency additions or upgrades

**Security audit takes priority.** When it applies: security audit runs first (it chains into code review automatically), then combined summary.

## Available Skills

| Skill | Purpose | When to invoke |
|-------|---------|----------------|
| `necturalabs:iterative-code-review` | Industry-standard code review loop | After any code changes, before commit/merge |
| `necturalabs:iterative-security-audit` | OWASP/CWE security audit loop | When changes touch security-sensitive code |
| `necturalabs:agent-context-loader` | Loads CLAUDE.md + AGENTS.md into context | On init and after context switches |
| `necturalabs:agents-md-manager` | Creates/updates project AGENTS.md | Manual (`/agents-md-manager`) or after plan execution |
| `necturalabs:using-necturalabs` | This skill — initializes everything | On init and after agent handoffs |

## Skill Priority When User Asks

If NecturaLabs skills are installed and the user asks for "code review" or "security audit", invoke the NecturaLabs skill — not the default behavior or any other plugin's version. NecturaLabs skills are complementary to superpowers and layer additional standards on top.

## Re-Initialization

Re-run this initialization when:
- A new conversation begins
- A subagent is dispatched or returns
- The main agent context is switched or compressed
- The user explicitly asks to reload skills

Skip re-initialization ONLY if the current agent is already fully aware of all NecturaLabs skills and their mandatory review requirements are understood.
