#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
need docker kind kubectl
need_kind
docker info >/dev/null 2>&1 || { echo "Start Docker Desktop or the Docker daemon first." >&2; exit 1; }
if kind get clusters | grep -qx "$CLUSTER_NAME"; then
  echo "Cluster $CLUSTER_NAME already exists; reusing it."
else
  kind create cluster --name "$CLUSTER_NAME" --config kind/cluster.yaml --image "$KIND_NODE_IMAGE" --wait 180s
fi
k wait --for=condition=Ready nodes --all --timeout=180s
