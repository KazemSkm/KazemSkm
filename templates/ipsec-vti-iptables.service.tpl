[Unit]
Description=ipsec-vti-autotunnel iptables reapply service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=__APPLY_SCRIPT__ /etc/ipsec-vti-autotunnel/iptables.env
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
