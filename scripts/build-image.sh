#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
need docker kind
need_kind
docker build -t "$DEMO_IMAGE" demo-service
kind load docker-image "$DEMO_IMAGE" --name "$CLUSTER_NAME"
