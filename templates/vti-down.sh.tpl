#!/usr/bin/env bash
set -euo pipefail

RUNTIME_ENV="__RUNTIME_ENV__"
[[ -f "$RUNTIME_ENV" ]] || exit 0

# shellcheck disable=SC1090
source "$RUNTIME_ENV"

VTI_IF="${VTI_IF:-vti42}"

if ip link show "$VTI_IF" >/dev/null 2>&1; then
  ip link del "$VTI_IF" || true
fi
