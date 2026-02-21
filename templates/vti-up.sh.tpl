#!/usr/bin/env bash
set -euo pipefail

RUNTIME_ENV="__RUNTIME_ENV__"
[[ -f "$RUNTIME_ENV" ]] || exit 0

# shellcheck disable=SC1090
source "$RUNTIME_ENV"

VTI_IF="${VTI_IF:-vti42}"
VTI_KEY="${VTI_KEY:-42}"

ip tunnel add "$VTI_IF" local "$LOCAL_PUBLIC_IP" remote "$REMOTE_PUBLIC_IP" mode vti key "$VTI_KEY" 2>/dev/null || true
ip link set "$VTI_IF" up
ip addr replace "$LOCAL_TUN_IP" dev "$VTI_IF"
ip link set "$VTI_IF" mtu 1436

sysctl -w "net.ipv4.conf.${VTI_IF}.disable_policy=1" >/dev/null
sysctl -w "net.ipv4.conf.${VTI_IF}.rp_filter=0" >/dev/null

if [[ -n "${REMOTE_LAN_CIDR:-}" ]]; then
  ip route replace "$REMOTE_LAN_CIDR" via "$REMOTE_TUN_IP" dev "$VTI_IF"
fi
