---
name: ad-redirect-resolver
description: "Resolve ANY cloaked ad-redirect URL to its real final destination, given ONLY the URL — no other guidance ever needed. Target URLs look like https://<domain>/4/<40-char-hash> (ads easy / adsh / 'new tari' / NRE-Systems broker families, seen on auctionr.org, asiafilm.org, etc.). Front door blocks on IP reputation: datacenter/unknown IPs get an instant 'Anonymous Proxy detected.' wall BEFORE any session/token check. Behind it, an anti-fraud portal page (Cloudflare-protected, nearly empty: 1 tracking pixel from static.nresystems.com + a hidden form) builds session tokens (fstu, ps1, rmtc, sht, shv, st1, uuid) inside an embedded URL-encoded JSON config in the page's inline JS; resubmitting the SAME URL with those tokens in the query + step-1 cookies + step-1 referer through the SAME residential IP returns a 302 to an ad-broker hop (e.g. madridkings.shop/click), which serves a 'Redirecting...' page whose meta-refresh hides the REAL target base64-encoded in a d= URL parameter, often itself a JSON {'URL': ...}. This skill finds a live residential proxy automatically, replays the full session faithfully with an authentic Chrome TLS fingerprint (curl-impersonate), peels every redirect layer (302s, meta-refresh, base64) and reports the true final page (title, description, destination, ref hosts). Use when the user gives an ad/cloaked/redirect link and wants to SEE what is really behind it, when they say 'voir le contenu derrière l'url', 'what redirect is behind this link', or hand over a domain/4/<hash> style URL. Absolute requirement history: tokens/cookies/referer/IP must be coherent IN ONE SESSION — reusing tokens from a previous session or switching IP mid-chain yields 403s in a chain. The winning proxy dies fast; the scripts re-hunt a fresh one on every run."
version: 1.0.0
author: buffy
tags: [url, redirect, cloaking, ads, anti-fraud, proxy, cloudflare, token, curl-impersonate, aliexpress, investigation]
---

# Ad-Redirect Resolver

Given **only** an URL such as:

```
https://asiafilm.org/4/109ea1a274ecc2b6970ed6d804c0bd15
```

produce the REAL content behind it. No other input from the user is ever
needed. This skill was proven end-to-end the day it was written (the URL
above → AliExpress-affiliate landing, details in "Proven chain" below).

## The architecture you are facing (know this first)

A cloaked ad chain has 3 walls, and agents fail on a DIFFERENT one each time:

1. **IP wall (before everything):** The gate answers ANY request from a
   datacenter/unknown-problem IP with a 200-OK page containing literally
   `<p>Anonymous Proxy detected.</p>` and nothing else. This is NOT about
   tokens, fingerprints or headers — no amount of header tuning fixes it.
   Only a residential-class exit IP passes. Proxies die daily; there is no
   list to copy: hunt afresh every run (the scripts do it).
2. **Session wall:** the first successful GET returns the "portal": a
   6–7 KB page with 1 tracking pixel (`static.nresystems.com/img.gif?uuid=…`)
   and an inline script that builds a hidden form. The tokens live INSIDE
   the page as a URL-encoded JSON: `a='%7B%22reverse…'`, `JSON.parse(decode…`
   The form's `values` are the session keys (`fstu` `ps1` `rmtc` `sht` `shv`
   `st1` `uuid` `pii`). A `e:false` flag means submission is a plain GET:
   `action?token=…&token=…` (plus browser screen fields `sw2…sw7/sh2…sh7/fr`
   that the JS fabricates — fake plausible ones: 1920×1080 etc.).
   **Coherence law:** tokens + cookies (`uidm`, `ain`, `__cf_bm`, `by`) +
   referer (the step-1 URL) + the SAME exit IP through the WHOLE chain.
   Break any of these → 403/rejection.
3. **Cloak wall:** even after the 302 you land on broker hops
   (e.g. `madridkings.shop/click?…`) that serve a "Redirecting…" page whose
   real target is hidden in `meta http-equiv="REFRESH" content="0;
   url=...?d=<base64>"`, where the base64 often decodes to
   `{"URL":"https://s.click.aliexpress.com/e/_c3cT5fqt?dp=…","InstallId":3725}`.
   Then AliExpress (or the final site) does 2 more 302s. Nothing ends where
   the 302 points — you must decode and follow.

## How to run it (everything is automated)

The scripts live next to this SKILL.md. One command does the whole job:

```bash
cp -r <skill_dir>/scripts /tmp/ad-resolver && cd /tmp/ad-resolver
bash resolve.sh "https://asiafilm.org/4/109ea1a274ecc2b6970ed6d804c0bd15"
```

What `resolve.sh` does, in order:

1. `curlchrome.sh` → one honest Chrome-116 GET. If it passes (rare),
   done — no proxy needed.
2. Otherwise downloads fresh proxy lists (monosans project, TheSpeedX
   fallback) and hunts in parallel (`xargs -P 40`) with `testproxy.sh`:
   a *winner* is any proxy answering with REAL html that is NOT
   "Anonymous Proxy detected". Typical stats on a fresh day: ~7 000
   candidates → ~70 winners. sock5 ones are preferred (remote DNS).
3. Step 1 on the winning proxy with the Chrome impersonation →
   portal + cookies (`jar.txt`).
4. `chain.py` extracts the embedded JSON config and prints the query
   string: screen fields + tokens, shuffled key order like the real JS.
5. Step 2: same URL + `?query`, `Referer:` = step-1 URL, same cookie jar,
   `-L`. Follows to the broker hop; `decode_meta_b64` peels the
   meta-refresh/base64 layer and follows that too (up to 6 hops).
6. Prints the REPORT: final URL, http code, page title, description,
   ref-hosts. Final HTML also saved to `/tmp/redirect-resolver-final.html`.

Exit codes: `0` resolved, `2` no live proxy found or no proxy list (rerun
later / fetch more lists), `1` unexpected chain failure (report says what).

## Prerequisite and known broken tools

- Requires the binary `curl-impersonate-chrome` (TLS JA3/JA4 + http2
  chrome fingerprint). Check: `command -v curl-impersonate-chrome`.
- **DO NOT use the shipped wrapper `/usr/bin/curl_chrome116`** on systems
  where it is preinstalled with a corrupted exec line
  (`exec "$dir(/curl-impersonate-chrome"`), and on that build `--ciphers`
  isn't supported either. The skill ships its own fixed wrapper
  `curlchrome.sh` (same headers, no `--ciphers`). If
  `curl-impersonate-chrome` is missing entirely, install from the
  curl-impersonate GitHub release, or fall back to plain `curl` and accept
  a lower pass rate at the front door.
- Plain `curl` (no impersonation) DOES pass the session wall on some
  residential IPs; if `curlchrome.sh` fails on step 1/2 only, try plain
  curl with the same headers before declaring the proxy dead. If it fails
  consistently at the front door, keep hunting: front-door failure is IP
  reputation, NOT fingerprint, on this gate.

## Debugging table (each symptom → unique cause)

| symptom | cause | fix |
|---|---|---|
| body = `<p>Anonymous Proxy detected.</p>` | datacenter IP | hunt another proxy; never hand-tune headers for this |
| step 1 timeout on winning proxy | proxy died mid-run | retry `resolve.sh` (new proxy chosen every run) |
| step 2 → 403 in a chain | tokens reused from earlier session / cookies not carried / IP changed mid-chain | always one fresh session: step 1→2 on same proxy + jar + referer |
| tokens_query prints nothing | portal page different variant | open portal.html, look for `a='…'JSON.parse(decodeURIComponent` extract; adapt regex in chain.py |
| final hop is "Redirection..." page | meta-refresh not decoded | decode_meta_b64 handles `d=` base64 (URL-safe, fix padding `+= '=' * (-len % 4)`) |
| AliExpress landing but want the actual product | generic `aff-third-party-landing` (CPS commission page, not a product) | report as-is: that IS the real destination |

## Proven chain (as delivered)

```
asiafilm.org/4/109ea1a…            (datacenter IP: "Anonymous Proxy detected.")
  └─ socks5h 183.106.215.208:1080 (residential, Korea Telecom, KT block)
       ├─ GET /4/109ea1a…         -> portal, cookies uidm/ain/__cf_bm/by,
       │                             tokens in page: fstu=01a17e28-…, ps1=…,
       │                             sht=…, shv=2, st1=1793117921…
       ├─ GET /4/109ea1a…?sw2=1920&sh2=1080&…&fstu=…&ps1=…&sht=…&shv=2
       │    -H "Referer: https://asiafilm.org/4/109ea1a…"
       │    -> 302 https://madridkings.shop/click?trvid=14760&extid=…
       │            &var1=31949992&var2=<proxyIP>&var4=Chrome
       │            (broker LOGS our exit IP — expect that in their logs)
       ├─ 200 madridkings.shop "Redirecting…" page
       │     meta refresh d=<base64> -> {"URL":"https://s.click.aliexpress.com
       │            /e/_c3cT5fqt?dp=aRxatKm9OZhl&af=…","InstallId":3725}
       └─ FINAL: https://www.aliexpress.com/s/aff-third-party-landing/…
             tt=CPS_NORMAL (affiliate-commission landing page, not a product)
```

Older link of the same family resolved to `vidox.net` — fake video-site
lander ("Videos being watched", fake 04:12 player, yandex-metrika pixel).
Same family, DIFFERENT final destination — never assume the destination,
always peel to the end.

## Ethics / scope

- The user provides the URL; the goal is INSPECTION only: reading what is
  behind a redirect they were given.
- Never execute, never interact, never click, never download executables
  from the resolved page. Read-only, GET-only, no beacons replayed.
- The chain-dependent tracker pixels and sendsBeacons are left unfired;
  only GET requests are sent. The ad-broker sees one click-worth of GET
  navigations — exactly what a user visiting the link produces.
