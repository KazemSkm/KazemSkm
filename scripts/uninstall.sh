#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

remove_runtime_iptables_rules() {
  [[ -f "$IPTABLES_ENV" ]] || return 0
  load_env_file "$IPTABLES_ENV"

  VTI_IF="${VTI_IF:-vti42}"
  FORWARD_RULES="${FORWARD_RULES:-}"
  LOCAL_LAN_CIDR="${LOCAL_LAN_CIDR:-}"
  REMOTE_LAN_CIDR="${REMOTE_LAN_CIDR:-}"
  PUBLIC_IF="${PUBLIC_IF:-}"
  ENABLE_SNAT="${ENABLE_SNAT:-false}"

  if [[ -n "$LOCAL_LAN_CIDR" && -n "$REMOTE_LAN_CIDR" ]]; then
    remove_iptables_rule filter FORWARD -s "$LOCAL_LAN_CIDR" -d "$REMOTE_LAN_CIDR" -j ACCEPT
    remove_iptables_rule filter FORWARD -s "$REMOTE_LAN_CIDR" -d "$LOCAL_LAN_CIDR" -j ACCEPT
  fi

  if [[ -n "$FORWARD_RULES" && -n "$PUBLIC_IF" ]]; then
    while IFS=',' read -r proto public_port dst_ip dst_port; do
      proto="$(echo "$proto" | xargs)"
      public_port="$(echo "$public_port" | xargs)"
      dst_ip="$(echo "$dst_ip" | xargs)"
      dst_port="$(echo "$dst_port" | xargs)"

      [[ -n "$proto" && -n "$public_port" && -n "$dst_ip" && -n "$dst_port" ]] || continue

      remove_iptables_rule nat PREROUTING -i "$PUBLIC_IF" -p "$proto" --dport "$public_port" -j DNAT --to-destination "${dst_ip}:${dst_port}"
      remove_iptables_rule filter FORWARD -i "$PUBLIC_IF" -o "$VTI_IF" -p "$proto" -d "$dst_ip" --dport "$dst_port" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT

      if is_true "$ENABLE_SNAT"; then
        remove_iptables_rule nat POSTROUTING -o "$VTI_IF" -p "$proto" -d "$dst_ip" --dport "$dst_port" -j MASQUERADE
      fi
    done < <(parse_forward_rules "$FORWARD_RULES")
  fi
}

main() {
  require_root

  local swan_service
  swan_service="$(detect_strongswan_service)"

  systemctl stop "$swan_service" || true
  systemctl disable ipsec-vti-iptables.service >/dev/null 2>&1 || true
  systemctl stop ipsec-vti-iptables.service >/dev/null 2>&1 || true

  remove_runtime_iptables_rules || true

  rm -f /etc/systemd/system/ipsec-vti-iptables.service
  rm -f /usr/local/sbin/ipsec-vti-apply-iptables
  rm -f /usr/local/lib/ipsec-vti-autotunnel/common.sh
  rmdir /usr/local/lib/ipsec-vti-autotunnel >/dev/null 2>&1 || true

  rm -f /etc/ipsec.d/vti-up.sh /etc/ipsec.d/vti-down.sh /etc/ipsec.d/ipsec-vti-updown.sh
  rm -f /etc/sysctl.d/99-ipsec-vti-autotunnel.conf

  if [[ -f /etc/ipsec.conf.ipsec-vti-autotunnel.bak ]]; then
    cp -f /etc/ipsec.conf.ipsec-vti-autotunnel.bak /etc/ipsec.conf
  fi

  if [[ -f /etc/ipsec.secrets.ipsec-vti-autotunnel.bak ]]; then
    cp -f /etc/ipsec.secrets.ipsec-vti-autotunnel.bak /etc/ipsec.secrets
  fi

  if [[ -f "$RUNTIME_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$RUNTIME_ENV"
    if [[ -n "${VTI_IF:-}" ]]; then
      ip link del "$VTI_IF" >/dev/null 2>&1 || true
    fi
  fi

  rm -rf "$RUNTIME_DIR"

  systemctl daemon-reload
  sysctl --system >/dev/null || true
  systemctl restart "$swan_service" || true

  log "Uninstall completed"
}

main "$@"
