# codex-companion

**Use OpenAI Codex as a headless debug companion inside Claude Code.**

Claude does the driving; Codex provides parallel second opinions, persistent
investigation threads, isolated fix attempts, and adversarial verification —
all as background tasks Claude can launch, watch, steer, and collect.

```
You: "Ask codex for a second opinion on this flaky test."

Claude ──┬─▶ codex_async (read-only diagnosis)  ──┐
         ├─▶ codex_async (worktree fix attempt)  ──┤─▶ codex_wait ─▶ merged verdicts
         └─▶ keeps working on its own analysis  ──┘
```

## What's inside

- **Bundled MCP server** — [codex-mcp-swarm](https://github.com/TKasperczyk/codex-mcp-swarm)
  (pinned `1.7.0`), which wraps `codex exec` with true parallelism: `codex`,
  `codex_async`, `codex_wait`, `codex_status` (live view of what each task is
  doing), `codex_reply` (thread continuation), `codex_cancel`.
- **`codex-companion` skill** — battle-tested usage patterns for four modes
  (second opinion, persistent investigator, delegated fixer, adversarial
  verifier), plus **source-verified gotchas** most integrations miss:
  - `codex_reply` silently drops the original call's sandbox/cwd/worktree —
    the skill routes continued work through `codex exec resume` with explicit
    flags instead.
  - Swarm force-deletes task worktrees *and their branches* after ~24 h —
    the skill mandates prompt verify-merge-cleanup.
  - Cancellation signals only the parent PID; reasoning-effort values are
    model-specific and bad values fail silently; `read-only` doesn't
    constrain MCP-tool side effects; and more.
- **`/codex-companion:doctor`** — one command to check prerequisites
  (codex CLI, auth, uv, server resolvability).

The gotchas come from a real trial plus a dogfood review in which Codex
itself audited this integration against the swarm source and its own CLI —
see [docs/design.md](docs/design.md).

## Install

Prerequisites: [Codex CLI](https://developers.openai.com/codex/cli)
(`npm i -g @openai/codex` + `codex login`), [uv](https://docs.astral.sh/uv/),
git.

```
/plugin marketplace add pelmog/codex-companion
/plugin install codex-companion
```

Restart your session, then run `/codex-companion:doctor` to verify the setup.

## Use

Just ask — the skill activates on phrases like:

- *"Ask codex for a second opinion on this bug"*
- *"Have codex independently diagnose the failing tests while you check the config"*
- *"Delegate the fix to codex in a worktree, then verify it"*
- *"Ask codex to try to break this fix"*
- *"Continue that codex thread — ask it about the cache layer"*

Codex inherits its model and auth from your own `~/.codex/config.toml`.
Per-task overrides for model and reasoning effort are supported
(`config: {"model_reasoning_effort": "high"}`).

**Default posture**: the bundled server runs Codex with
`approval_policy=never` + `sandbox_mode=workspace-write` — tasks execute
without approval prompts, sandboxed to their working directory. The skill
routes diagnosis/verification through per-call `read-only` and risky fixes
through isolated git worktrees; tighten the defaults in `.mcp.json` if your
threat model wants it.

## Design notes

- This is deliberately the **exec-backed architecture** (`codex exec` +
  `resume` behind MCP), not Codex's experimental app-server daemon: robust,
  version-stable, zero daemon management. The trade-off is no graceful
  mid-turn steering — steering is cancel + resume, which the skill encodes.
- The server version is **pinned**. Upgrades should re-verify the reply
  context-loss and worktree-TTL behaviors (see the skill's quirks section).

## Credits

- [TKasperczyk/codex-mcp-swarm](https://github.com/TKasperczyk/codex-mcp-swarm) — the MCP bridge this plugin bundles.
- Built and reviewed with Claude Code + Codex (the dogfood review found two
  high-severity issues in our own first draft — details in the design doc).

## License

MIT
