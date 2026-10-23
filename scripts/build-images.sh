#!/bin/sh
# Builds the two small images this repo needs that are not published: the mock OpenID issuer (web/ variant) and the git server (coder/ variant).
# Their sources live in vymalo/another-agentic-system (dev/mock-oidc, dev/coder/git-server), fetched at a pinned commit into .cache/.
set -eu
REF=${SYSTEM_REF:-ce39839}
cd "$(dirname "$0")/.."
mkdir -p .cache
if [ ! -d .cache/another-agentic-system/.git ]; then
  git clone --quiet https://github.com/vymalo/another-agentic-system.git .cache/another-agentic-system
fi
git -C .cache/another-agentic-system fetch --quiet origin
git -C .cache/another-agentic-system checkout --quiet "$REF"
docker build -q -t another-agentic-system/mock-oidc:dev .cache/another-agentic-system/dev/mock-oidc
docker build -q -t another-agentic-system/git-server:dev .cache/another-agentic-system/dev/coder/git-server
echo "built mock-oidc:dev and git-server:dev from another-agentic-system@$REF"
