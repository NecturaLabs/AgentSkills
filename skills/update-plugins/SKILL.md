---
name: update-plugins
description: Update all installed plugin marketplaces and their plugins concurrently. Use when the user asks to update plugins, check for updates, or refresh their plugin installations.
---

# Update Plugins

Update all installed plugin marketplaces concurrently, then reinstall plugins that have newer versions available.

## Procedure

### Step 1: Discover Installed Marketplaces

Run `claude plugin marketplace list` to get all registered marketplaces. Parse the output to extract marketplace names.

### Step 2: Update All Marketplaces Concurrently

Use the `superpowers:dispatching-parallel-agents` pattern — launch one subagent per marketplace, each running:

```
claude plugin marketplace update <marketplace-name>
```

All agents run in parallel. Collect results from each.

### Step 3: Reinstall Updated Plugins

After marketplace updates complete, run `claude plugin list` to see installed plugins. For each installed plugin, reinstall it to pick up any new version:

```
claude plugin install <plugin-name>@<marketplace-name>
```

Run these concurrently as well.

### Step 4: Report Results

Present a summary table:

| Marketplace | Status |
|-------------|--------|
| name | Updated / Already up to date / Failed: reason |

| Plugin | Status |
|--------|--------|
| name@marketplace | Updated to vX.Y.Z / Already current / Failed: reason |

## Error Handling

- If a marketplace update fails, report it but continue with the others
- If a plugin reinstall fails, report it but continue with the others
- Never abort the entire operation due to a single failure
