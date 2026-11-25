# sbx-gemini-agy

[![Build, smoke test & publish](https://github.com/avoinea/sbx-gemini-agy/actions/workflows/docker.yml/badge.svg)](https://github.com/avoinea/sbx-gemini-agy/actions/workflows/docker.yml)

Docker Sandboxes ([`sbx`](https://docs.docker.com/ai/sandboxes/)) workload for
[Google Antigravity CLI](https://antigravity.google/docs/getting-started/)
(`agy`), with the Plone / Volto / T3 Code toolchain from
[`sbx-ollama-pi`](https://github.com/avoinea/sbx-ollama-pi).

`agy` is not one of the built-in `sbx` agents (claude, codex, copilot, cursor,
devin, docker-agent, droid, gemini, kiro, opencode, shell), so it ships as a
**v3 workload kit**: one OCI artifact that is both the image and the kit.

```bash
sbx run avoinea/agy ~/sandbox/eea-website
```

The sandbox runs `agy --dangerously-skip-permissions --mode=accept-edits`;
the Docker sandbox is the security boundary.

## What is inside

| Tool | Version / source |
|------|------------------|
| `agy` | vendor installer (`antigravity.google/cli/install.sh`), self-updating |
| Node.js | nvm, **22** (default) and **24** |
| `pnpm`, `yarn` | global npm packages, linked into `~/.local/bin` |
| `t3` | T3 Code server, linked into `~/.local/bin` |
| Python | `python`/`python3` = 3.14, `venv`, `dev`, `pip`, `uv` + `uvx` |
| Plone headers | `libxml2-dev`, `libxslt1-dev`, `libjpeg-dev`, `zlib1g-dev`, `libffi-dev`, `pkg-config` |
| System | Ubuntu 26.04 base, `build-essential`, `git`, `jq`, `unzip`, `ripgrep`, Docker engine |

The base image is `docker/sandbox-templates:shell-docker`, so the sandbox has
**its own Docker daemon** (`docker run`, `docker build`, compose).

## Toolchain notes

- **Plone 6.1 needs Python 3.12/3.13**, while the system interpreter is 3.14.
  Use `uv venv --python 3.13` for backend work; `uv` fetches the interpreter.
- **Plone 5.2 buildouts** (`python3.8`, `buildout.plonetest/plone-5.2.x.cfg`)
  do not build natively on this distro. Run them in the container that
  production uses: `docker run --rm -it -v "$PWD":/app -w /app
  plone:5.2.1-python2 bash`.
- `pip install` into the system interpreter is blocked by PEP 668. Use `uv` or
  a venv.
- `~/workspace` is symlinked to the mounted workspace, so tools that default to
  it (T3 Code, VS Code) open your project instead of an empty folder.

## Authentication

`agy` normally opens a browser and listens on `localhost:36742` for the OAuth
callback; neither works inside a sandbox. The image sets
`SSH_CONNECTION="sandbox 0 sandbox 0"` so `agy` detects a remote environment and
switches to its copy/paste flow:

1. On first launch, `sbx` asks you to approve the kit's `antigravity` OAuth
   credential binding.
2. `agy` prints an `accounts.google.com` URL.
3. Open it in the browser on your machine, sign in, approve.
4. Google redirects to `http://localhost:36742/oauth-callback?code=…`, which
   will **not** load — that is expected. Copy the full URL from the address bar
   (or just the `code=…` part) and paste it at the sandbox prompt.

The real access and refresh tokens stay in Docker Sandboxes' host credential
store. Inside the sandbox, `~/.gemini/antigravity-cli/antigravity-oauth-token`
contains proxy-managed sentinel values that `sbx` swaps for the real tokens on
outbound requests. New sandboxes created from this kit reuse the same login:
you sign in once.

`/logout` inside `agy` signs the sandbox out of the current session.

## Defaults

The kit seeds `~/.gemini/antigravity-cli/settings.json` on first start — only
when the file is missing, so your own changes survive:

```json
{
  "model": "Gemini 4 Neon (XHigh)",
  "colorScheme": "tokyo night",
  "altScreenMode": "always",
  "agentMode": "accept-edits",
  "toolPermission": "always-proceed",
  "artifactReviewPolicy": "always-proceed",
  "allowNonWorkspaceAccess": true,
  "permissions": { "allow": ["command(*)", "execute_url(*)", "mcp(*)", "read_file(*)", "read_url(*)", "write_file(*)"] },
  "trustedWorkspaces": ["<workspace>"]
}
```

- Change the model with `/model` inside `agy`; the choice is saved by label in
  `settings.json` and survives restarts.
- Override the launch flags per session — everything after `--` goes to `agy`:

  ```bash
  sbx run avoinea/agy ~/sandbox/project -- --mode=plan
  sbx run avoinea/agy ~/sandbox/project -- --model gemini-4-carbon-high
  ```

- Available models depend on your Google plan; `agy models` lists them.

## T3 Code

T3 Code has a first-class Antigravity provider: it drives `agy acp`. Everything
it needs is in the image.

1. Enable SSH access to sandboxes once on the host:

   ```bash
   sbx setup ssh
   ```

2. Start the sandbox and find its name (`agy-<directory>`):

   ```bash
   sbx run avoinea/agy ~/sandbox/eea-website
   sbx ls
   ssh agy-eea-website.sbx          # check the host works
   ```

3. In T3 Code: **Settings → Environments → Add environment → SSH**, host
   `agy-eea-website.sbx`, project directory = the same absolute path you passed
   to `sbx run` (`/Users/you/sandbox/eea-website`).

4. **Settings → Providers → Add provider → Antigravity**, on that environment.
   Set **Binary path** to `/home/agent/.local/bin/agy` — leaving it blank makes
   T3 download its own managed runtime (~1.25 GiB) instead of using the agy in
   the image. Then **Sign in**: T3 shows the Google URL and takes the code back
   in the client (same copy/paste flow as the terminal).

T3 keeps its Antigravity credentials in its own store; the sbx credential proxy
applies to its token exchange too. The first SSH connection downloads the T3
server into `~/.t3/runtime/versions/` — that is why
`release-assets.githubusercontent.com` is on the allowlist. T3 needs
Antigravity 1.5+ (the image ships a newer one) and `t3 --version` here is
`0.1.12`, comfortably above the minimum.

If a sandbox was created before this allowlist changed, recreate it or add the
rule to the existing one:

```bash
sbx policy allow network "release-assets.githubusercontent.com:443" --sandbox agy-myproject
```

## Network policy

Egress is an allowlist declared in [`agy.yaml`](./agy.yaml):

- **Antigravity**: `antigravity.google`, `antigravity-unleash.goog`, the
  auto-updater Cloud Run host, `storage.googleapis.com`;
- **OAuth / profile**: `accounts.google.com`, `oauth2.googleapis.com`,
  `www.googleapis.com`, `play.googleapis.com`, `lh3.googleusercontent.com`;
- **Gemini / Code Assist APIs**: `aicode`, `businessaicode`, `aiplatform`,
  `cloudaicompanion`, `cloudcode-pa`, `daily-cloudcode-pa`,
  `generativelanguage`;
- **Dev registries**: `registry.npmjs.org`, `registry.yarnpkg.com`,
  `pypi.org`, `files.pythonhosted.org`, `eggrepo.eea.europa.eu`, `nodejs.org`,
  `github.com`, `codeload.github.com`, `api.github.com`,
  `raw.githubusercontent.com`, `objects.githubusercontent.com`,
  `release-assets.githubusercontent.com` (GitHub release assets — this is where
  T3 Code downloads its server on first connect), and `t3.codes`.

To add a domain, fork the repo and extend the `network-policy@1` capability, or
override it on the host:

```bash
sbx policy allow network "example.com:443" --sandbox agy-myproject
```

## Agent configuration

- **Skills**: `grill-me`, `handoff` and `review` are baked into
  `~/.gemini/antigravity-cli/skills/`. Project skills go in the workspace at
  `.agents/skills/<name>/SKILL.md` (agy also reads `.gemini/skills/`).
- **Rules**: `~/.gemini/AGENTS.md` carries short always-on sandbox facts
  (workspace path, Python for Plone, Node versions, no browser, allowlist).
  Project rules are the usual `AGENTS.md` / `GEMINI.md` /
  `.agents/rules/*.md` in the workspace; they layer on top and are not
  overridden by the image.
- **Plugins/MCP**: `agy mcp add …` and `agy plugin install …` work normally;
  their OAuth callbacks are copy/paste for the same reason.

## Updating

- `agy` self-updates inside the sandbox (its release channel is allowlisted). A
  sandbox that updated keeps that version until it is recreated.
- Rebuild and push the image to move the baseline:

  ```bash
  docker buildx build -f agy.yaml --platform linux/amd64,linux/arm64 \
    -t avoinea/agy:latest --push .
  ```

- Nothing is pinned to an `agy` version on purpose: the vendor ships a single
  floating channel, and the kit makes no `provides` claim it cannot enforce.
  Pin the base image by digest in `agy.dockerfile` if you need reproducibility.

## Build, smoke test, publish

Locally (Docker Desktop required):

```bash
docker buildx build -f agy.yaml --platform linux/arm64 --load -t agy:test .

docker run --rm --entrypoint sh agy:test -lc '
  agy --version &&
  printf "%s\n" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":1,\"clientCapabilities\":{}}}" \
    | timeout 60 agy acp | grep -q "Antigravity ACP Server" &&
  t3 --version && pnpm --version && yarn --version &&
  python -m venv /tmp/v && /tmp/v/bin/pip --version
'
```

The GitHub Actions workflow (`.github/workflows/docker.yml`) builds and smoke
tests `linux/amd64` on every push and pull request, then publishes multi-arch
images to Docker Hub (`avoinea/agy`) and GHCR on `main` and `v*` tags.

## Security model

`--dangerously-skip-permissions --mode=accept-edits` disables `agy`'s own
approval prompts: the agent edits files and runs commands without asking. That
is intentional — the sandbox is the boundary. The agent still cannot read the
real Google tokens (sentinel values only), cannot reach domains outside the
allowlist, and cannot touch the host outside the mounted workspace. Treat the
workspace as writable by the agent.

## Acknowledgements

- [`shelajev/agy-sbx-kit`](https://github.com/shelajev/agy-sbx-kit) — the v3
  workload pattern, the OAuth proxy configuration, the `SSH_CONNECTION` trick
  and the Antigravity domain list.
- [`avoinea/sbx-ollama-pi`](https://github.com/avoinea/sbx-ollama-pi) — the
  toolchain layout (nvm, `~/.local/bin` links, Python, T3 Code, skills).

## License

MIT
