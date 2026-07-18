#!/bin/bash
# codex-companion prerequisite check. Prints PASS/FAIL lines; exit 0 if all pass.
fails=0

check() { # name, condition-exit-code, detail
  if [ "$2" -eq 0 ]; then
    echo "PASS: $1 $3"
  else
    echo "FAIL: $1 $3"
    fails=$((fails + 1))
  fi
}

# codex CLI present
if command -v codex >/dev/null 2>&1; then
  ver=$(codex --version 2>/dev/null | head -1)
  check "codex CLI" 0 "($ver)"
  # version >= 0.100 (exec resume + --output-schema era)
  vnum=$(echo "$ver" | grep -oE '[0-9]+\.[0-9]+' | head -1)
  major=${vnum%%.*}; minor=${vnum##*.}
  if [ "${major:-0}" -gt 0 ] || [ "${minor:-0}" -ge 100 ]; then
    check "codex version >= 0.100" 0 "($vnum)"
  else
    check "codex version >= 0.100" 1 "($vnum — run: codex update)"
  fi
  # exec resume subcommand exists
  codex exec resume --help >/dev/null 2>&1
  check "codex exec resume available" $? ""
  # authenticated
  if codex login status 2>&1 | grep -qi "logged in\|authenticated"; then
    check "codex authenticated" 0 ""
  else
    check "codex authenticated" 1 "(run: codex login)"
  fi
else
  check "codex CLI" 1 "(not found — npm install -g @openai/codex)"
fi

# uvx present (runs the bundled MCP server)
command -v uvx >/dev/null 2>&1
check "uvx (uv)" $? "$(command -v uvx 2>/dev/null)"

# swarm package resolvable at the pinned version (uvx pin syntax is pkg@ver;
# == is rejected as an invalid package name). stdin EOF makes the MCP server
# exit 0 right after startup; resolution failure exits nonzero. Watchdog loop
# because macOS lacks `timeout`; first run may download, hence 180 s.
if command -v uvx >/dev/null 2>&1; then
  uvx codex-mcp-swarm@1.7.0 </dev/null >/dev/null 2>&1 &
  swarm_pid=$!
  waited=0
  while kill -0 "$swarm_pid" 2>/dev/null && [ "$waited" -lt 180 ]; do
    sleep 1
    waited=$((waited + 1))
  done
  if kill -0 "$swarm_pid" 2>/dev/null; then
    kill "$swarm_pid" 2>/dev/null
    check "codex-mcp-swarm@1.7.0 resolvable" 1 "(no exit after ${waited}s — slow network? re-run once)"
  else
    wait "$swarm_pid"
    rc=$?
    if [ "$rc" -eq 0 ]; then
      check "codex-mcp-swarm@1.7.0 resolvable" 0 ""
    else
      check "codex-mcp-swarm@1.7.0 resolvable" 1 "(uvx exit $rc — could not fetch/run it)"
    fi
  fi
fi

# git (worktree isolation)
command -v git >/dev/null 2>&1
check "git" $? ""

echo
if [ "$fails" -eq 0 ]; then
  echo "All checks passed."
else
  echo "$fails check(s) failed."
fi
exit "$fails"
