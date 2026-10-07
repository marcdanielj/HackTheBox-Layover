# Hack The Box — <BOX NAME>

> **OS:** <Linux/Windows> · **Difficulty:** <Easy/Medium/Hard/Insane> · **Status:** <Retired>
> **Entry point:** `<ip>`

<One-paragraph summary of the box and the overall path.>

| Flag | Value |
|------|-------|
| user | `<hash>` |
| root | `<hash>` |

---

## Attack chain at a glance

```
<ascii diagram of the path: foothold → user → root>
```

---

## 1. Recon
```bash
nmap -p- --min-rate 3000 -T4 <ip>
nmap -sC -sV -p<ports> <ip>
```
<findings>

## 2. Foothold
<how initial access was gained>

## 3. User
<path to the user flag>
```bash
cat user.txt
```

## 4. Privilege escalation → root
<enumeration + the escalation vector (name the CVE/misconfig)>
```bash
cat /root/root.txt
```

---

## Appendix A — Dead ends & lessons
| Rabbit hole | Reality |
|---|---|
| <thing I tried> | <why it didn't work> |

## Appendix B — Tools used
- <tool> — <what for>

## Appendix C — Key takeaways
1. <lesson>

## Credits
- Box: **<BOX NAME>** on [Hack The Box](https://www.hackthebox.com/). Retired; writeup for education/portfolio.
- <exploit attributions, if any>
