#!/bin/sh
# Checks the running stack through the edge: readiness, sign-in is required, the agents are listed, and one chat message streams to RUN_FINISHED.
# With CODER=1 it also gives Adam a task in the local sandbox repository and checks the branch it pushed. Needs the web/ (or coder/) variant, curl, jq.
#   KUBE_CONTEXT=<context> sh scripts/smoke.sh
set -eu
CTX=${KUBE_CONTEXT:?set KUBE_CONTEXT}; NS=${NAMESPACE:-another-dev}
k() { kubectl --context "$CTX" -n "$NS" "$@"; }
pids=""; trap 'kill $pids 2>/dev/null || true' EXIT
k port-forward svc/another-agentic-edge 18080:8080 >/dev/null 2>&1 & pids="$pids $!"
k port-forward svc/mock-oidc 18099:8080 >/dev/null 2>&1 & pids="$pids $!"
sleep 4
EDGE=http://127.0.0.1:18080
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok:   $*"; }

[ "$(curl -s -o /dev/null -w '%{http_code}' $EDGE/readyz)" = 200 ] || fail "edge /readyz"
ok "edge and orchestrator ready"
[ "$(curl -s -o /dev/null -w '%{http_code}' $EDGE/api/me)" = 401 ] || fail "/api/me without a token should be 401"
ok "no token is refused (401)"
TOKEN=$(curl -fsS -u dev-chat:dev-client-secret -d grant_type=client_credentials --data-urlencode user=dev@example.com http://127.0.0.1:18099/token | jq -r .access_token)
[ -n "$TOKEN" ] || fail "no token from the mock issuer"
H="Authorization: Bearer $TOKEN"
curl -fsS -H "$H" $EDGE/api/me | jq -e '.user == "dev@example.com"' >/dev/null || fail "/api/me"
ok "/api/me answers for dev@example.com"
AGENTS=$(curl -fsS -H "$H" $EDGE/api/agents | jq -r '.[].id' | tr '\n' ' ')
echo "agents: $AGENTS"

run() { # run AGENT TEXT -> prints the final RUN_FINISHED/RUN_ERROR line
  body=$(jq -n --arg t "$(uuidgen | tr A-F a-f)" --arg r "$(uuidgen | tr A-F a-f)" --arg m "$(uuidgen | tr A-F a-f)" --arg x "$2" \
    '{threadId:$t,runId:$r,state:{},tools:[],context:[],messages:[{id:$m,role:"user",content:$x}],forwardedProps:{}}')
  curl -sN -m "${RUN_TIMEOUT:-300}" -H "$H" -H 'Content-Type: application/json' -H 'Accept: text/event-stream' -d "$body" "$EDGE/agui/agents/$1" | grep -E '"type":"RUN_(FINISHED|ERROR)"' | tail -1
}
out=$(run chat "Say hello in one short sentence.")
echo "$out" | grep -q '"outcome":{"type":"success"}' || fail "chat run: $out"
ok "chat agent streamed a reply to RUN_FINISHED success"

if [ "${CODER:-0}" = 1 ]; then
  echo "$AGENTS" | grep -q coder || fail "the coder agent is not listed (apply the coder/ variant and restart the orchestrator)"
  out=$(RUN_TIMEOUT=540 run coder "In http://git-server:8080/local/sandbox.git (base branch main), add a file hello.txt containing the single line hello. Run the checks and open a pull request.")
  echo "$out" | grep -q '"outcome":{"type":"success"}' || fail "coder run: $out"
  branch=$(k exec deploy/git-server -- sh -c 'cd /srv/git/local/sandbox.git && git for-each-ref --format="%(refname:short)" refs/heads/agent | tail -1')
  [ -n "$branch" ] || fail "no agent/* branch on the git server"
  content=$(k exec deploy/git-server -- sh -c "cd /srv/git/local/sandbox.git && git show $branch:hello.txt")
  [ "$content" = hello ] || fail "hello.txt on $branch contains: $content"
  ok "Adam pushed $branch with hello.txt = hello"
fi
echo "smoke test passed"
