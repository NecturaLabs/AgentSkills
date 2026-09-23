# Error codes

Every failure carries `error.code`, `error.message`, `error.recoverable`, `error.retryable`, and
often `error.hint` and `error.details`. The exit code is stable per code.

| Exit | Code | Meaning | Agent action |
|---|---|---|---|
| 1 | `FAB_INTERNAL` | Bug in necturalabs-fab. | Report with the message; do not retry. |
| 1 | `FAB_PROVIDER_FAILED` | Backend failed without a classification. | Retry once; then report. |
| 1 | `FAB_DOWNLOAD_FAILED` | A local write failed mid-download. | Check disk space and the directory; report. |
| 2 | `FAB_AUTH_REQUIRED` | Not signed in. | Ask the user to run `necturalabs-fab auth login --run`. |
| 2 | `FAB_AUTH_EXPIRED` | Session lapsed. | Same as above. |
| 3 | `FAB_NOT_FOUND` | Listing does not exist. | Re-check the id from a fresh search. |
| 3 | `FAB_LISTING_UNAVAILABLE` | Exists but cannot be served now. | Retry later; offer alternatives. |
| 4 | `FAB_RATE_LIMITED` | Marketplace throttling. | Wait ~30 s, retry once, stop parallel calls. |
| 5 | `FAB_NETWORK` | Transport failure. | Retry once; report connectivity. |
| 6 | `FAB_INVALID_INPUT` | Bad flag value, id or date. | Fix the command; `error.message` names the problem. |
| 6 | `FAB_CONFIG_INVALID` | Config file or env var is wrong. | Report the file and key from the message. |
| 7 | `FAB_PROVIDER_NOT_INSTALLED` | FabCLI missing. | Tell the user; see `necturalabs-fab doctor`. |
| 7 | `FAB_PROVIDER_UNSUPPORTED_VERSION` | FabCLI version outside the tested range. | Tell the user; `details.detected` and `details.supported` say which. |
| 7 | `FAB_PROVIDER_PROTOCOL` | Backend output changed shape. | Do not retry; run `doctor`; report. Upstream APIs may have moved. |
| 8 | `FAB_APPROVAL_REQUIRED` | Account mutation without approval, or policy `deny`. | Show `details.plan` to the user; re-run with `--approve` only if they agree. `details.policy: "deny"` cannot be overridden. |
| 9 | `FAB_ASSET_NOT_FREE` | Claim refused: paid or unknown price. | Stop; report price and URL. |
| 9 | `FAB_MONETARY_BLOCKED` | A monetary action was requested. | Stop. |
| 10 | `FAB_OUTPUT_CONFLICT` | Files or a previous download already there. | Choose another `--out`, or ask before `--overwrite force`. |
| 10 | `FAB_OUTPUT_NOT_EMPTY` | `require-empty` and the directory has content. | Choose an empty directory. |
| 10 | `FAB_PERMISSION_DENIED` | Filesystem refused the write. | Choose a writable directory. |
| 11 | `FAB_AMBIGUOUS_VARIANT` | Several engine versions/platforms. | Choose from `details.available`; retry with `--engine-version`/`--platform`. |
| 12 | `FAB_NOT_OWNED` | Download of something not in the library. | Claim if free (with approval); otherwise report. |
| 13 | `FAB_UNSUPPORTED_CAPABILITY` | Active provider lacks the operation. | Check `necturalabs-fab capabilities`; report. |
| 14 | `FAB_TIMEOUT` | Backend did not answer in time. | Retry once; a first library fetch can take minutes (`--timeout`). |
