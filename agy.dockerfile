# syntax=docker/dockerfile:1
# Workload image for Google's Antigravity CLI (agy) plus the Plone/Volto dev
# toolchain. Built as an OCI artifact by `docker buildx -f agy.yaml`.
#
# The base image is pinned by tag on purpose: Docker ships security updates to
# sandbox-templates regularly, and agy already floats (vendor installer +
# self-update). Pin the digest if you need bit-for-bit reproducibility:
#   docker image inspect docker/sandbox-templates:shell-docker \
#     --format '{{index .RepoDigests 0}}'
FROM docker/sandbox-templates:shell-docker

USER root

# System packages. build-essential is already in the base image; what we add is
# the Python/Plone headers (lxml, Pillow, cryptography fall back to source
# builds often enough to matter) and the small CLI conveniences.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl ca-certificates gnupg zstd libatomic1 \
        python3 python3-venv python3-dev python3-pip python-is-python3 \
        libxml2-dev libxslt1-dev libjpeg-dev zlib1g-dev libffi-dev \
        pkg-config jq unzip ripgrep less \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Smoke-test Python: `python` must exist and venv must ship a working pip.
RUN python --version \
    && python -m venv /tmp/venv-check \
    && /tmp/venv-check/bin/pip --version \
    && rm -rf /tmp/venv-check

# The base image ships uv without its uvx shim.
RUN ln -sf /usr/local/bin/uv /usr/local/bin/uvx && uvx --version

# Point ~/workspace at the mounted workspace. sbx mounts the host directory at
# its own absolute path, so tools that default to ~/workspace (T3 Code, VS Code)
# would otherwise open an empty folder.
RUN printf '\n\
if [ -n "${WORKSPACE_DIR:-}" ] && [ -d "$HOME/workspace" ] && [ ! -L "$HOME/workspace" ] && [ -z "$(ls -A "$HOME/workspace" 2>/dev/null)" ]; then\n\
  rmdir "$HOME/workspace" 2>/dev/null && ln -s "$WORKSPACE_DIR" "$HOME/workspace"\n\
fi\n' >> /etc/sandbox-persistent.sh

USER agent

# Node via nvm, same layout as the pi sandbox: both 22 and 24, default 22.
ARG NODE_DEFAULT=22
ENV NVM_DIR=/home/agent/.nvm
ENV NPM_CONFIG_PREFIX=

RUN unset NPM_CONFIG_PREFIX \
    && rm -f "$HOME/.npmrc" 2>/dev/null || true \
    && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.7/install.sh | bash \
    && . "$NVM_DIR/nvm.sh" \
    && nvm install 22 \
    && nvm install 24 \
    && nvm alias default "${NODE_DEFAULT}" \
    && nvm use default

# CLIs installed with the default Node, then linked into ~/.local/bin.
# nvm only exports PATH from ~/.bashrc, so `sh -lc` (T3 Code, scripts) never
# sees them; ~/.local/bin is first on the image PATH.
RUN . "$NVM_DIR/nvm.sh" \
    && nvm use default \
    && npm install -g --ignore-scripts t3 pnpm yarn \
    && mkdir -p "$HOME/.local/bin" \
    && NODE_BIN="$(dirname "$(nvm which default)")" \
    && for bin in t3 pnpm yarn; do ln -sf "$NODE_BIN/$bin" "$HOME/.local/bin/$bin"; done \
    && sh -lc 't3 --version && pnpm --version && yarn --version && node --version'

# Antigravity CLI from the vendor installer. It lands in ~/.local/bin/agy and
# self-updates from there, so rebuilds pick up whatever the release channel has.
RUN curl -fsSL --compressed https://antigravity.google/cli/install.sh | bash \
    && test -x "$HOME/.local/bin/agy" \
    && sh -lc 'agy --version'

# Global agent configuration: workflow skills plus short always-on rules that
# state the sandbox facts (workspace path, Python for Plone, default Node).
RUN mkdir -p "$HOME/.gemini/antigravity-cli/skills"
COPY --chown=agent:agent skills/ /home/agent/.gemini/antigravity-cli/skills/
COPY --chown=agent:agent home/AGENTS.md /home/agent/.gemini/AGENTS.md

# agy detects a remote environment from SSH_CONNECTION and switches to the
# copy/paste OAuth flow instead of trying to launch a browser and a callback
# listener inside the sandbox. Sign-in is handled by the sbx credential proxy.
ENV SSH_CONNECTION="sandbox 0 sandbox 0"

WORKDIR /home/agent/workspace
ENTRYPOINT ["agy"]
CMD ["--dangerously-skip-permissions", "--mode=accept-edits"]
