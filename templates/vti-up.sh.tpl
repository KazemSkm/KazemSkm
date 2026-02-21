#!/usr/bin/env bash
set -euo pipefail

RUNTIME_ENV="__RUNTIME_ENV__"
[[ -f "$RUNTIME_ENV" ]] || exit 0

# shellcheck disable=SC1090
source "$RUNTIME_ENV"

# shellcheck disable=SC1091
source /usr/local/lib/ipsec-vti-systemd-tunnel/common.sh

ip tunnel add vti42 local "$LOCAL_PUBLIC_IP" remote "$REMOTE_PUBLIC_IP" mode vti key 42 2>/dev/null || true
ip link set vti42 up
ip addr replace "$LOCAL_TUN_IP" dev vti42
ip link set vti42 mtu 1436

sysctl -w net.ipv4.conf.vti42.disable_policy=1 >/dev/null
sysctl -w net.ipv4.conf.vti42.rp_filter=0 >/dev/null

if [[ -n "${REMOTE_LAN_CIDR:-}" ]]; then
  ip route replace "$REMOTE_LAN_CIDR" via "$REMOTE_TUN_IP" dev vti42
fi

if [[ -n "${LOCAL_LAN_CIDR:-}" && -n "${REMOTE_LAN_CIDR:-}" ]]; then
  ensure_iptables_rule filter FORWARD -s "$LOCAL_LAN_CIDR" -d "$REMOTE_LAN_CIDR" -j ACCEPT
  ensure_iptables_rule filter FORWARD -s "$REMOTE_LAN_CIDR" -d "$LOCAL_LAN_CIDR" -j ACCEPT
fi

ensure_iptables_rule filter FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

if [[ -n "${FORWARD_RULES:-}" ]]; then
  while IFS=',' read -r proto in_port dst_ip dst_port; do
    proto="$(echo "$proto" | xargs)"
    in_port="$(echo "$in_port" | xargs)"
    dst_ip="$(echo "$dst_ip" | xargs)"
    dst_port="$(echo "$dst_port" | xargs)"

    [[ -n "$proto" && -n "$in_port" && -n "$dst_ip" && -n "$dst_port" ]] || continue

    ensure_iptables_rule nat PREROUTING -i "$PUBLIC_IF" -p "$proto" --dport "$in_port" -j DNAT --to-destination "${dst_ip}:${dst_port}"
    ensure_iptables_rule filter FORWARD -i "$PUBLIC_IF" -o vti42 -p "$proto" -d "$dst_ip" --dport "$dst_port" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT

    if is_true "${ENABLE_SNAT:-false}"; then
      ensure_iptables_rule nat POSTROUTING -o vti42 -p "$proto" -d "$dst_ip" --dport "$dst_port" -j MASQUERADE
    fi
  done < <(parse_forward_rules "$FORWARD_RULES")
fi
