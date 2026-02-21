[Unit]
Description=IPSec VTI tunnel managed by systemd
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/sbin/ipsec start --nofork
ExecStartPost=/usr/sbin/ipsec up __CONN_NAME__
ExecStop=/usr/sbin/ipsec stop
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
