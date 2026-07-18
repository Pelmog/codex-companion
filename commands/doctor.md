---
description: Check codex-companion prerequisites (codex CLI, auth, uv) and MCP server health
---

Run the prerequisite check script and interpret its results for the user:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh
```

For each FAIL line, explain the fix:

- **codex CLI missing** → install with `npm install -g @openai/codex` (or the
  ChatGPT desktop app, which bundles it), then `codex login`.
- **codex not authenticated** → run `codex login` (ChatGPT account) or
  `codex login --api-key <key>`. Suggest the user run it themselves in a
  terminal since it may open a browser.
- **codex too old** → `codex update` or `npm update -g @openai/codex`.
  This plugin is validated against codex-cli 0.144.x; `exec resume` and
  `--output-schema` need a reasonably recent CLI.
- **uv/uvx missing** → `curl -LsSf https://astral.sh/uv/install.sh | sh`
  (uvx runs the bundled codex-mcp-swarm server).
- **swarm server not reachable** → restart the Claude Code session so the
  plugin's MCP server starts, then check `/mcp` for `codex`.

If everything passes, confirm the setup is ready and point the user at the
`codex-companion` skill (it activates automatically on phrases like "ask
codex for a second opinion").
