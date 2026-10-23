# Local another-agentic-system on minikube or kind. See README.md.
CLUSTER ?= minikube
NAME    ?= another-dev
VARIANT ?= web
KEYFILE ?= model-api-key
CTX     := $(if $(filter kind,$(CLUSTER)),kind-$(NAME),$(NAME))
export KUBE_CONTEXT := $(CTX)
export CLUSTER NAME

.PHONY: cluster images load secrets deploy restart forward smoke down
cluster:   ## create the cluster (minikube: 6 CPU / 5 GB; kind: default node)
ifeq ($(CLUSTER),kind)
	kind create cluster --name $(NAME)
else
	minikube start -p $(NAME) --driver=docker --cpus=6 --memory=5000
endif
images:    ## build mock-oidc and git-server
	sh scripts/build-images.sh
load:      ## pre-pull the big images into the node and load the built ones
	WITH_CODER=$(if $(filter coder,$(VARIANT)),1,0) sh scripts/load-images.sh
secrets:   ## create namespace and Secrets from the file KEYFILE
	sh scripts/secrets.sh $(KEYFILE)
deploy:    ## apply VARIANT = base | web | coder
	kubectl --context $(CTX) kustomize $(VARIANT) | kubectl --context $(CTX) apply -f -
restart:   ## the orchestrator reads its config once, at startup
	kubectl --context $(CTX) -n another-dev rollout restart deploy/another-agentic-orchestrator
forward:   ## UI on http://127.0.0.1:8080 (sign-in redirects use these ports)
	kubectl --context $(CTX) -n another-dev port-forward svc/another-agentic-edge 8080:8080 & \
	kubectl --context $(CTX) -n another-dev port-forward svc/mock-oidc 8099:8080
smoke:     ## end-to-end check (CODER=1 adds Adam)
	sh scripts/smoke.sh
down:
ifeq ($(CLUSTER),kind)
	kind delete cluster --name $(NAME)
else
	minikube delete -p $(NAME)
endif
