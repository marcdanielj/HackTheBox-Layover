# 🧰 HTB / Pentest Writeups

My personal knowledge base of Hack The Box (and other lab) writeups — part portfolio, part
searchable study notes. Each box gets its own folder with a full walkthrough, the exploit
scripts I used, and a **Dead ends & lessons** section so I don't repeat mistakes.

> ⚠️ Only **retired** HTB machines are written up publicly, per HTB's content policy.

---

## 📦 Boxes

| Box | OS | Difficulty | Status | Key techniques | Writeup |
|-----|----|-----------|--------|----------------|---------|
| **Layover** | Linux | Hard | Retired | xrdp jumpbox · open‑WiFi sniffing · CraftCMS RCE · encrypted‑secret reuse · CUPS root | [→](Layover/README.md) |

<!-- Add new rows at the top. Keep the table sorted newest-first. -->

---

## 🏷️ Techniques & CVE index

A reverse index — "I want to review *X*, which boxes used it?"

| Technique / CVE | Boxes |
|---|---|
| RDP / xrdp enumeration & session pivots | Layover |
| Open Wi‑Fi / cleartext credential sniffing (monitor mode) | Layover |
| CraftCMS element-condition RCE (**CVE‑2026‑28695**) | Layover |
| Reversible app secrets / key reuse (`.env` → decrypt) | Layover |
| CUPS local privesc — root token leak (**CVE‑2026‑34990**) | Layover |
| SSH reverse tunnels / dynamic SOCKS + proxychains pivoting | Layover |
| LXD estate / unprivileged-container recon | Layover |
| Verifying a CVE is patched (`dpkg` + changelog) before exploiting | Layover |

<!-- When you add a box, add its techniques here too (new or existing rows). -->

---

## 🗂️ Repo layout

```
.
├── README.md            ← this index (boxes + techniques)
├── _template/           ← copy this to start a new writeup
│   └── README.md
├── new-box.sh           ← ./new-box.sh "BoxName" scaffolds a new folder
└── <BoxName>/
    ├── README.md        ← the writeup
    ├── exploits/        ← scripts / PoCs used
    └── screenshots/     ← supporting images
```

## ➕ Adding a new box

```bash
./new-box.sh "BoxName"          # creates BoxName/ from the template
# ...write BoxName/README.md, drop scripts in exploits/, images in screenshots/
# then add a row to the two tables above.
```

---

## 🎯 Why this repo exists

I'm building IT/security skills and wanted a single place that is both a **portfolio** (show the
work) and a **study database** (revisit techniques fast). Every writeup follows the same shape:
Recon → Foothold → User → Privesc → **Dead ends & lessons** → Tools → Takeaways.

## ⚖️ Disclaimer

For education and authorized testing only. These target deliberately vulnerable, **retired** lab
machines. Don't point any of this at systems you don't own or have explicit permission to test.
