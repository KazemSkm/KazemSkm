config setup
  uniqueids=no
  charondebug="ike 1, knl 1, cfg 0"

conn __CONN_NAME__
  auto=start
  type=tunnel
  keyexchange=ikev2
  authby=psk
  left=__LOCAL_PUBLIC_IP__
  leftid=__LOCAL_ID__
  leftsubnet=0.0.0.0/0
  right=__REMOTE_PUBLIC_IP__
  rightid=__REMOTE_ID__
  rightsubnet=0.0.0.0/0
  ike=aes256-sha256-modp2048!
  esp=aes256-sha256!
  ikelifetime=8h
  lifetime=1h
  rekeymargin=3m
  keyingtries=%forever
  dpdaction=restart
  dpddelay=30s
  dpdtimeout=120s
  compress=no
  forceencaps=yes
  mark=__VTI_KEY__
  vti-interface=%none
  leftupdown=/etc/ipsec.d/ipsec-vti-updown.sh
  installpolicy=yes
