#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

ENV_FILE="${1:-${PROJECT_ROOT}/.env}"
TEMPLATES_DIR="${PROJECT_ROOT}/templates"

validate_env() {
  ROLE="${ROLE:-}"
  LOCAL_PUBLIC_IP="${LOCAL_PUBLIC_IP:-}"
  REMOTE_PUBLIC_IP="${REMOTE_PUBLIC_IP:-}"
  LOCAL_ID="${LOCAL_ID:-$LOCAL_PUBLIC_IP}"
  REMOTE_ID="${REMOTE_ID:-$REMOTE_PUBLIC_IP}"
  PSK="${PSK:-}"
  VTI_IF="${VTI_IF:-vti42}"
  VTI_KEY="${VTI_KEY:-42}"
  LOCAL_TUN_IP="${LOCAL_TUN_IP:-}"
  REMOTE_TUN_IP="${REMOTE_TUN_IP:-}"
  LOCAL_LAN_CIDR="${LOCAL_LAN_CIDR:-}"
  REMOTE_LAN_CIDR="${REMOTE_LAN_CIDR:-}"
  FORWARD_RULES="${FORWARD_RULES:-}"
  PUBLIC_IF="${PUBLIC_IF:-}"
  ENABLE_SNAT="${ENABLE_SNAT:-}"

  [[ "$ROLE" == "iran" || "$ROLE" == "foreign" ]] || die "ROLE must be iran or foreign"
  [[ -n "$LOCAL_PUBLIC_IP" ]] || die "LOCAL_PUBLIC_IP is required"
  [[ -n "$REMOTE_PUBLIC_IP" ]] || die "REMOTE_PUBLIC_IP is required"
  [[ -n "$PSK" ]] || die "PSK is required"
  [[ -n "$LOCAL_TUN_IP" ]] || die "LOCAL_TUN_IP is required"
  [[ -n "$REMOTE_TUN_IP" ]] || die "REMOTE_TUN_IP is required"

  if [[ -n "$FORWARD_RULES" && -z "$ENABLE_SNAT" ]]; then
    ENABLE_SNAT="true"
  elif [[ -z "$ENABLE_SNAT" ]]; then
    ENABLE_SNAT="false"
  fi

  if [[ -z "$PUBLIC_IF" ]]; then
    PUBLIC_IF="$(default_route_iface || true)"
  fi

  [[ -n "$PUBLIC_IF" ]] || die "PUBLIC_IF is empty and auto-detect failed"
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y strongswan iproute2 iptables
}

render_ipsec_conf() {
  local tpl="${TEMPLATES_DIR}/ipsec.conf.tpl"
  [[ -f "$tpl" ]] || die "Template missing: $tpl"

  backup_once /etc/ipsec.conf
  sed \
    -e "s|__CONN_NAME__|ipsec-vti-${ROLE}|g" \
    -e "s|__LOCAL_PUBLIC_IP__|${LOCAL_PUBLIC_IP}|g" \
    -e "s|__REMOTE_PUBLIC_IP__|${REMOTE_PUBLIC_IP}|g" \
    -e "s|__LOCAL_ID__|${LOCAL_ID}|g" \
    -e "s|__REMOTE_ID__|${REMOTE_ID}|g" \
    -e "s|__VTI_KEY__|${VTI_KEY}|g" \
    "$tpl" | safe_write_file /etc/ipsec.conf 0644
}

render_ipsec_secrets() {
  local tpl="${TEMPLATES_DIR}/ipsec.secrets.tpl"
  [[ -f "$tpl" ]] || die "Template missing: $tpl"

  backup_once /etc/ipsec.secrets
  sed \
    -e "s|__LOCAL_ID__|${LOCAL_ID}|g" \
    -e "s|__REMOTE_ID__|${REMOTE_ID}|g" \
    -e "s|__PSK__|${PSK}|g" \
    "$tpl" | safe_write_file /etc/ipsec.secrets 0600
}

render_vti_scripts() {
  local up_tpl="${TEMPLATES_DIR}/vti-up.sh.tpl"
  local down_tpl="${TEMPLATES_DIR}/vti-down.sh.tpl"

  [[ -f "$up_tpl" ]] || die "Template missing: $up_tpl"
  [[ -f "$down_tpl" ]] || die "Template missing: $down_tpl"

  ensure_dir /etc/ipsec.d 0755

  sed \
    -e "s|__RUNTIME_ENV__|${RUNTIME_ENV}|g" \
    "$up_tpl" | safe_write_file /etc/ipsec.d/vti-up.sh 0750

  sed \
    -e "s|__RUNTIME_ENV__|${RUNTIME_ENV}|g" \
    "$down_tpl" | safe_write_file /etc/ipsec.d/vti-down.sh 0750

  safe_write_file /etc/ipsec.d/ipsec-vti-updown.sh 0750 <<'UPDOWN'
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
UPDOWN
}

write_runtime_env() {
  ensure_dir "$RUNTIME_DIR" 0700

  quote_env() {
    local val="${1:-}"
    val="${val//\'/\'\"\'\"\'}"
    printf "'%s'" "$val"
  }

  safe_write_file "$RUNTIME_ENV" 0600 <<EOF_RUNTIME
ROLE=$(quote_env "$ROLE")
LOCAL_PUBLIC_IP=$(quote_env "$LOCAL_PUBLIC_IP")
REMOTE_PUBLIC_IP=$(quote_env "$REMOTE_PUBLIC_IP")
VTI_IF=$(quote_env "$VTI_IF")
VTI_KEY=$(quote_env "$VTI_KEY")
LOCAL_TUN_IP=$(quote_env "$LOCAL_TUN_IP")
REMOTE_TUN_IP=$(quote_env "$REMOTE_TUN_IP")
LOCAL_LAN_CIDR=$(quote_env "$LOCAL_LAN_CIDR")
REMOTE_LAN_CIDR=$(quote_env "$REMOTE_LAN_CIDR")
PUBLIC_IF=$(quote_env "$PUBLIC_IF")
ENABLE_SNAT=$(quote_env "$ENABLE_SNAT")
FORWARD_RULES=$(quote_env "$FORWARD_RULES")
EOF_RUNTIME

  safe_write_file "$IPTABLES_ENV" 0600 <<EOF_IPT
VTI_IF=$(quote_env "$VTI_IF")
LOCAL_LAN_CIDR=$(quote_env "$LOCAL_LAN_CIDR")
REMOTE_LAN_CIDR=$(quote_env "$REMOTE_LAN_CIDR")
PUBLIC_IF=$(quote_env "$PUBLIC_IF")
ENABLE_SNAT=$(quote_env "$ENABLE_SNAT")
FORWARD_RULES=$(quote_env "$FORWARD_RULES")
EOF_IPT
}

configure_sysctl() {
  local sysctl_file="/etc/sysctl.d/99-ipsec-vti-autotunnel.conf"
  safe_write_file "$sysctl_file" 0644 <<'EOF_SYSCTL'
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
EOF_SYSCTL
  sysctl --system >/dev/null
}

configure_ufw() {
  if command_exists ufw && ufw status | grep -q "Status: active"; then
    ufw allow 500/udp >/dev/null
    ufw allow 4500/udp >/dev/null
    log "UFW active: UDP 500 and 4500 allowed"
  else
    warn "UFW active نیست؛ مطمئن شوید UDP/500 و UDP/4500 در فایروال/شبکه باز هستند."
  fi
}

install_helpers() {
  ensure_dir /usr/local/lib/ipsec-vti-autotunnel 0755
  install -m 0644 "${SCRIPT_DIR}/common.sh" /usr/local/lib/ipsec-vti-autotunnel/common.sh
  install -m 0755 "${SCRIPT_DIR}/apply-iptables.sh" /usr/local/sbin/ipsec-vti-apply-iptables

  local svc_tpl="${TEMPLATES_DIR}/ipsec-vti-iptables.service.tpl"
  sed -e 's|__APPLY_SCRIPT__|/usr/local/sbin/ipsec-vti-apply-iptables|g' "$svc_tpl" | safe_write_file /etc/systemd/system/ipsec-vti-iptables.service 0644

  systemctl daemon-reload
  systemctl enable ipsec-vti-iptables.service >/dev/null
}

start_services() {
  local swan_service
  swan_service="$(detect_strongswan_service)"

  systemctl enable "$swan_service" >/dev/null
  systemctl restart ipsec-vti-iptables.service
  systemctl restart "$swan_service"

  sleep 2
  ipsec rereadall || true
  ipsec update || true
  ipsec up "ipsec-vti-${ROLE}" || true
}

verify_status() {
  log "strongSwan service: $(detect_strongswan_service)"
  ipsec statusall | sed -n '1,80p' || true

  if ip link show "$VTI_IF" >/dev/null 2>&1; then
    log "VTI interface ${VTI_IF} is present"
  else
    warn "VTI interface ${VTI_IF} not found yet; maybe tunnel not negotiated."
  fi

  if command_exists ping; then
    ping -c 1 -W 2 "$REMOTE_TUN_IP" >/dev/null 2>&1 && log "Ping to ${REMOTE_TUN_IP} ok" || warn "Ping to ${REMOTE_TUN_IP} failed"
  fi
}

main() {
  require_root
  detect_os_support
  load_env_file "$ENV_FILE"
  validate_env

  log "Installing required packages"
  install_packages

  log "Writing runtime configuration"
  write_runtime_env

  log "Rendering strongSwan config"
  render_ipsec_conf
  render_ipsec_secrets
  render_vti_scripts

  log "Applying system networking settings"
  configure_sysctl
  configure_ufw

  log "Installing iptables helper + systemd unit"
  install_helpers

  log "Applying iptables rules"
  /usr/local/sbin/ipsec-vti-apply-iptables "$IPTABLES_ENV"

  log "Starting services"
  start_services

  log "Running basic verification"
  verify_status

  log "Installation completed"
}

main "$@"
