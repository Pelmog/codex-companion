---
name: codex-companion
description: >
  Use OpenAI Codex as a headless debug companion via the bundled
  codex-mcp-swarm MCP server (tools codex, codex_async, codex_wait,
  codex_status, codex_reply, codex_cancel). Use when asking Codex for a
  second opinion on a bug, running a parallel independent diagnosis,
  delegating a fix to Codex, having Codex reproduce or verify a bug/fix, or
  continuing an earlier Codex investigation thread. Triggers on: "ask codex",
  "codex second opinion", "have codex diagnose", "codex fix this", "codex
  verify", "parallel investigation", "codex thread", "resume codex session".
---

# Codex debug companion (codex-mcp-swarm)

Headless Codex over MCP. Tasks run as parallel background `codex exec`
processes with live status, thread continuation, cancel, and per-task git
worktrees. The server is bundled with this plugin, pinned to
`codex-mcp-swarm==1.7.0`; its tools appear under this plugin's MCP prefix
(e.g. `mcp__plugin_codex-companion_codex__codex_async`) — search for
`codex_async` if unsure. Codex inherits its model and defaults from the
user's `~/.codex/config.toml`; the bundled server sets sandbox
`workspace-write` and effort `medium` as server-wide defaults.

Run `/codex-companion:doctor` first if anything fails — it checks the codex
CLI, auth, and uv prerequisites.

## CRITICAL: codex_reply loses execution context

`codex_reply` resumes the **conversation** (full history) but rebuilds the
command from **server defaults only** — the original call's `sandbox`, `cwd`,
`worktree`, `model`, and `config` are all dropped (verified in 1.7.0 source).
A read-only task resumes as workspace-write; a worktree fixer resumes in the
server's cwd, NOT its worktree.

- Use `codex_reply` only for conversational follow-ups (questions about
  findings, clarifications) where execution context doesn't matter.
- To *continue work* with correct context, run Codex directly via Bash:
  `codex exec resume <thread-uuid> --cd <dir> --sandbox <mode> "<prompt>"`
  — the CLI accepts full flags on resume; the MCP wrapper doesn't.

## The four modes

### 1. Second opinion / independent diagnosis (read-only)

```
codex_async {
  "prompt": "<symptom + where>. Independently investigate. Do NOT modify
             files. End with JSON:
             {\"bugs\": [{\"test\": ..., \"root_cause\": ..., \"minimal_fix\": ...}]}",
  "sandbox": "read-only",
  "cwd": "<abs path>"
}
```

- Structured output is prompt-enforced — swarm doesn't expose codex's
  `--output-schema`. State the exact JSON shape in the prompt; for a hard
  schema contract, use Bash `codex exec --output-schema <file>` instead.
- `read-only` constrains Codex's **shell commands** only — MCP tools from
  the user's `~/.codex/config.toml` roster load anyway and can have side
  effects. Keep the explicit "do NOT modify" instruction in the prompt.
- Launch typically returns a `Task ID` in ~1 s (longer with `worktree` on a
  big repo); keep working, then `codex_wait`.

### 2. Persistent investigator (threads)

- `codex_status`/`codex_wait` output includes `Thread ID:` (UUID) — **always
  capture it**; launch only gives the short Task ID, and the Thread ID can
  be temporarily absent until Codex actually starts (missing forever if
  startup failed — check stderr via status).
- Q&A follow-ups: `codex_reply {"threadId": ..., "prompt": ...}` (seconds,
  full context). Continued *work*: `codex exec resume` via Bash (see above).
- Threads persist in `$CODEX_HOME/sessions` across server restarts and
  days; archived/deleted sessions can't be resumed. Swarm task metadata
  (including the **full prompt and config**) sits in `/tmp/codex_swarm_tasks`
  (mode 0700, ~24 h TTL) — don't put secrets in prompts or config overrides.

### 3. Delegated fixer (worktree isolation)

Add `"worktree": true` + `sandbox: "workspace-write"`; ask Codex to commit in
the task prompt. Codex works on branch `codex-swarm/<task_id>` in a worktree
under the system temp dir — main working files stay untouched, but note the
worktree is created **from HEAD** (uncommitted main-tree changes are
invisible to it; commit or deliberately exclude them first).

On completion — promptly, because swarm's cleanup sweep **force-deletes the
worktree AND branch (`git branch -D`) after ~24 h** (`CODEX_SWARM_TASK_MAX_AGE`,
default 86400 s), even for cancelled/failed tasks:

1. Run the tests **in the worktree** yourself.
2. Merge `codex-swarm/<task_id>` back.
3. `git worktree remove <path>` then `git branch -d codex-swarm/<task_id>`
   (remove doesn't delete the branch; swarm's sweep skips it if the path is
   already gone).

### 4. Verify / reproduce (adversarial check)

Same as mode 1 but prompt Codex to *refute*: "try to prove this fix is
wrong / reproduce the bug on this branch". Runs genuinely in parallel with
your own verification. Tests that must write (tmp_path, coverage, snapshots)
can't run read-only — use a worktree + workspace-write for those.

## Steering a running task

No mid-turn injection (that needs Codex's experimental app-server). The loop:
`codex_status` → capture Thread ID → `codex_cancel {"task_id": ...}` →
resume with the redirect. Two caveats:

- Cancel is **best-effort**: it signals only the Codex parent PID, so child
  shell commands may briefly survive — verify processes have stopped
  (`pgrep -f <worktree-path>`) before testing or merging.
- For the redirect, prefer Bash `codex exec resume <thread> --cd ...
  --sandbox ...` over `codex_reply` (context loss, above).

Cancel preserves the worktree and partial output — subject to the 24 h sweep.

## Model & thinking level

Per call: `"model": "<slug>"` and/or `"config": {"model_reasoning_effort":
"<level>"}`. Parallel tasks can use different models/efforts (cheap repro +
frontier diagnosis). Supported efforts are **model-specific** — check
`codex debug models` for the installed catalog (e.g. current frontier models
support `low|medium|high|xhigh|max`, with no `minimal`). Invalid values may
be silently accepted — treat them as config errors, don't rely on rejection.
`--profile` in recent codex-cli layers `$CODEX_HOME/<name>.config.toml` over
the base config (NOT a `[profiles.<name>]` table).

## Quirks (verified against swarm 1.7.0 / codex-cli 0.144.5)

- Finished tasks say `COMPLETED in Ns` in the header but still `Phase:
  running` — trust the header.
- `codex_wait` timeout does NOT kill the task — re-wait or poll status.
- Read-only sandbox breaks pytest's cache writes — `-p no:cacheprovider`
  fixes *that*; write-requiring tests need a worktree instead.
- Every task spawn boots the user's full `~/.codex/config.toml` MCP roster
  (tens of seconds of launch overhead if that roster is large) — batch
  questions into one task where sensible.
- `codex_status` "Thinking" snippets are mid-line cuts — indicative, not
  quotable.
- The bundled server is pinned (`codex-mcp-swarm@1.7.0` — uvx pin syntax is
  `@`, not `==`); before upgrading, re-check the reply context-loss and
  cleanup-TTL behaviors and re-run a smoke test.
