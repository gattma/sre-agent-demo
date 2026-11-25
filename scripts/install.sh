#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
need helm kubectl openssl
install_chart argocd argo-cd "$ARGOCD_CHART_VERSION" argocd \
  --repo https://argoproj.github.io/argo-helm --values bootstrap/argocd/values.yaml
install_chart prometheus prometheus "$PROMETHEUS_CHART_VERSION" monitoring \
  --repo https://prometheus-community.github.io/helm-charts --values bootstrap/prometheus/values.yaml
install_chart loki loki "$LOKI_CHART_VERSION" monitoring \
  --repo https://grafana.github.io/helm-charts --values bootstrap/loki/values.yaml
k apply -f bootstrap/loki/alloy-rbac.yaml
install_chart alloy alloy "$ALLOY_CHART_VERSION" monitoring \
  --repo https://grafana.github.io/helm-charts --values bootstrap/loki/alloy-values.yaml
bash scripts/litellm.sh
