#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

main() {
  local vti_if="vti42"
  if [[ -f "$RUNTIME_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$RUNTIME_ENV"
    vti_if="${VTI_IF:-vti42}"
  fi

  echo "===== strongSwan statusall ====="
  ipsec statusall || true
  echo

  echo "===== VTI interface (${vti_if}) ====="
  ip -d a show "$vti_if" || true
  echo

  echo "===== Routes (main + VTI/LAN related) ====="
  ip route show || true
  echo

  echo "===== sysctl important values ====="
  sysctl net.ipv4.ip_forward net.ipv4.conf.all.rp_filter net.ipv4.conf.default.rp_filter || true
  if ip link show "$vti_if" >/dev/null 2>&1; then
    sysctl "net.ipv4.conf.${vti_if}.disable_policy" "net.ipv4.conf.${vti_if}.rp_filter" || true
  fi
  echo

  echo "===== iptables (NAT + FORWARD) ====="
  iptables -t nat -S || true
  iptables -S FORWARD || true
  echo

  echo "===== Firewall/UFW ====="
  if command_exists ufw; then
    ufw status verbose || true
  else
    echo "ufw not installed"
  fi
  echo

  local swan_service
  swan_service="$(detect_strongswan_service)"
  echo "===== last 200 logs for ${swan_service} ====="
  journalctl -u "$swan_service" -n 200 --no-pager || true
  echo

  echo "===== Common issue hints ====="
  echo "- مطمئن شوید UDP/500 و UDP/4500 در هر دو سمت باز است."
  echo "- LOCAL_ID/REMOTE_ID و PSK در هر دو سرور باید دقیقاً match باشد."
  echo "- اگر پشت NAT هستید، NAT-T باید فعال باشد (4500/udp)."
  echo "- اگر پکت drop می‌شود، rp_filter باید 0 باشد."
  echo "- در صورت مشکل fragmentation، MTU را کمتر از 1436 تست کنید (مثلاً 1400)."
  echo "- مسیر REMOTE_LAN_CIDR باید روی VTI تنظیم شده باشد."
}

main "$@"
