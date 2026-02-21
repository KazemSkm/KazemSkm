#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/common.sh"

remove_forward_rules() {
  [[ -f "$RUNTIME_ENV" ]] || return 0
  # shellcheck disable=SC1090
  source "$RUNTIME_ENV"

  local rules="${FORWARD_RULES:-}"
  local public_if="${PUBLIC_IF:-}"
  local enable_snat="${ENABLE_SNAT:-false}"

  [[ -z "$rules" || -z "$public_if" ]] && return 0

  while IFS=',' read -r proto in_port dst_ip dst_port; do
    proto="$(echo "$proto" | xargs)"
    in_port="$(echo "$in_port" | xargs)"
    dst_ip="$(echo "$dst_ip" | xargs)"
    dst_port="$(echo "$dst_port" | xargs)"

    [[ -n "$proto" && -n "$in_port" && -n "$dst_ip" && -n "$dst_port" ]] || continue

    remove_iptables_rule nat PREROUTING -i "$public_if" -p "$proto" --dport "$in_port" -j DNAT --to-destination "${dst_ip}:${dst_port}"
    remove_iptables_rule filter FORWARD -i "$public_if" -o vti42 -p "$proto" -d "$dst_ip" --dport "$dst_port" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT

    if is_true "$enable_snat"; then
      remove_iptables_rule nat POSTROUTING -o vti42 -p "$proto" -d "$dst_ip" --dport "$dst_port" -j MASQUERADE
    fi
  done < <(parse_forward_rules "$rules")
}

restore_ipsec_backups() {
  if [[ -f /etc/ipsec.conf.ipsec-vti-systemd-tunnel.bak ]]; then
    cp -f /etc/ipsec.conf.ipsec-vti-systemd-tunnel.bak /etc/ipsec.conf
  fi

  if [[ -f /etc/ipsec.secrets.ipsec-vti-systemd-tunnel.bak ]]; then
    cp -f /etc/ipsec.secrets.ipsec-vti-systemd-tunnel.bak /etc/ipsec.secrets
  fi
}

main() {
  require_root

  systemctl stop ipsec-vti.service >/dev/null 2>&1 || true
  systemctl disable ipsec-vti.service >/dev/null 2>&1 || true

  remove_forward_rules || true

  ip link del vti42 >/dev/null 2>&1 || true

  rm -f /etc/systemd/system/ipsec-vti.service
  rm -f /etc/ipsec.d/vti-up.sh /etc/ipsec.d/vti-down.sh /etc/ipsec.d/ipsec-vti-updown.sh
  rm -f /etc/sysctl.d/99-ipsec-vti-systemd-tunnel.conf
  rm -rf /etc/ipsec-vti-systemd-tunnel
  rm -f /usr/local/bin/tunnel-status
  rm -f /usr/local/lib/ipsec-vti-systemd-tunnel/common.sh
  rmdir /usr/local/lib/ipsec-vti-systemd-tunnel >/dev/null 2>&1 || true

  restore_ipsec_backups

  systemctl daemon-reload
  sysctl --system >/dev/null || true

  log "Uninstall completed"
}

main "$@"
