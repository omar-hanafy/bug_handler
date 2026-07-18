# bug-handler agent plugin

Package-specific AI coding-assistant support for the
[`bug_handler`](https://pub.dev/packages/bug_handler) Flutter error-reporting
toolkit. One canonical plugin tree, installable in both **Claude Code** and
**OpenAI Codex** (each reads its own manifest; the skills are shared and follow
the [agentskills.io](https://agentskills.io) standard).

This is developer tooling for coding agents. It is **not** a runtime feature of
the Dart package and is **not** included in the pub.dev archive; it installs
from this Git repository.

## Install

Claude Code (v2.1.196+ recommended):

```
/plugin marketplace add omar-hanafy/bug_handler
/plugin install bug-handler@bug-handler
```

OpenAI Codex CLI (v0.131.0+; plugins also work in ChatGPT Work mode, not in the
IDE extension):

```
codex plugin marketplace add omar-hanafy/bug_handler
codex plugin add bug-handler@bug-handler
```

Start a **new session** after installing (required by Codex; recommended in
Claude Code, or run `/reload-plugins`).

## Skills

| Skill | Use it for |
|---|---|
| `setup-reporting` | First-time integration: bootstrap wiring, ClientConfig, providers, policy, reporters |
| `guard-workflow` | Everyday feature code: typed exceptions at repository boundaries, `guard(...)`, exceptions in state, `userMessage` in UI |
| `extend-pipeline` | Custom reporters (Sentry/Crashlytics/HTTP), custom context providers, transforms |
| `tune-privacy` | Sanitizer chains, allow/deny filter paths, masking heuristics, payload budgets |
| `diagnose-reporting` | Missing/duplicated/unexpected reports, outbox buildup, policy-gate elimination |
| `migrate-legacy-api` | Migrating 0.0.1-dev.x (`BugReporter`/`ErrorHandler`) projects to 1.0.0-dev.x |
| `audit-error-handling` | Reviewing an app's code against the package's error-handling contract |

Invocation: skills trigger automatically when the task matches. Explicitly:
Claude Code `/bug-handler:setup-reporting`; Codex `$setup-reporting` (or browse
with `/skills`).

Example prompts:

- "Wire bug_handler into this app; we already initialize Sentry in bootstrap."
- "Why do errors from staging never show up in our backend?"
- "Migrate this project off the old BugReporter API."

## Layout

```
plugins/bug-handler/
  .claude-plugin/plugin.json   Claude Code manifest
  .codex-plugin/plugin.json    Codex manifest
  skills/<name>/SKILL.md       7 shared skills (agentskills.io format)
  references/*.md              verified API/behavior references the skills load on demand
  fixtures/migration/          before/after example for the legacy migration
  evals/scenarios.md           behavioral test scenarios for the skills
```

Both manifests and the marketplace entries must carry the same version as
`pubspec.yaml`. `dart tool/validate_plugin.dart` (repo root) enforces this plus
manifest/frontmatter/path integrity - run it after any plugin edit.

## Compatibility

- Skills target bug_handler **>= 1.0.0-dev.5** (the `captureSafely` never-throw
  era) and know the differences back to 1.0.0-dev.1 and the legacy 0.0.1-dev.x
  line.
- No hooks, MCP servers, or executables are included: the plugin is
  instructions + reference markdown + illustrative fixtures only.

## Update / remove

Claude Code: `/plugin marketplace update bug-handler`, remove via `/plugin` UI or
`claude plugin uninstall bug-handler@bug-handler`.
Codex: `codex plugin marketplace upgrade bug-handler`, remove via
`codex plugin remove bug-handler@bug-handler`.

## For maintainers

When the package API changes, update the affected `references/*.md` and skills
in the same PR, bump the two `plugin.json` versions and both marketplace files
alongside `pubspec.yaml`, then run `dart tool/validate_plugin.dart` and the
scenarios in `evals/scenarios.md` that touch the changed behavior. Breaking
package releases MUST ship a new dedicated `migrate-<from>-to-<to>` skill
modeled on `migrate-legacy-api`.
