#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
need kubectl
repo_config
echo "Argo CD will read $GIT_REPO_URL at $GIT_REVISION. Push these files there first."
# JSON-quoted substitutions are valid YAML scalar values; no envsubst dependency.
python3 - <<'RENDER' | k apply -f -
import json, os
from pathlib import Path
text = Path("gitops/applications/demo-service.yaml").read_text()
for key in ("GIT_REPO_URL", "GIT_REVISION"):
    text = text.replace("${" + key + "}", json.dumps(os.environ[key]))
print(text)
RENDER
k annotate application demo-service -n argocd argocd.argoproj.io/refresh=hard --overwrite
for attempt in {1..120}; do
  state=$(k get application demo-service -n argocd -o jsonpath='{.status.sync.status}/{.status.health.status}')
  if [ "$state" = "Synced/Healthy" ]; then
    echo "demo-service Synced/Healthy"
    exit 0
  fi
  sleep 5
done
k get application demo-service -n argocd -o yaml
echo "Timed out waiting for GitOps sync. Check repository URL/revision, pushed files, and local image." >&2
exit 1
