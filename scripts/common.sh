#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="ipsec-vti-autotunnel"
RUNTIME_DIR="/etc/${PROJECT_NAME}"
RUNTIME_ENV="${RUNTIME_DIR}/runtime.env"
IPTABLES_ENV="${RUNTIME_DIR}/iptables.env"

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

error() {
  printf '[ERROR] %s\n' "$*" >&2
}

die() {
  error "$*"
  exit 1
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "این اسکریپت باید با sudo/root اجرا شود."
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

detect_os_support() {
  if [[ ! -f /etc/os-release ]]; then
    die "فایل /etc/os-release پیدا نشد؛ سیستم‌عامل پشتیبانی‌شده نیست."
  fi

  # shellcheck disable=SC1091
  source /etc/os-release
  local os_id="${ID:-}"
  local version="${VERSION_ID:-0}"
  local major="${version%%.*}"

  case "$os_id" in
    ubuntu)
      if (( major < 20 )); then
        die "Ubuntu ${version} پشتیبانی نمی‌شود. حداقل Ubuntu 20.04 لازم است."
      fi
      ;;
    debian)
      if (( major < 11 )); then
        die "Debian ${version} پشتیبانی نمی‌شود. حداقل Debian 11 لازم است."
      fi
      ;;
    *)
      die "سیستم‌عامل ${os_id:-unknown} پشتیبانی نمی‌شود. فقط Ubuntu 20.04+ و Debian 11+ پشتیبانی می‌شوند."
      ;;
  esac
}

load_env_file() {
  local env_file="$1"
  [[ -f "$env_file" ]] || die "فایل env پیدا نشد: $env_file"

  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
}

ensure_dir() {
  local dir="$1"
  local mode="$2"
  install -d -m "$mode" "$dir"
}

backup_once() {
  local path="$1"
  local backup="${path}.ipsec-vti-autotunnel.bak"
  if [[ -f "$path" && ! -f "$backup" ]]; then
    cp -a "$path" "$backup"
    log "Backup created: $backup"
  fi
}

safe_write_file() {
  local target="$1"
  local mode="$2"
  local owner_group="${3:-root:root}"
  local tmp

  tmp="$(mktemp)"
  cat >"$tmp"
  install -m "$mode" -o "${owner_group%%:*}" -g "${owner_group##*:}" "$tmp" "$target"
  rm -f "$tmp"
}

ensure_sysctl_setting() {
  local key="$1"
  local value="$2"
  local file="$3"

  if grep -qE "^${key}=" "$file" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >>"$file"
  fi
}

default_route_iface() {
  ip -o route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}'
}

ensure_iptables_rule() {
  local table="$1"
  local chain="$2"
  shift 2

  if ! iptables -t "$table" -C "$chain" "$@" >/dev/null 2>&1; then
    iptables -t "$table" -A "$chain" "$@"
  fi
}

remove_iptables_rule() {
  local table="$1"
  local chain="$2"
  shift 2

  while iptables -t "$table" -C "$chain" "$@" >/dev/null 2>&1; do
    iptables -t "$table" -D "$chain" "$@"
  done
}

parse_forward_rules() {
  local rules="$1"
  [[ -n "$rules" ]] || return 0
  printf '%s' "$rules" | tr ';' '\n' | sed '/^[[:space:]]*$/d'
}

is_true() {
  local v="${1:-}"
  [[ "$v" == "1" || "$v" == "true" || "$v" == "TRUE" || "$v" == "yes" || "$v" == "on" ]]
}

detect_strongswan_service() {
  if systemctl list-unit-files | awk '{print $1}' | grep -qx 'strongswan-starter.service'; then
    printf 'strongswan-starter.service\n'
    return
  fi

  if systemctl list-unit-files | awk '{print $1}' | grep -qx 'strongswan.service'; then
    printf 'strongswan.service\n'
    return
  fi

  printf 'strongswan-starter.service\n'
}
