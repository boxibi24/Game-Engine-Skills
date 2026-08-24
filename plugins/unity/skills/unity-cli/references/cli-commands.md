# Unity CLI command surface

Binary: `%LOCALAPPDATA%\Unity\bin\unity.exe` (on PATH as `unity`). Version `1.0.0-beta.6`.

## Global flags

`--json` (shorthand for `--format json`; also `human`, `tsv`, `ndjson`, `github`) · `--no-banner` · `--no-pager` · `--non-interactive` (set this in CI) · `--quiet` · `--verbose` · `--proxy <url>`

All have env-var equivalents: `UNITY_FORMAT`, `UNITY_NO_BANNER`, `UNITY_NON_INTERACTIVE`, etc.

**Always pass `--no-banner`, and prefer `--json` when parsing.** The default `human` format prints a TSV-ish table that is awkward to parse and whose columns shift between versions.

## Live-Editor commands (need Pipeline running)

| Command | Purpose |
|---|---|
| `unity status` | Live state of every connected Editor: port, state, project, version, PID |
| `unity list` | List the tools the connected Editor exposes |
| `unity cmd <tool> [--flag value]` | Execute a Pipeline tool (alias of `unity command`) |
| `unity mcp` | Serve those same tools as an MCP stdio server |
| `unity mcp configure <client>` | Write MCP config for a known client; `--list` shows all 17 |
| `unity pipeline install\|upgrade\|list\|list-versions` | Manage the Pipeline package |

`unity mcp configure --list` covers Claude Desktop, Cursor, VS Code, Copilot CLI, Cline, Codex, Windsurf, Zed, Continue, Kiro and more. Of the 17 entries, four are `(no file — delegation/manual)` — `claude-code`, `trae`, `openclaw`, `inspect` — and the other 13 get written. **`claude-code` is one of the four**: it will not write Claude Code's config for you. Write `.mcp.json` by hand.

`unity skill install claude-code` is a *different* thing and new in beta.6: it writes the CLI's own bundled agent skill into `~/.claude/skills/unity-cli/`. That is the CLI vendor's skill, not this one, and it installs under the same `unity-cli` name — installing it will shadow or collide with this plugin's skill. `unity skill refresh` re-renders every tracked install.

## Editor-free commands (no Pipeline, no running Editor)

These spawn Unity in batch mode or talk to the Hub. They work in CI.

| Command | Notes |
|---|---|
| `unity build --target <t> --execute-method <M>` | **`--execute-method` is required** — Unity has no built-in CLI build. You must supply a static C# method. `-o/--output-path` is only a hint; your method has to honour it. |
| `unity test [project]` | `--mode EditMode\|PlayMode`, `--filter <pattern>`, `--output results.xml` (NUnit XML), `--timeout <s>`, `--allow-install`. **Exit 8 = tests failed; exit 6 = the run never produced a verdict** (compile error, expired licence, crashed editor). Under `--format json` the same split is `errors[0].code`: `TESTS_FAILED` vs `TEST_RUN_ERROR` / `TEST_TIMED_OUT`. Retry a 6, never an 8. Changed in beta.6 — older scripts treating 6 as "tests failed" are now wrong. |
| `unity run [project]` | Batch mode. `--command <name>` runs a registered Editor command **headlessly** — args after `--` are parsed against that command's schema. |
| `unity open [project]` | Opens in the correct Editor version; `--build-target`, `--args` |
| `unity shell` | Warm REPL for many commands in one process. `--protocol ndjson` gives a machine-readable stdio protocol — the right choice for scripted/agent batches. |
| `unity editors` / `install` / `install-modules` / `uninstall` | Editor and module management |
| `unity projects` | Hub project registry |
| `unity license` / `auth` | Licences; `auth login --client-id/--client-secret` for service accounts in CI |
| `unity doctor` / `diagnose` | Environment diagnostics, redacted and paste-safe |
| `unity cloud` | Unity Cloud orgs and projects |
| `unity templates` | Project templates |
| `unity bug` | File a bug to Unity's reporter (requires being signed in) |
| `unity job status\|wait\|cancel <job-id>` | Manage detached Editor command jobs (new in beta.6) |
| `unity collaboration` | Unity Collaboration resources — annotations, attachments, Jira, reactions (new in beta.6) |
| `unity skill install\|refresh` | Install the CLI's own bundled agent skill into an AI client (new in beta.6) — see the note above |

`unity run --command` is the one that matters for CI: it gets you Pipeline-style commands without a human-opened Editor.

## Self-update

```bash
unity upgrade --check          # check without installing
unity changelog                # release notes for the installed version
unity upgrade --changelog      # release notes for the *target* version
unity upgrade -y               # install
unity upgrade --channel beta   # stable | beta
unity upgrade --target <ver>   # pin a specific version
unity upgrade --rollback       # restore the previous binary
unity upgrade --dry-run        # preview
```

`--rollback` exists and works — reach for it rather than reinstalling by hand if an upgrade breaks you.

## Package management

```bash
unity pipeline list-versions   # available Pipeline versions
unity pipeline upgrade         # latest
unity pipeline install --package-version 0.5.0-exp.1   # pin
unity pipeline install --force # re-resolve
```

Pinning is worth doing. `0.5.0-exp.1` is experimental and Unity ships breaking changes in `-exp` packages without notice.
