# Manual NikkiOpen installation

[English](MANUAL_INSTALL.md) | [Русский](MANUAL_INSTALL.ru.md)

This guide installs official packages from
[lanetsky/nikkiopen](https://github.com/lanetsky/nikkiopen) without running
NikkiGo or another installation script.

> Back up the router first and keep the SSH session open. A broken proxy or
> DNS configuration can interrupt internet access for the LAN.

## 1. Check the router

```sh
cat /etc/openwrt_release
uname -r
uname -m
test -x /sbin/fw4 && echo "firewall4: OK"
command -v apk || command -v opkg
```

Use a supported OpenWrt release, Linux kernel 5.13 or newer, and `firewall4`.

## 2. Back up the current state

```sh
mkdir -p /root/nikki-backup
cp -p /etc/config/nikki /root/nikki-backup/ 2>/dev/null || true
cp -Rp /etc/nikki/subscriptions /root/nikki-backup/ 2>/dev/null || true
/etc/init.d/nikki stop 2>/dev/null || true
```

## 3. Download official packages

Open the
[lanetsky/nikkiopen releases](https://github.com/lanetsky/nikkiopen/releases)
page and download the archive matching both the OpenWrt release and router
architecture. Copy it to `/tmp` on the router, then extract it:

```sh
mkdir -p /tmp/nikki-manual
tar -xzf /tmp/nikki_*.tar.gz -C /tmp/nikki-manual
cd /tmp/nikki-manual
```

Never install an archive built for another architecture or OpenWrt release.

## 4. Install packages

For `apk`:

```sh
apk update
apk add --allow-untrusted ./nikki-*.apk ./luci-app-nikki-*.apk
apk add --allow-untrusted ./luci-i18n-nikki-ru-*.apk
```

For `opkg`:

```sh
opkg update
opkg install ./nikki_*.ipk ./luci-app-nikki_*.ipk
opkg install ./luci-i18n-nikki-ru_*.ipk
```

Register the LuCI backend without rebooting:

```sh
rm -f /tmp/luci-indexcache
/etc/init.d/rpcd restart
/etc/init.d/uhttpd reload
ubus -S list luci.nikki
```

## 5. Add the subscription

Open:

```text
http://ROUTER_ADDRESS/cgi-bin/luci/admin/services/nikki
```

Create a subscription in the profiles/subscriptions page:

- choose a descriptive name;
- paste the provider URL;
- set User-Agent to `Clash.Meta`;
- prefer the remote version.

Do not publish the subscription URL. Select it as the active profile and
enable profile validation.

## 6. Start without interception

```sh
uci set nikki.proxy.enabled='0'
uci set nikki.config.enabled='1'
uci commit nikki
/etc/init.d/nikki enable
/etc/init.d/nikki restart
sleep 3
/etc/init.d/nikki running
tail -n 30 /var/log/nikki/app.log
tail -n 30 /var/log/nikki/core.log
```

Confirm that profile validation and core startup succeeded.

## 7. Zashboard

Use the official [Zephyruso/zashboard](https://github.com/Zephyruso/zashboard)
archive referenced by `external-ui-url`. Extract it to a temporary directory
and locate the real `index.html`:

```sh
mkdir -p /tmp/zashboard-unpack
unzip -q /tmp/dist-cdn-fonts.zip -d /tmp/zashboard-unpack
find /tmp/zashboard-unpack -name index.html
```

If it is under `dist/`, copy the contents of `dist`, not the directory itself:

```sh
mkdir -p /etc/nikki/run/ui
cp -Rp /tmp/zashboard-unpack/dist/. /etc/nikki/run/ui/
test -f /etc/nikki/run/ui/index.html
```

If `index.html` is at the archive root, copy that root instead. Perform this
after Nikki creates `/etc/nikki/run`, because the run directory may be
recreated.

## 8. Enable interception and test

```sh
uci set nikki.proxy.enabled='1'
uci commit nikki
/etc/init.d/nikki restart
sleep 3
/etc/init.d/nikki running
nslookup example.com
curl -fsS --max-time 10 -o /dev/null https://www.gstatic.com/generate_204
```

Repeat the checks several times. A successful subscription download does not
prove that its proxy route works.

If DNS or HTTPS fails, immediately restore normal internet access:

```sh
/etc/init.d/nikki stop
uci set nikki.config.enabled='0'
uci commit nikki
```

Do not disable the firewall or reboot the router.

## 9. Update a subscription manually

```sh
uci show nikki | grep '=subscription'
/etc/init.d/nikki update_subscription SECTION_ID
uci -q get nikki.SECTION_ID.success
```

The value `1` confirms only download and formal validation. Repeat the
service, DNS, and HTTPS checks after applying it.

## 10. Removal

Use the official
[uninstall.sh](https://github.com/lanetsky/nikkiopen/blob/main/uninstall.sh)
or remove the installed packages using `apk`/`opkg`. Stop and disable Nikki
first:

```sh
/etc/init.d/nikki stop
/etc/init.d/nikki disable
rm -rf /tmp/nikki-manual /tmp/zashboard-unpack
```
