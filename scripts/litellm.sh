#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
need helm kubectl openssl

namespace=litellm
bitnami=oci://registry-1.docker.io/bitnamicharts

k create namespace "$namespace" --dry-run=client -o yaml | k apply -f -

# Keep credentials stable across retries and upgrades, including the encryption salt.
ensure_secret() {
  local name=$1 key=$2 prefix=$3 existing value
  shift 3
  existing=$(k -n "$namespace" get secret "$name" --ignore-not-found -o name)
  if [[ -z "$existing" ]]; then
    value=$(openssl rand -hex 32)
    k -n "$namespace" create secret generic "$name" \
      --from-literal="$key=$prefix$value" "$@"
  fi
}

ensure_secret litellm-master-key-secret master-key sk-
ensure_secret litellm-writer-secret password '' --from-literal=username=admin
ensure_secret litellm-redis password ''
ensure_secret litellm-env LITELLM_SALT_KEY sk-

install_chart my-redis "$bitnami/redis" "$REDIS_CHART_VERSION" "$namespace" \
  --set architecture=standalone \
  --set auth.existingSecret=litellm-redis,auth.existingSecretPasswordKey=password \
  --set master.persistence.size=1Gi --set-string "image.digest=$REDIS_IMAGE_DIGEST"

install_chart my-postgres "$bitnami/postgresql" "$POSTGRESQL_CHART_VERSION" "$namespace" \
  --set auth.username=admin,auth.database=litellm,auth.enablePostgresUser=false \
  --set auth.existingSecret=litellm-writer-secret \
  --set primary.persistence.size=2Gi --set-string "image.digest=$POSTGRESQL_IMAGE_DIGEST"

install_chart litellm oci://ghcr.io/berriai/litellm-helm "$LITELLM_CHART_VERSION" "$namespace" \
  --values bootstrap/litellm/values.yaml
