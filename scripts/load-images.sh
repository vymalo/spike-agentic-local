#!/bin/sh
# Gets the images into the cluster's node(s) so the first start does not stall on pulls (the adam image is about 3 GB; a kubelet pulls one image at a time).
#   CLUSTER=minikube NAME=another-dev sh scripts/load-images.sh        (NAME is the minikube profile)
#   CLUSTER=kind     NAME=another-dev sh scripts/load-images.sh        (NAME is the kind cluster name; node container is <NAME>-control-plane)
set -eu
CLUSTER=${CLUSTER:?CLUSTER=minikube or kind}; NAME=${NAME:?NAME of the minikube profile or kind cluster}
WITH_CODER=${WITH_CODER:-1}
ADAM="ghcr.io/vymalo/another-adam-rs/coder:sha-ddef35e@sha256:14a0e0dfed8f8244b73b46c46043852355a7f5d97ce4ead45f67233eeef86a44"
REMOTE="postgres:17-alpine $ADAM"
[ "$WITH_CODER" = 1 ] && REMOTE="$REMOTE wiremock/wiremock:3.13.2"
LOCAL="another-agentic-system/mock-oidc:dev"
[ "$WITH_CODER" = 1 ] && LOCAL="$LOCAL another-agentic-system/git-server:dev"
for img in $REMOTE; do
  echo "pulling in the node: $img"
  case $CLUSTER in
    minikube) minikube -p "$NAME" ssh -- "sudo docker pull $img >/dev/null" ;;
    kind)     docker exec "$NAME-control-plane" crictl pull "$img" >/dev/null ;;
    *) echo "CLUSTER must be minikube or kind" >&2; exit 1 ;;
  esac
done
for img in $LOCAL; do
  echo "loading: $img"
  case $CLUSTER in
    minikube) minikube -p "$NAME" image load "$img" ;;
    kind)     kind load docker-image "$img" --name "$NAME" ;;
  esac
done
