---
name: using-necturalabs
description: Use at the start of every conversation and after every agent handoff. Initializes NecturaLabs skills, verifies superpowers dependency, and sets up automatic triggers for code review and security audit.
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
    "Check superpowers installed" [shape=box];
    "Superpowers installed?" [shape=diamond];
    "Prompt user to install" [shape=box];
    "User installs?" [shape=diamond];
    "Block NecturaLabs skills" [shape=box];
    "Register auto-triggers" [shape=box];
    "Load agent-context-loader" [shape=box];
    "Run agents-md-manager" [shape=box];
    "Ready" [shape=doublecircle];

    "Conversation starts / agent changes" -> "Already initialized?";
    "Already initialized?" -> "Ready" [label="yes, fully aware"];
    "Already initialized?" -> "Check superpowers installed" [label="no"];
    "Check superpowers installed" -> "Superpowers installed?";
    "Superpowers installed?" -> "Register auto-triggers" [label="yes"];
    "Superpowers installed?" -> "Prompt user to install" [label="no"];
    "Prompt user to install" -> "User installs?";
    "User installs?" -> "Register auto-triggers" [label="yes"];
    "User installs?" -> "Block NecturaLabs skills" [label="no"];
    "Register auto-triggers" -> "Load agent-context-loader";
    "Load agent-context-loader" -> "Run agents-md-manager";
    "Run agents-md-manager" -> "Ready";
}
```

## Step 1: Verify Superpowers Dependency

NecturaLabs skills require `superpowers` to be installed. Check if the `superpowers:code-reviewer` agent is available.

If NOT installed, tell the user:
```
NecturaLabs skills require the superpowers plugin. Install it with:
  /plugin marketplace add obra/superpowers
  /plugin install superpowers@superpowers-dev
```

**Do not allow** `necturalabs:iterative-code-review` or `necturalabs:iterative-security-audit` to run without superpowers installed. Other NecturaLabs skills may run independently.

## Step 2: Register Auto-Triggers

After initialization, these triggers are active for the entire session:

### Code Review — After ANY Changes
```dot
digraph review_trigger {
    "Agent makes code changes" [shape=doublecircle];
    "Changes security-related?" [shape=diamond];
    "Run security audit first" [shape=box];
    "Run code review" [shape=box];
    "Both loops complete" [shape=box];
    "Show summary" [shape=doublecircle];

    "Agent makes code changes" -> "Changes security-related?";
    "Changes security-related?" -> "Run security audit first" [label="yes"];
    "Changes security-related?" -> "Run code review" [label="no"];
    "Run security audit first" -> "Run code review";
    "Run code review" -> "Both loops complete";
    "Both loops complete" -> "Show summary";
}
```

**Code review runs automatically after every change the agent makes.** This is not optional. The agent must not skip this.

### Security Audit — When Changes Are Security-Related

Security audit auto-triggers when changes touch ANY of:
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

**Security audit takes priority over code review.** When both apply: security audit loop runs first, then code review loop runs on all changes (including audit remediations), then combined summary.

## Step 3: Load Context

Invoke `necturalabs:agent-context-loader` to load global CLAUDE.md and project AGENTS.md.

## Step 4: Run AGENTS.md Manager

Invoke `necturalabs:agents-md-manager` to create or update the project's AGENTS.md if needed.

## Available Skills

| Skill | Purpose | Auto-triggers |
|-------|---------|---------------|
| `necturalabs:iterative-code-review` | Industry-standard code review loop | After any agent changes |
| `necturalabs:iterative-security-audit` | OWASP/CWE security audit loop | When changes are security-related |
| `necturalabs:agent-context-loader` | Loads CLAUDE.md + AGENTS.md into context | On init and agent changes |
| `necturalabs:agents-md-manager` | Creates/updates project AGENTS.md | On init, when project changes |
| `necturalabs:using-necturalabs` | This skill — initializes everything | On init and agent changes |

## Skill Priority When User Asks

If NecturaLabs skills are installed and the user asks for "code review" or "security audit", invoke the NecturaLabs skill — not the default behavior or any other plugin's version. NecturaLabs skills are complementary to superpowers and layer additional standards on top.

## Re-Initialization

Re-run this initialization when:
- A new conversation begins
- A subagent is dispatched or returns
- The main agent context is switched or compressed
- The user explicitly asks to reload skills

Skip re-initialization ONLY if the current agent is already fully aware of all NecturaLabs skills and their auto-triggers are active.
