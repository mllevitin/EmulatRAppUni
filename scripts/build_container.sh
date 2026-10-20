#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$source_dir/out"
export LOCAL_UID="$(id -u)"
export LOCAL_GID="$(id -g)"

exec docker compose -f "$source_dir/compose.yaml" run --build --rm builder \
    bash /usr/local/bin/build-emulatr "$@"
