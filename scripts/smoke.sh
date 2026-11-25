#!/bin/sh
# Smoke test for the workload image. Runs inside the container:
#   docker run --rm -e AGY_CLI_DISABLE_AUTO_UPDATE=1 \
#     -v "$PWD/scripts:/scripts:ro" --entrypoint sh agy:smoke /scripts/smoke.sh
#
# It covers what a successful build hides: ~/.local/bin not on PATH for
# non-interactive shells, missing pnpm/yarn links, `agy acp` not starting
# without a TTY, python venv without ensurepip, and the Node warning that
# breaks T3 Code's Antigravity sign-in.
set -eux

agy --version
agy --help > /dev/null

# ACP handshake without a TTY and without credentials: the server must answer
# `initialize` before any login happens.
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{}}}' \
  | timeout 60 agy acp | grep -q "Antigravity ACP Server"

t3 --version
node --version
pnpm --version
yarn --version
uv --version
uvx --version
python --version
python -m venv /tmp/venv-check
/tmp/venv-check/bin/pip --version
git --version
rg --version | head -1
docker --version

# sbx injects NODE_USE_ENV_PROXY=1; Node answers with an EnvHttpProxyAgent
# warning on stderr, and T3's sign-in preflight requires stderr to be exactly
# one marker line. The image sets NODE_OPTIONS to suppress that warning.
test -n "${NODE_OPTIONS-}"
NODE_USE_ENV_PROXY=1 node -e 'console.error("x")' 2>/tmp/node.stderr >/dev/null
test "$(cat /tmp/node.stderr)" = x

test -f "$HOME/.gemini/AGENTS.md"
test -f "$HOME/.gemini/antigravity-cli/skills/grill-me/SKILL.md"
test -f "$HOME/.gemini/antigravity-cli/skills/handoff/SKILL.md"
test -f "$HOME/.gemini/antigravity-cli/skills/review/SKILL.md"

echo "smoke test passed"
