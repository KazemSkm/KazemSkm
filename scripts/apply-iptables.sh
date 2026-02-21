#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_DIR}/common.sh" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/common.sh"
elif [[ -f /usr/local/lib/ipsec-vti-autotunnel/common.sh ]]; then
  # shellcheck disable=SC1091
  source /usr/local/lib/ipsec-vti-autotunnel/common.sh
else
  echo "[ERROR] common.sh not found" >&2
  exit 1
fi

ENV_FILE="${1:-$IPTABLES_ENV}"

main() {
  require_root
  [[ -f "$ENV_FILE" ]] || die "iptables env file not found: $ENV_FILE"

  load_env_file "$ENV_FILE"

  VTI_IF="${VTI_IF:-vti42}"
  FORWARD_RULES="${FORWARD_RULES:-}"
  LOCAL_LAN_CIDR="${LOCAL_LAN_CIDR:-}"
  REMOTE_LAN_CIDR="${REMOTE_LAN_CIDR:-}"
  PUBLIC_IF="${PUBLIC_IF:-}"
  ENABLE_SNAT="${ENABLE_SNAT:-false}"

  if [[ -z "$PUBLIC_IF" ]]; then
    PUBLIC_IF="$(default_route_iface || true)"
  fi

  [[ -n "$PUBLIC_IF" ]] || die "Unable to detect PUBLIC_IF"

  ensure_iptables_rule filter FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

  if [[ -n "$LOCAL_LAN_CIDR" && -n "$REMOTE_LAN_CIDR" ]]; then
    ensure_iptables_rule filter FORWARD -s "$LOCAL_LAN_CIDR" -d "$REMOTE_LAN_CIDR" -j ACCEPT
    ensure_iptables_rule filter FORWARD -s "$REMOTE_LAN_CIDR" -d "$LOCAL_LAN_CIDR" -j ACCEPT
  fi

  if [[ -n "$FORWARD_RULES" ]]; then
    while IFS=',' read -r proto public_port dst_ip dst_port; do
      proto="$(echo "$proto" | xargs)"
      public_port="$(echo "$public_port" | xargs)"
      dst_ip="$(echo "$dst_ip" | xargs)"
      dst_port="$(echo "$dst_port" | xargs)"

      [[ -n "$proto" && -n "$public_port" && -n "$dst_ip" && -n "$dst_port" ]] || {
        warn "Skipping invalid FORWARD_RULE entry"
        continue
      }

      ensure_iptables_rule nat PREROUTING -i "$PUBLIC_IF" -p "$proto" --dport "$public_port" -j DNAT --to-destination "${dst_ip}:${dst_port}"
      ensure_iptables_rule filter FORWARD -i "$PUBLIC_IF" -o "$VTI_IF" -p "$proto" -d "$dst_ip" --dport "$dst_port" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT

      if is_true "$ENABLE_SNAT"; then
        ensure_iptables_rule nat POSTROUTING -o "$VTI_IF" -p "$proto" -d "$dst_ip" --dport "$dst_port" -j MASQUERADE
      fi
    done < <(parse_forward_rules "$FORWARD_RULES")
  fi

  log "iptables rules are applied idempotently"
}

main "$@"
