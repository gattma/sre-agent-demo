#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
need helm kubectl
install_chart() {
  local release=$1 chart=$2 repo=$3 version=$4 namespace=$5 values=$6
  helm upgrade --install "$release" "$chart" --repo "$repo" --version "$version" \
    --kube-context "$CONTEXT" --namespace "$namespace" --create-namespace \
    --values "$values" --wait --timeout 10m --history-max 3
}
install_chart argocd argo-cd https://argoproj.github.io/argo-helm "$ARGOCD_CHART_VERSION" argocd bootstrap/argocd/values.yaml
install_chart prometheus prometheus https://prometheus-community.github.io/helm-charts "$PROMETHEUS_CHART_VERSION" monitoring bootstrap/prometheus/values.yaml
install_chart loki loki https://grafana.github.io/helm-charts "$LOKI_CHART_VERSION" monitoring bootstrap/loki/values.yaml
k apply -f bootstrap/loki/alloy-rbac.yaml
install_chart alloy alloy https://grafana.github.io/helm-charts "$ALLOY_CHART_VERSION" monitoring bootstrap/loki/alloy-values.yaml
