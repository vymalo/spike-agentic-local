#!/bin/sh
# Points the manifests at your OpenAI-compatible endpoint and models (edits base/ and coder/ in place).
#   sh scripts/configure.sh <base-url-with-/v1> <chat-model> <coder-model>
#   sh scripts/configure.sh https://api.example.com/v1 my-chat-model my-coder-model
set -eu
URL=${1:?base url, with /v1}; CHAT=${2:?chat model}; CODER=${3:?coder model}
cd "$(dirname "$0")/.."
OLD_URL=$(sed -n 's/.*MODEL_BASE_URL, value: "\(.*\)".*/\1/p' coder/coder.yaml | head -1)
OLD_CHAT=$(sed -n '/name: MODEL$/{n;s/.*value: "\(.*\)".*/\1/p;}' base/chat.yaml | head -1)
OLD_CODER=$(sed -n 's/.*{ name: MODEL, value: "\(.*\)" }.*/\1/p' coder/coder.yaml | head -1)
sed -i.bak "s#$OLD_URL#$URL#g" base/orchestrator.yaml base/chat.yaml web/patch-orchestrator-config.yaml coder/coder.yaml
sed -i.bak "s#\"$OLD_CHAT\"#\"$CHAT\"#g" base/orchestrator.yaml base/chat.yaml web/patch-orchestrator-config.yaml
sed -i.bak "s#\"$OLD_CODER\"#\"$CODER\"#g" coder/coder.yaml
find . -name '*.bak' -delete
echo "endpoint $OLD_URL -> $URL, chat model $OLD_CHAT -> $CHAT, coder model $OLD_CODER -> $CODER"
