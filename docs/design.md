# Codex Debug Companion — Design

> **Note (2026-07-18):** this design has since been packaged as the
> `codex-companion` Claude Code plugin (this repo). The server ships via the
> plugin's `.mcp.json` (tools surface as `mcp__plugin_codex-companion_codex__*`)
> and the skill is bundled in `skills/` — the user-scope `claude mcp add` and
> `~/.claude/skills/` placement described below reflect the original
> pre-plugin setup. uvx pin syntax is `codex-mcp-swarm@1.7.0` (`==` is not
> accepted by uvx).

**Date:** 2026-07-18
**Status:** Approved (trial validated; revised after Codex dogfood review — see
"Review findings" below)

## Problem

Claude Code needs Codex as a debug companion: second opinions, persistent
paired investigation, delegated fixes, and independent verification. The
existing mechanism (`claude-to-codex` driving the Codex TUI through herdr
panes) is heavy — a large skill, Monitor choreography, and multi-step verdict
loops — and gives weak mid-task observability and control. Human-visible
panes turned out to be unnecessary; headless is fine.

## Decision

Adopt **codex-mcp-swarm** (TKasperczyk/codex-mcp-swarm, PyPI
`codex-mcp-swarm`) as the Codex bridge, registered in Claude Code under the
server name **`codex`**, plus a compact usage skill **`codex-companion`** in
`~/.claude/skills/`.

Swarm wraps `codex exec` / `codex exec resume` subprocesses behind MCP tools:
`codex` (sync, drop-in for the official `codex mcp-server` tool),
`codex_async`, `codex_wait` (batch, resumable), `codex_status` (live view),
`codex_reply` (thread continuation), `codex_cancel`. It is NOT the
experimental app-server RPC daemon; graceful mid-turn steering is out of
scope by design — steering is cancel + reply on the surviving thread.

### Why swarm over the alternatives

- **exec+resume wrapper (build):** swarm already is that engine with an MCP
  facade; nothing left to build. The official `@openai/codex-sdk` remains the
  upgrade path if we ever outgrow it.
- **Official `codex mcp-server`:** the Claude-visible compatibility tools
  (`codex`/`codex-reply`) are sequential and blocking with no status/cancel.
  (The underlying experimental MCP interface has since grown thread/turn
  lifecycle and interrupt methods, but a generic MCP client like Claude Code
  only sees the compatibility tools — assessment as of codex-cli 0.144.5.)
- **app-server daemon:** experimental protocol, real engineering cost; buys
  graceful mid-turn injection plus typed events/approvals/lifecycle — not
  worth it yet for this use case.

### Trial evidence (2026-07-18)

Two planted bugs (adjacent-interval merge `<` vs `<=`, caller-list mutation).
Parallel read-only diagnoser (45 s) returned a correct prompt-enforced JSON
diagnosis; worktree fixer (70 s) fixed and committed on
`codex-swarm/<task_id>` with 4/4 tests passing, master untouched;
`codex_cancel` interrupted at 20 s; `codex_reply` follow-up answered in ~7 s
with full context. Timings at `model_reasoning_effort=low`.

## Architecture

1. **Registration** (user scope, tools surface as `mcp__codex__*`, which
   revalidates `/codex-plan-review`, `codex-review-integration`,
   `codex-reviewed-development`, and the CLAUDE.md "Codex MCP" docs with zero
   edits):

   ```bash
   claude mcp add --scope user codex -- uvx codex-mcp-swarm@1.7.0 \
     -c approval_policy=never -c sandbox_mode=workspace-write \
     -c model_reasoning_effort=medium --skip-git-repo-check
   ```

   Version is **pinned to the reviewed 1.7.0** (the package self-identifies
   as beta; `@latest` could silently change reply/cleanup semantics).
   Upgrades require re-checking the reply context-loss and worktree-TTL
   behaviors plus a smoke test. Defaults: model unset (inherits
   `gpt-5.6-sol` from `~/.codex/config.toml`); effort `medium`; sandbox
   `workspace-write`. Per-call overrides: `model`, `config`
   (e.g. `{"model_reasoning_effort": "high"}`), `sandbox`, `worktree`, `cwd`.

2. **Skill `codex-companion`** — usage patterns only, no scripts:
   - *Second opinion:* `codex_async` + `sandbox: "read-only"` + prompt-level
     JSON contract.
   - *Persistent investigator:* capture Task ID (launch) and Thread ID
     (status/wait); `codex_reply` for follow-ups.
   - *Delegated fixer:* `worktree: true`; verify tests in the worktree; merge
     `codex-swarm/<task_id>` back; clean up.
   - *Steer:* `codex_status` → thread ID → `codex_cancel` → `codex_reply`
     with the redirect.
   - *Quirks:* completed tasks still report `Phase: running` (trust the
     "COMPLETED in Ns" header); bogus effort values are silently accepted
     (use exactly minimal/low/medium/high); read-only sandbox breaks pytest
     cache (`-p no:cacheprovider`); every spawn boots the full config.toml
     MCP roster (~30–45 s launch overhead).

3. **Unchanged:** `claude-to-codex`/herdr (visible-pane niche);
   `/codex-review` (CLI diff review).

## Error handling & persistence

- Task launch typically returns in ~1 s (worktree creation is synchronous
  and can take longer on large repos); if `codex_wait` times out the task
  keeps running — re-wait or `codex_status`.
- Cancelled/failed tasks preserve worktrees and partial output for autopsy —
  but only until swarm's cleanup sweep (~24 h, `CODEX_SWARM_TASK_MAX_AGE`),
  which force-removes worktrees and deletes their branches. Cancel is also
  best-effort: it signals the Codex parent PID only, so descendant shell
  processes can briefly outlive it.
- Two persistence layers: swarm task artifacts (metadata incl. full prompt
  and config, stdout/stderr) in `/tmp/codex_swarm_tasks` (mode 0700, TTL as
  above — no secrets in prompts/config); Codex conversation rollouts in
  `$CODEX_HOME/sessions` (survive restarts; archived/deleted sessions can't
  be resumed).
- `codex_reply` resumes conversation history but rebuilds execution context
  from server defaults (per-call sandbox/cwd/worktree/model/config are
  dropped) — continued *work* must go through `codex exec resume` with
  explicit flags; the skill documents this prominently.

## Review findings (dogfood, 2026-07-18)

Per the testing plan, swarm itself reviewed this spec and the skill
(read-only, effort high, 14 findings). Both high-severity findings were
verified against the 1.7.0 source and codex-cli 0.144.5 and are incorporated
above and in the skill: (1) `codex_reply` context loss, (2) 24 h worktree/
branch force-cleanup. Mediums adopted: best-effort cancel, read-only ≠
MCP-side-effect guarantee, worktree-from-HEAD + branch cleanup, model-specific
effort levels (`gpt-5.6-sol`: low…ultra, no `minimal`), `--profile` =
`$CODEX_HOME/<name>.config.toml` overlay, pytest cache-vs-write distinction,
`--output-schema` unexposed by the wrapper, task-artifact retention, version
pinning. Full review output: `trial/review.log`.

## Testing

Restart a session; confirm `mcp__codex__*` tools; run one `codex_async`
read-only smoke task end-to-end; have swarm itself review this spec and the
skill (dogfood).
