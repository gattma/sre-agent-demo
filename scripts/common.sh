#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
source "$ROOT/versions.env"
CLUSTER_NAME=ai-ops-poc
CONTEXT=kind-ai-ops-poc
k() { kubectl --context "$CONTEXT" "$@"; }
need() {
  for tool in "$@"; do
    command -v "$tool" >/dev/null || { echo "Missing prerequisite: $tool" >&2; exit 1; }
  done
}
repo_config() {
  need python3
  : "${GIT_REPO_URL:?Set GIT_REPO_URL to the public GitHub repository containing these committed files.}"
  export GIT_REPO_URL
  export GIT_REVISION="${GIT_REVISION:-main}"
  python3 - <<'CHECK'
import os, re
url = os.environ["GIT_REPO_URL"]
if not re.fullmatch(r"https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?", url):
    raise SystemExit("GIT_REPO_URL must be a public https://github.com/owner/repo URL")
CHECK
}

need_kind() {
  need kind python3
  kind version | python3 -c 'import re,sys; m=re.search(r"v(\d+)\.(\d+)\.(\d+)", sys.stdin.read()); sys.exit(0 if m and tuple(map(int,m.groups())) >= (0,27,0) else "kind 0.27.0+ is required for the pinned Kubernetes/containerd image; update kind first.")'
}
