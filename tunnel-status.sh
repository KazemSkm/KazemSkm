#!/usr/bin/env bash
set -euo pipefail

print_section() {
  printf '\n-----------------------------------\n%s\n-----------------------------------\n' "$1"
}

print_section "Systemd status"
systemctl status ipsec-vti --no-pager || true

print_section "IPSec status"
ipsec statusall || true

print_section "VTI Interface"
ip a show vti42 || true

print_section "Routes"
ip route || true

print_section "Firewall rules"
iptables -t nat -L -n -v || true
iptables -L -n -v || true
