#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
need docker kind kubectl helm curl python3
need_kind
repo_config
bash scripts/cluster.sh
bash scripts/build-image.sh
bash scripts/install.sh
bash scripts/bootstrap.sh
bash scripts/verify.sh
