#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
need kind kubectl curl python3
printf 'AI Ops PoC verification\n\n'
pids=""
workdir=$(mktemp -d)
cleanup() {
  for pid in $pids; do kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; done
  rm -rf "$workdir"
}
trap cleanup EXIT
ok() { echo "[OK] $1"; }
fail() { echo "[FAIL] $1" >&2; exit 1; }
kind get clusters | grep -qx "$CLUSTER_NAME" || fail 'kind cluster'
ok 'kind cluster'
k get --raw=/readyz >/dev/null || fail 'Kubernetes API'
ok 'Kubernetes API'
k rollout status deployment/argocd-server -n argocd --timeout=180s >/dev/null || fail 'Argo CD server'
k rollout status deployment/argocd-repo-server -n argocd --timeout=180s >/dev/null || fail 'Argo CD repo server'
k rollout status statefulset/argocd-application-controller -n argocd --timeout=180s >/dev/null || fail 'Argo CD controller'
ok 'Argo CD'
k get application demo-service -n argocd >/dev/null || fail 'demo-service Application exists'
ok 'demo-service Application exists'
state=$(k get application demo-service -n argocd -o jsonpath='{.status.sync.status}/{.status.health.status}')
[ "$state" = 'Synced/Healthy' ] || fail "demo-service Application: $state"
ok 'demo-service Application Synced/Healthy'
k rollout status deployment/demo-service -n demo --timeout=180s >/dev/null || fail 'demo-service pod'
ok 'demo-service pod'
k rollout status deployment/prometheus-server -n monitoring --timeout=180s >/dev/null || fail 'Prometheus'
ok 'Prometheus'
k rollout status statefulset/loki -n monitoring --timeout=180s >/dev/null || fail 'Loki'
ok 'Loki'
k rollout status deployment/alloy -n monitoring --timeout=180s >/dev/null || fail 'Alloy'
ok 'Alloy'
# Let kubectl allocate free localhost ports; do not interfere with UI forwards.
forward() {
  local namespace=$1 service=$2 remote=$3 logfile="$workdir/$2.log"
  k port-forward -n "$namespace" "service/$service" ":$remote" --address 127.0.0.1 >"$logfile" 2>&1 &
  pids="$pids $!"
  for attempt in {1..50}; do
    port=$(sed -n 's/.*127.0.0.1:\([0-9]*\) ->.*/\1/p' "$logfile" | head -1)
    if [ -n "$port" ]; then return; fi
    sleep 0.2
  done
  cat "$logfile" >&2
  fail "port-forward $service"
}
forward demo demo-service 8080
demo_port=$port
curl --fail --silent --max-time 5 "http://127.0.0.1:$demo_port/health" > /dev/null || fail 'demo-service /health'
ok 'demo-service /health'
forward monitoring prometheus-server 80
prom_port=$port
forward monitoring loki 3100
loki_port=$port
# Allow time for the first scrape and log delivery; retry actual evidence.
for attempt in {1..30}; do
  if curl -fsS --max-time 5 --get "http://127.0.0.1:$prom_port/api/v1/query" \
    --data-urlencode 'query=up{job="demo-service",service="demo-service"}' >"$workdir/prom.json" &&
    python3 - "$workdir/prom.json" <<'CHECK'
import json, sys
r = json.load(open(sys.argv[1]))
assert r["status"] == "success" and any(float(x["value"][1]) == 1 for x in r["data"]["result"])
CHECK
  then break; fi
  [ "$attempt" -lt 30 ] || fail 'demo-service Prometheus target'
  sleep 2
done
ok 'demo-service Prometheus target'
curl -fsS --max-time 5 --get "http://127.0.0.1:$prom_port/api/v1/query" \
  --data-urlencode 'query=http_requests_total{service="demo-service",path="/health",status="200"}' >"$workdir/metrics.json"
python3 - "$workdir/metrics.json" <<'CHECK' || fail 'demo-service request metrics'
import json, sys
assert any(float(x["value"][1]) > 0 for x in json.load(open(sys.argv[1]))["data"]["result"])
CHECK
ok 'demo-service request metrics'
for attempt in {1..30}; do
  if curl -fsS --max-time 5 --get "http://127.0.0.1:$loki_port/loki/api/v1/query_range" \
    --data-urlencode 'query={namespace="demo",service="demo-service"} | json | path="/health"' \
    --data-urlencode 'since=10m' >"$workdir/logs.json" &&
    python3 - "$workdir/logs.json" <<'CHECK'
import json, sys
r = json.load(open(sys.argv[1]))
assert r["status"] == "success" and any(x["values"] for x in r["data"]["result"])
CHECK
  then break; fi
  [ "$attempt" -lt 30 ] || fail 'demo-service logs available in Loki'
  sleep 2
done
ok 'demo-service logs available in Loki'
printf '\nEnvironment healthy.\n'
