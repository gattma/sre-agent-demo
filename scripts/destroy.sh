#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
need kind
kind delete cluster --name "$CLUSTER_NAME"
