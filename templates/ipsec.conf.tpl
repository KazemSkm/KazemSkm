config setup
  uniqueids=no

conn __CONN_NAME__
  auto=start
  type=tunnel
  keyexchange=ikev2
  authby=psk
  left=__LOCAL_PUBLIC_IP__
  leftid=__LOCAL_PUBLIC_IP__
  leftsubnet=0.0.0.0/0
  right=__REMOTE_PUBLIC_IP__
  rightid=__REMOTE_PUBLIC_IP__
  rightsubnet=0.0.0.0/0
  ike=aes256-sha256-modp2048!
  esp=aes256-sha256!
  ikelifetime=8h
  lifetime=1h
  dpdaction=restart
  dpddelay=30s
  dpdtimeout=120s
  keyingtries=%forever
  mark=42
  forceencaps=yes
  leftupdown=/etc/ipsec.d/ipsec-vti-updown.sh
