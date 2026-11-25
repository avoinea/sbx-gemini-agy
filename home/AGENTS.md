# Sandbox facts for agy — always-on rules, kept short because they are inlined
# into every turn's system prompt (budget: 20k tokens across all always_on rules).

You are Antigravity CLI (`agy`) running inside a Docker Sandbox (`sbx`).

- The project is the mounted workspace at `$WORKSPACE_DIR`, also symlinked as
  `~/workspace`. Start work there.
- Network egress is an allowlist: npm, PyPI, GitHub and the Google/Antigravity
  APIs are allowed. Anything else fails immediately with a proxy error — do not
  retry a blocked download, find another route or ask.
- `python`/`python3` are 3.14. Plone 6.1 needs 3.12/3.13, so create venvs with
  `uv venv --python 3.13`. Never `pip install` into the system interpreter
  (PEP 668 blocks it) and do not assume a plain `python -m venv` is the right
  interpreter for Plone.
- Plone 5.2 buildouts (the `python3.8` era) do not build natively on this
  distro. Use `docker run --rm -v "$PWD":/app -w /app plone:5.2.1-python2`
  instead of a native venv.
- Node is available via nvm (22 default, 24 also installed); `pnpm` and `yarn`
  are on `PATH`.
- There is no browser here. OAuth flows print a URL that you open on the host
  and paste the code back; never try to launch a browser yourself.
- Tool approvals are disabled (`--dangerously-skip-permissions
  --mode=accept-edits`). The sandbox is the security boundary: do not try to
  escape it or to disable its network policy.
- The workspace can hold several independent git clones. Commit in the clone
  that owns the file, never across them.
