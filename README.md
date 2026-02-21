# ipsec-vti-autotunnel

ابزار اتوماتیک برای راه‌اندازی تونل Site-to-Site IPSec (IKEv2 + strongSwan) به‌صورت Route-Based با VTI روی Linux.

هدف: نصب سریع، تکرارپذیر (idempotent)، قابل حذف، و مناسب Ubuntu 20.04+ / Debian 11+.

## ویژگی‌ها
- استفاده از `strongSwan` با `ipsec.conf` و `ipsec.secrets`
- VTI route-based با `VTI_IF` (پیش‌فرض `vti42`) و `VTI_KEY` (پیش‌فرض `42`)
- نصب آسان با `.env` + `sudo ./install.sh`
- بالا آمدن خودکار در بوت (systemd + strongSwan)
- پشتیبانی از NAT Traversal (UDP 500/4500)
- پشتیبانی اختیاری از route بین LANهای دو سمت
- پشتیبانی اختیاری از Port Forwarding روی تونل (DNAT/FORWARD/SNAT)
- حذف کامل با `sudo ./uninstall.sh`
- ابزار عیب‌یابی با `sudo ./diagnose.sh`

## ساختار پروژه
- `README.md`
- `examples/iran.env.example`
- `examples/foreign.env.example`
- `scripts/common.sh`
- `scripts/install.sh`
- `scripts/uninstall.sh`
- `scripts/diagnose.sh`
- `scripts/apply-iptables.sh`
- `templates/ipsec.conf.tpl`
- `templates/ipsec.secrets.tpl`
- `templates/vti-up.sh.tpl`
- `templates/vti-down.sh.tpl`
- `templates/ipsec-vti-iptables.service.tpl`
- `.github/workflows/lint.yml`

## پیش‌نیاز
- دسترسی root یا sudo
- هر دو سرور باید public IP قابل دسترس داشته باشند (یا حداقل NAT-T قابل عبور)
- UDP `500` و `4500` در فایروال/شبکه باز باشد

## متغیرهای `.env`
فایل `.env` را کنار `install.sh` بسازید.

الزامی:
- `ROLE=iran|foreign`
- `LOCAL_PUBLIC_IP=`
- `REMOTE_PUBLIC_IP=`
- `PSK=`
- `LOCAL_TUN_IP=` (برای ایران معمولاً `10.255.255.1/30`)
- `REMOTE_TUN_IP=` (برای ایران معمولاً `10.255.255.2`)

اختیاری:
- `LOCAL_ID=` (پیش‌فرض: `LOCAL_PUBLIC_IP`)
- `REMOTE_ID=` (پیش‌فرض: `REMOTE_PUBLIC_IP`)
- `VTI_IF=` (پیش‌فرض `vti42`)
- `VTI_KEY=` (پیش‌فرض `42`)
- `LOCAL_LAN_CIDR=`
- `REMOTE_LAN_CIDR=`
- `FORWARD_RULES=`
- `PUBLIC_IF=` (اگر خالی باشد، auto-detect)
- `ENABLE_SNAT=true|false` (اگر `FORWARD_RULES` ست شده باشد و این مقدار خالی باشد، پیش‌فرض `true`)

فرمت `FORWARD_RULES`:
- `FORWARD_RULES="tcp,443,10.20.0.10,443;tcp,80,10.20.0.10,80"`

## Quickstart (هر دو سمت)

### 1) روی سرور ایران
```bash
git clone <YOUR_REPO_URL> ipsec-vti-autotunnel
cd ipsec-vti-autotunnel
cp examples/iran.env.example .env
# فایل .env را ویرایش کنید
sudo ./install.sh
```

### 2) روی سرور خارجی
```bash
git clone <YOUR_REPO_URL> ipsec-vti-autotunnel
cd ipsec-vti-autotunnel
cp examples/foreign.env.example .env
# فایل .env را ویرایش کنید
sudo ./install.sh
```

### 3) بررسی وضعیت
```bash
sudo ./diagnose.sh
```

## مثال حداقلی (فقط تونل)
سمت ایران:
```env
ROLE=iran
LOCAL_PUBLIC_IP=203.0.113.10
REMOTE_PUBLIC_IP=198.51.100.20
PSK=use-a-long-random-string
LOCAL_TUN_IP=10.255.255.1/30
REMOTE_TUN_IP=10.255.255.2
```

سمت خارجی:
```env
ROLE=foreign
LOCAL_PUBLIC_IP=198.51.100.20
REMOTE_PUBLIC_IP=203.0.113.10
PSK=use-a-long-random-string
LOCAL_TUN_IP=10.255.255.2/30
REMOTE_TUN_IP=10.255.255.1
```

## مثال route بین LANها
ایران:
```env
LOCAL_LAN_CIDR=10.10.0.0/24
REMOTE_LAN_CIDR=10.20.0.0/24
```

خارجی (برعکس):
```env
LOCAL_LAN_CIDR=10.20.0.0/24
REMOTE_LAN_CIDR=10.10.0.0/24
```

## مثال Port Forwarding روی تونل
فرض: روی سرور ایران می‌خواهیم پورت 443 عمومی به `10.20.0.10:443` در سمت خارجی ارسال شود:

```env
FORWARD_RULES=tcp,443,10.20.0.10,443
ENABLE_SNAT=true
```

مثال چند قانون:
```env
FORWARD_RULES=tcp,443,10.20.0.10,443;tcp,80,10.20.0.10,80
ENABLE_SNAT=true
```

## دستورات روزمره
نصب:
```bash
sudo ./install.sh
```

حذف:
```bash
sudo ./uninstall.sh
```

تشخیص مشکل:
```bash
sudo ./diagnose.sh
```

## رفتار idempotent
- اجرای چندباره `install.sh` باعث تکرار قوانین iptables نمی‌شود.
- فایل‌های حساس قبل از جایگزینی backup می‌شوند:
  - `/etc/ipsec.conf.ipsec-vti-autotunnel.bak`
  - `/etc/ipsec.secrets.ipsec-vti-autotunnel.bak`
- uninstall فقط artefactهای ساخته‌شده توسط همین پروژه را حذف می‌کند.

## نکات امنیتی
- فایل `.env` را commit نکنید (`PSK` محرمانه است).
- از PSK طولانی و تصادفی استفاده کنید.
- PSK را دوره‌ای rotate کنید.
- دسترسی SSH را محدود کنید (کلید SSH، allowlist IP، Fail2ban، پورت/Policy مناسب).
- لاگ‌ها را بررسی کنید و در صورت نیاز `LOCAL_ID/REMOTE_ID` را دقیق تنظیم کنید.

## Troubleshooting
1. اگر تونل بالا نمی‌آید:
- `sudo ./diagnose.sh`
- چک کنید UDP 500/4500 در مسیر شبکه باز باشد.
- چک کنید `PSK`, `LOCAL_ID`, `REMOTE_ID` در هر دو طرف match باشند.

2. اگر پکت‌ها از تونل عبور نمی‌کنند:
- مقدار `rp_filter` باید `0` باشد.
- route مربوط به `REMOTE_LAN_CIDR` باید روی VTI ثبت شده باشد.
- MTU را کمتر تست کنید (مثلاً `1400`).

3. اگر Port Forwarding کار نمی‌کند:
- `FORWARD_RULES` را بررسی کنید (فرمت CSV صحیح باشد).
- `PUBLIC_IF` درست باشد (یا auto-detect درست انجام شده باشد).
- در صورت مشکل مسیر برگشت، `ENABLE_SNAT=true` بگذارید.

## فرض‌های طراحی
- این ابزار برای سناریوی دو سرور Linux (iran/foreign) و strongSwan starter نوشته شده است.
- backend فایروال روی iptables در نظر گرفته شده است.
- برای پایداری قوانین فایروال پس از reboot از سرویس systemd اختصاصی استفاده شده (به‌جای iptables-persistent).
