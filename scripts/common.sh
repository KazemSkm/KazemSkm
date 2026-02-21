#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="ipsec-vti-systemd-tunnel"
RUNTIME_DIR="/etc/${PROJECT_NAME}"
RUNTIME_ENV="${RUNTIME_DIR}/runtime.env"

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
  [[ -f /etc/os-release ]] || die "سیستم‌عامل تشخیص داده نشد (/etc/os-release موجود نیست)."

  # shellcheck disable=SC1091
  source /etc/os-release
  local os_id="${ID:-}"
  local version="${VERSION_ID:-0}"
  local major="${version%%.*}"

  case "$os_id" in
    ubuntu)
      (( major >= 20 )) || die "Ubuntu ${version} پشتیبانی نمی‌شود. حداقل Ubuntu 20.04 لازم است."
      ;;
    debian)
      (( major >= 11 )) || die "Debian ${version} پشتیبانی نمی‌شود. حداقل Debian 11 لازم است."
      ;;
    *)
      die "${os_id:-unknown} پشتیبانی نمی‌شود. فقط Ubuntu 20.04+ و Debian 11+ پشتیبانی می‌شوند."
      ;;
  esac
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

backup_once() {
  local path="$1"
  local backup="${path}.ipsec-vti-systemd-tunnel.bak"
  if [[ -f "$path" && ! -f "$backup" ]]; then
    cp -a "$path" "$backup"
    log "Backup created: $backup"
  fi
}

default_route_iface() {
  ip -o route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}'
}

is_true() {
  case "${1:-}" in
    true|TRUE|1|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

parse_forward_rules() {
  local rules="${1:-}"
  [[ -n "$rules" ]] || return 0
  printf '%s' "$rules" | tr ';' '\n' | sed '/^[[:space:]]*$/d'
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

quote_env() {
  local val="${1:-}"
  val="${val//\'/\'\"\'\"\'}"
  printf "'%s'" "$val"
}

load_env_file() {
  local env_file="$1"
  [[ -f "$env_file" ]] || die "فایل env پیدا نشد: $env_file"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ "$line" == export\ * ]] && line="${line#export }"

    [[ "$line" == *=* ]] || die "خط نامعتبر در env: $line"

    local key="${line%%=*}"
    local value="${line#*=}"

    key="${key%"${key##*[![:space:]]}"}"
    key="${key#"${key%%[![:space:]]*}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "نام متغیر نامعتبر در env: $key"

    if [[ "$value" == \"*\" && "$value" == *\" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
      value="${value:1:${#value}-2}"
    fi

    printf -v "$key" '%s' "$value"
    export "$key"
  done <"$env_file"
}

validate_forward_rules() {
  local rules="${1:-}"
  [[ -z "$rules" ]] && return 0

  while IFS=',' read -r proto in_port dst_ip dst_port; do
    proto="$(echo "$proto" | xargs)"
    in_port="$(echo "$in_port" | xargs)"
    dst_ip="$(echo "$dst_ip" | xargs)"
    dst_port="$(echo "$dst_port" | xargs)"

    [[ "$proto" == "tcp" || "$proto" == "udp" ]] || die "FORWARD_RULES proto باید tcp یا udp باشد."
    [[ "$in_port" =~ ^[0-9]{1,5}$ ]] || die "FORWARD_RULES in_port نامعتبر: $in_port"
    [[ "$dst_port" =~ ^[0-9]{1,5}$ ]] || die "FORWARD_RULES dst_port نامعتبر: $dst_port"
    [[ "$dst_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "FORWARD_RULES dst_ip نامعتبر: $dst_ip"
  done < <(parse_forward_rules "$rules")
}
