#!/usr/bin/env bash
set -euo pipefail

if ip link show vti42 >/dev/null 2>&1; then
  ip link del vti42 || true
fi
