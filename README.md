# ipsec-vti-systemd-tunnel

راه‌اندازی خودکار تونل Site-to-Site IPSec با strongSwan (IKEv2) و VTI route-based، کاملاً مدیریت‌شده با systemd.

## قابلیت‌ها
- پشتیبانی Ubuntu 20.04+ و Debian 11+
- اجرای خودکار روی boot با `systemd`
- بازیابی خودکار سرویس در crash (`Restart=always`)
- ساخت/حذف داینامیک `vti42`
- پشتیبانی اختیاری از route بین LAN دو طرف
- پشتیبانی اختیاری از Port Forwarding
- دستور آماده `tunnel-status` برای عیب‌یابی سریع

## ساختار پروژه
- `README.md`
- `.env.example`
- `install.sh`
- `uninstall.sh`
- `tunnel-status.sh`
- `scripts/common.sh`
- `templates/ipsec.conf.tpl`
- `templates/ipsec.secrets.tpl`
- `templates/vti-up.sh.tpl`
- `templates/vti-down.sh.tpl`
- `templates/ipsec-vti.service.tpl`

## نصب سریع

### سمت ایران
```bash
git clone <REPO_URL> ipsec-vti-systemd-tunnel
cd ipsec-vti-systemd-tunnel
cp .env.example .env
# ویرایش .env
sudo ./install.sh
```

### سمت خارجی
```bash
git clone <REPO_URL> ipsec-vti-systemd-tunnel
cd ipsec-vti-systemd-tunnel
cp .env.example .env
# ویرایش .env با مقادیر معکوس ایران/خارج
sudo ./install.sh
```

## متغیرهای `.env`
- `ROLE=iran|foreign`
- `LOCAL_PUBLIC_IP=`
- `REMOTE_PUBLIC_IP=`
- `PSK=`
- `LOCAL_TUN_IP=`
- `REMOTE_TUN_IP=`
- `LOCAL_LAN_CIDR=` (اختیاری)
- `REMOTE_LAN_CIDR=` (اختیاری)
- `FORWARD_RULES=` (اختیاری)
- `ENABLE_SNAT=true|false` (اختیاری)
- `PUBLIC_IF=` (اختیاری، در صورت خالی بودن auto-detect)

نکته: اگر PSK شامل کاراکترهای خاص است، داخل `'` یا `"` قرار دهید.

## مثال حداقلی
ایران:
```env
ROLE=iran
LOCAL_PUBLIC_IP=203.0.113.10
REMOTE_PUBLIC_IP=198.51.100.20
PSK='LongRandomPSK...'
LOCAL_TUN_IP=10.255.255.1/30
REMOTE_TUN_IP=10.255.255.2
```

خارجی:
```env
ROLE=foreign
LOCAL_PUBLIC_IP=198.51.100.20
REMOTE_PUBLIC_IP=203.0.113.10
PSK='LongRandomPSK...'
LOCAL_TUN_IP=10.255.255.2/30
REMOTE_TUN_IP=10.255.255.1
```

## مثال LAN Routing
ایران:
```env
LOCAL_LAN_CIDR=10.10.0.0/24
REMOTE_LAN_CIDR=10.20.0.0/24
```

خارجی:
```env
LOCAL_LAN_CIDR=10.20.0.0/24
REMOTE_LAN_CIDR=10.10.0.0/24
```

## مثال Port Forward
```env
FORWARD_RULES="tcp,443,10.20.0.10,443;tcp,80,10.20.0.10,80"
ENABLE_SNAT=true
PUBLIC_IF=eth0
```

## دستور وضعیت
پس از نصب:
```bash
tunnel-status
```

این دستور خروجی‌های زیر را نشان می‌دهد:
- `systemctl status ipsec-vti --no-pager`
- `ipsec statusall`
- `ip a show vti42`
- `ip route`
- `iptables -t nat -L -n -v` و `iptables -L -n -v`

## حذف
```bash
sudo ./uninstall.sh
```

## Troubleshooting
1. UDP 500 و UDP 4500 در دو طرف باید باز باشد.
2. مقادیر `PSK`، `LOCAL_PUBLIC_IP` و `REMOTE_PUBLIC_IP` در هر دو سمت باید هماهنگ باشند.
3. اگر route برقرار نیست، `LOCAL_LAN_CIDR` و `REMOTE_LAN_CIDR` را بررسی کنید.
4. اگر forwarding مشکل دارد، `PUBLIC_IF` و فرمت `FORWARD_RULES` را چک کنید.
5. وضعیت کامل را با `tunnel-status` ببینید.

## توصیه‌های امنیتی
- PSK را هرگز commit نکنید.
- از PSK طولانی و تصادفی استفاده کنید.
- دسترسی SSH را محدود کنید.
- PSK را دوره‌ای rotate کنید.
- لاگ‌ها را منظم بررسی کنید.

## فرض‌های اجرایی
- پشتیبانی best-effort فقط روی Ubuntu 20.04+ و Debian 11+.
- backend فایروال مبتنی بر iptables در نظر گرفته شده است.
- سرویس systemd اختصاصی `ipsec-vti.service` مدیریت lifecycle تونل را انجام می‌دهد.
