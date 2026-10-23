#!/bin/sh
# Creates the namespace and the Secrets the manifests read. Nothing secret is stored in this repository.
# Re-running keeps the values that already exist (a new database password would no longer match the running Postgres).
#
#   KUBE_CONTEXT=<context> sh scripts/secrets.sh /path/to/model-api-key
#
# The key file holds the bearer token for the OpenAI-compatible endpoint named in the manifests (see scripts/configure.sh).
set -eu
KEYFILE=${1:?usage: sh scripts/secrets.sh /path/to/model-api-key}
[ -s "$KEYFILE" ] || { echo "secrets.sh: $KEYFILE is empty or missing" >&2; exit 1; }
CTX=${KUBE_CONTEXT:?set KUBE_CONTEXT to the kubectl context of the cluster (minikube: <profile>, kind: kind-<name>)}
NS=${NAMESPACE:-another-dev}
k() { kubectl --context "$CTX" -n "$NS" "$@"; }
rnd() { openssl rand -hex "$1"; }
# existing SECRET KEY: the value already in the cluster, or nothing
existing() { k get secret "$1" -o "jsonpath={.data.$2}" 2>/dev/null | base64 -d 2>/dev/null || true; }
keep() { v=$(existing "$1" "$2"); [ -n "$v" ] && printf '%s' "$v" || rnd "$3"; }

kubectl --context "$CTX" create namespace "$NS" --dry-run=client -o yaml | kubectl --context "$CTX" apply -f - >/dev/null
PG=$(keep another-agentic-db-auth password 16)
CHAT_TOKEN=$(keep another-agentic-chat A2A_BEARER_TOKENS 32)
CODER_TOKEN=$(keep another-agentic-coder A2A_BEARER_TOKENS 32)
THREAD_TOOLS=$(keep another-agentic-orchestrator thread-tools-secret 32)
DB="another-agentic-db.$NS.svc:5432"
apply() { k create secret generic "$@" --dry-run=client -o yaml | k apply -f - >/dev/null; }

apply another-agentic-db-auth --from-literal=password="$PG"
apply another-agentic-db-app   --from-literal=uri="postgresql://postgres:$PG@$DB/orchestrator"
apply another-agentic-db-agent --from-literal=uri="postgresql://postgres:$PG@$DB/agent"
apply another-agentic-orchestrator --from-literal=thread-tools-secret="$THREAD_TOOLS" --from-file=model-api-key="$KEYFILE" \
  --from-literal=CHAT_A2A_TOKEN="$CHAT_TOKEN" --from-literal=CODER_A2A_TOKEN="$CODER_TOKEN"
apply another-agentic-chat  --from-literal=A2A_BEARER_TOKENS="$CHAT_TOKEN" --from-file=MODEL_API_KEY="$KEYFILE"
# Adam (the coder/ variant): its own database, the bearer it shares with the orchestrator, and a dummy token for the mock GitHub.
apply another-agentic-coder --from-literal=DATABASE_URL="postgresql://postgres:$PG@$DB/coder" --from-file=MODEL_API_KEY="$KEYFILE" \
  --from-literal=A2A_BEARER_TOKENS="$CODER_TOKEN" --from-literal=GITHUB_TOKEN=dev-github-token
echo "secrets ready in $CTX/$NS"
