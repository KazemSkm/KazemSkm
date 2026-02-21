#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/common.sh"

ENV_FILE="${1:-${ROOT_DIR}/.env}"
CONN_NAME="s2s-vti"
SERVICE_NAME="ipsec-vti"

validate_env() {
  ROLE="${ROLE:-}"
  LOCAL_PUBLIC_IP="${LOCAL_PUBLIC_IP:-}"
  REMOTE_PUBLIC_IP="${REMOTE_PUBLIC_IP:-}"
  PSK="${PSK:-}"
  LOCAL_TUN_IP="${LOCAL_TUN_IP:-}"
  REMOTE_TUN_IP="${REMOTE_TUN_IP:-}"
  LOCAL_LAN_CIDR="${LOCAL_LAN_CIDR:-}"
  REMOTE_LAN_CIDR="${REMOTE_LAN_CIDR:-}"
  FORWARD_RULES="${FORWARD_RULES:-}"
  ENABLE_SNAT="${ENABLE_SNAT:-false}"
  PUBLIC_IF="${PUBLIC_IF:-}"

  [[ "$ROLE" == "iran" || "$ROLE" == "foreign" ]] || die "ROLE باید iran یا foreign باشد."
  [[ -n "$LOCAL_PUBLIC_IP" ]] || die "LOCAL_PUBLIC_IP الزامی است."
  [[ -n "$REMOTE_PUBLIC_IP" ]] || die "REMOTE_PUBLIC_IP الزامی است."
  [[ -n "$PSK" ]] || die "PSK الزامی است."
  [[ -n "$LOCAL_TUN_IP" ]] || die "LOCAL_TUN_IP الزامی است."
  [[ -n "$REMOTE_TUN_IP" ]] || die "REMOTE_TUN_IP الزامی است."

  if [[ -z "$PUBLIC_IF" ]]; then
    PUBLIC_IF="$(default_route_iface || true)"
  fi
  [[ -n "$PUBLIC_IF" ]] || die "PUBLIC_IF خالی است و auto-detect هم شکست خورد."

  validate_forward_rules "$FORWARD_RULES"
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y strongswan iproute2 iptables
}

configure_sysctl() {
  safe_write_file /etc/sysctl.d/99-ipsec-vti-systemd-tunnel.conf 0644 <<'EOF_SYSCTL'
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
EOF_SYSCTL
  sysctl --system >/dev/null
}

write_runtime_env() {
  install -d -m 0700 "$RUNTIME_DIR"

  safe_write_file "$RUNTIME_ENV" 0600 <<EOF_RUNTIME
ROLE=$(quote_env "$ROLE")
CONN_NAME=$(quote_env "$CONN_NAME")
LOCAL_PUBLIC_IP=$(quote_env "$LOCAL_PUBLIC_IP")
REMOTE_PUBLIC_IP=$(quote_env "$REMOTE_PUBLIC_IP")
LOCAL_TUN_IP=$(quote_env "$LOCAL_TUN_IP")
REMOTE_TUN_IP=$(quote_env "$REMOTE_TUN_IP")
LOCAL_LAN_CIDR=$(quote_env "$LOCAL_LAN_CIDR")
REMOTE_LAN_CIDR=$(quote_env "$REMOTE_LAN_CIDR")
FORWARD_RULES=$(quote_env "$FORWARD_RULES")
ENABLE_SNAT=$(quote_env "$ENABLE_SNAT")
PUBLIC_IF=$(quote_env "$PUBLIC_IF")
EOF_RUNTIME
}

render_configs() {
  backup_once /etc/ipsec.conf
  backup_once /etc/ipsec.secrets

  sed \
    -e "s|__LOCAL_PUBLIC_IP__|${LOCAL_PUBLIC_IP}|g" \
    -e "s|__REMOTE_PUBLIC_IP__|${REMOTE_PUBLIC_IP}|g" \
    -e "s|__CONN_NAME__|${CONN_NAME}|g" \
    "${ROOT_DIR}/templates/ipsec.conf.tpl" | safe_write_file /etc/ipsec.conf 0644

  sed \
    -e "s|__LOCAL_PUBLIC_IP__|${LOCAL_PUBLIC_IP}|g" \
    -e "s|__REMOTE_PUBLIC_IP__|${REMOTE_PUBLIC_IP}|g" \
    -e "s|__PSK__|${PSK}|g" \
    "${ROOT_DIR}/templates/ipsec.secrets.tpl" | safe_write_file /etc/ipsec.secrets 0600

  sed -e "s|__RUNTIME_ENV__|${RUNTIME_ENV}|g" "${ROOT_DIR}/templates/vti-up.sh.tpl" | safe_write_file /etc/ipsec.d/vti-up.sh 0750
  sed -e "s|__RUNTIME_ENV__|${RUNTIME_ENV}|g" "${ROOT_DIR}/templates/vti-down.sh.tpl" | safe_write_file /etc/ipsec.d/vti-down.sh 0750

  safe_write_file /etc/ipsec.d/ipsec-vti-updown.sh 0750 <<'EOF_UPDOWN'
#!/usr/bin/env bash
set -euo pipefail

case "${PLUTO_VERB:-}" in
  up-client|up-host|up-ike)
    /etc/ipsec.d/vti-up.sh
    ;;
  down-client|down-host|down-ike)
    /etc/ipsec.d/vti-down.sh
    ;;
  *)
    ;;
esac
EOF_UPDOWN
}

install_service() {
  sed -e "s|__CONN_NAME__|${CONN_NAME}|g" "${ROOT_DIR}/templates/ipsec-vti.service.tpl" | safe_write_file /etc/systemd/system/ipsec-vti.service 0644

  install -d -m 0755 /usr/local/lib/ipsec-vti-systemd-tunnel
  install -m 0644 "${ROOT_DIR}/scripts/common.sh" /usr/local/lib/ipsec-vti-systemd-tunnel/common.sh

  install -m 0755 "${ROOT_DIR}/tunnel-status.sh" /usr/local/bin/tunnel-status

  systemctl daemon-reload
  systemctl enable ipsec-vti.service >/dev/null
  systemctl start ipsec-vti.service
}

open_ufw_ports_if_needed() {
  if command_exists ufw && ufw status | grep -q "Status: active"; then
    ufw allow 500/udp >/dev/null
    ufw allow 4500/udp >/dev/null
    log "UFW active: UDP/500 and UDP/4500 allowed"
  else
    warn "UFW فعال نیست؛ UDP 500/4500 را در فایروال خود باز کنید."
  fi
}

post_check() {
  systemctl --no-pager --full status ipsec-vti.service || true
  ipsec statusall || true
}

main() {
  require_root
  detect_os_support
  load_env_file "$ENV_FILE"
  validate_env

  log "Installing required packages"
  install_packages

  log "Configuring sysctl"
  configure_sysctl

  log "Writing runtime env"
  write_runtime_env

  log "Rendering IPSec/VTI configs"
  render_configs

  log "Configuring firewall ports"
  open_ufw_ports_if_needed

  log "Installing and starting systemd service"
  install_service

  log "Verification"
  post_check

  log "Installation completed"
}

main "$@"
