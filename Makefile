SHELL := /bin/bash
CONTEXT := kind-ai-ops-poc
.DEFAULT_GOAL := help
.PHONY: help cluster build-image install bootstrap up verify status destroy argocd-ui argocd-password prometheus-ui loki-api demo-service restart-demo reconcile-demo
help:
	@echo "Targets: up cluster build-image install bootstrap verify status destroy"
	@echo "Access: argocd-ui argocd-password prometheus-ui loki-api demo-service"
	@echo "Recovery: restart-demo reconcile-demo"
cluster:
	@bash scripts/cluster.sh
build-image:
	@bash scripts/build-image.sh
install:
	@bash scripts/install.sh
bootstrap:
	@bash scripts/bootstrap.sh
up:
	@bash scripts/up.sh
verify:
	@bash scripts/verify.sh
status:
	kubectl --context $(CONTEXT) get pods -A
	kubectl --context $(CONTEXT) -n argocd get applications
destroy:
	@bash scripts/destroy.sh
argocd-ui:
	kubectl --context $(CONTEXT) -n argocd port-forward service/argocd-server 8443:443 --address 127.0.0.1
argocd-password:
	@kubectl --context $(CONTEXT) -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | python3 -c 'import base64,sys; print(base64.b64decode(sys.stdin.read()).decode())'
prometheus-ui:
	kubectl --context $(CONTEXT) -n monitoring port-forward service/prometheus-server 9090:80 --address 127.0.0.1
loki-api:
	kubectl --context $(CONTEXT) -n monitoring port-forward service/loki 3100:3100 --address 127.0.0.1
demo-service:
	kubectl --context $(CONTEXT) -n demo port-forward service/demo-service 8080:8080 --address 127.0.0.1
restart-demo:
	kubectl --context $(CONTEXT) -n demo rollout restart deployment/demo-service
	kubectl --context $(CONTEXT) -n demo rollout status deployment/demo-service --timeout=180s
reconcile-demo:
	kubectl --context $(CONTEXT) -n argocd annotate application demo-service argocd.argoproj.io/refresh=hard --overwrite
