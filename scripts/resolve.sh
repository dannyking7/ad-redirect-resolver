#!/usr/bin/env bash
# resolve.sh — give it ONLY the cloaked ad URL, it prints the REAL destination.
#   Usage:  bash resolve.sh https://some-domain/4/1a2b3c4d5e...
#   Exit 0 = resolved.  Exit 2 = no usable proxy / chain dead (retry later).
set -uo pipefail

URL="${1:?Usage: resolve.sh <url>}"
MAX_HOPS=8
PROXY_TRIES=10
WORK="$(mktemp -d /tmp/redirect-resolver.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"

die()  { echo "ERROR: $*" >&2; exit "${2:-1}"; }
log()  { echo "[$(date +%H:%M:%S)] $*"; }
is_portal()   { grep -q "JSON.parse(decodeURIComponent" "$1" 2>/dev/null; }
is_ipwall()   { grep -q "Anonymous Proxy detected" "$1" 2>/dev/null; }

report() {
  echo
  echo "================= REPORT ================="
  echo "original URL : $URL"
  echo "proxy used   : ${PROXY:-direct}"
  echo "final URL    : $(sed -n 1p hop.txt | tr -d '\r')"
  echo "http code    : $(sed -n 2p hop.txt | tr -d '\r')"
  echo "extra decode : ${EXTRA_URL:-none}"
  python3 - body.html <<'PYEOF'
import re, sys, html
raw = open(sys.argv[1], encoding='utf-8', errors='ignore').read()
t = re.search(r'<title[^>]*>(.*?)</title>', raw, re.S | re.I)
print("page title   :", html.unescape(t.group(1)).strip()[:120] if t else "(none)")
d = re.search(r'<meta[^>]+description[^>]+content="([^"]{0,300})"', raw, re.I)
print("description  :", html.unescape(d.group(1)).strip()[:200] if d else "(none)")
hosts = []
for h in re.findall(r'https?://([^/"\s]+)', raw):
    if h not in hosts: hosts.append(h)
for h in hosts[:8]: print("ref host     :", h)
PYEOF
  echo "final html   : /tmp/redirect-resolver-final.html"
  echo "work session : $WORK (kept on error, removed on clean exit)"
  cp body.html /tmp/redirect-resolver-final.html 2>/dev/null
}
report_on_error() { cp body.html /tmp/redirect-resolver-final.html 2>/dev/null || true; }
trap 'report_on_error' ERR
trap 'rm -rf "$WORK"' EXIT

decode_meta_b64() {
  python3 - "$1" <<'PYEOF'
import base64, json, re, sys, urllib.parse
raw = open(sys.argv[1], encoding='utf-8', errors='ignore').read()
for m in re.finditer(r'url=([^">]+)', raw):
    url = m.group(1)
    if not url.startswith('http'): continue
    qs = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)
    b64 = qs.get('d', [None])[0]
    if b64:
        b64 += '=' * (-len(b64) % 4)
        try:
            cfg = json.loads(base64.urlsafe_b64decode(b64).decode())
            if isinstance(cfg, dict) and cfg.get('URL'):
                print(cfg['URL']); sys.exit(0)
        except Exception:
            pass
    print(url); sys.exit(0)
PYEOF
}

tokens_query() { python3 ./chain.py portal.html 2>/dev/null; }

# full hop: -L redirects, output body.html + hop.txt ("url\ncode")
do_hop() { # $1 target, $2 referer
  ./curlchrome.sh -x "$PROXY" -c jar.txt -b jar.txt \
    -H "Referer: $2" -H 'Sec-Fetch-Site: same-origin' \
    -L -o body.html -D hop.h -w '%{url_effective}\n%{http_code}\n' \
    --max-time 45 "$1" 2>/dev/null > hop.txt
}

# ---------------- step 0: honest attempt without proxy ----------------------
cd "$WORK" || exit 1
cp "$SKILL_DIR"/curlchrome.sh "$SKILL_DIR"/chain.py "$SKILL_DIR"/testproxy.sh .
chmod +x curlchrome.sh testproxy.sh
export TEST_URL="$URL"
log "step 0: direct fetch attempt (no proxy)"
: > jar.txt
./curlchrome.sh -c jar.txt -b jar.txt -o body.html -D h.a -w '%{http_code}' \
  --max-time 30 "$URL" 2>/dev/null | tr -d '\r' > code.a
if grep -q "<html" body.html 2>/dev/null && ! is_ipwall body.html; then
  log "direct fetch worked — no proxy needed"
  printf '%s\n%s\n' "$URL" "$(cat code.a)" > hop.txt
  PROXY="<direct>"
  report; exit 0
fi
log "blocked by IP reputation -> hunting live proxies"

# ---------------- fresh proxy lists -----------------------------------------
curl -sS --max-time 25 "https://raw.githubusercontent.com/monosans/proxy-list/main/proxies/http.txt"   -o list_http.txt   2>/dev/null || true
curl -sS --max-time 25 "https://raw.githubusercontent.com/monosans/proxy-list/main/proxies/socks5.txt" -o list_socks5.txt 2>/dev/null || true
if [ ! -s list_http.txt ] && [ ! -s list_socks5.txt ]; then
  curl -sS --max-time 25 "https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/http.txt"   -o list_http.txt   2>/dev/null || true
  curl -sS --max-time 25 "https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/socks5.txt" -o list_socks5.txt 2>/dev/null || true
fi
[ -s list_http.txt ] || [ -s list_socks5.txt ] || die "could not download any proxy list" 2

# ---------------- hunt: winner = real HTML, not the IP wall ------------------
rm -f win_*.html
( sed 's|^|http://|'    list_http.txt
  sed 's|^|socks5h://|' list_socks5.txt ) | shuf | \
  xargs -P 40 -n1 ./testproxy.sh > winners.txt 2>/dev/null
nwin=$(wc -l < winners.txt 2>/dev/null | tr -d ' ')
[ "${nwin:-0}" -gt 0 ] 2>/dev/null || die "no proxy passed the front door — rerun later" 2
log "passed: $nwin — serviceable order: socks5h first"

mapfile -t WINS < winners.txt
SOCKS=(); HTTP=()
for l in "${WINS[@]}"; do
  p="${l#WINNER }"
  [[ "$p" == socks5h://* ]] && SOCKS+=("$p") || HTTP+=("$p")
done
CANDIDATES=("${SOCKS[@]}" "${HTTP[@]}")

# ---------------- reliable step-1 session (try up to PROXY_TRIES proxies) ---
PORTAL_OK=0
for ((i=0; i<PROXY_TRIES && i<${#CANDIDATES[@]}; i++)); do
  PROXY="${CANDIDATES[$i]}"
  log "step 1 with $PROXY (try $((i+1))/$PROXY_TRIES)"
  rm -f jar.txt
  ./curlchrome.sh -x "$PROXY" -c jar.txt -b jar.txt -o portal.html -D h1.txt \
    --max-time 20 "$URL" 2>/dev/null
  if [ -s portal.html ] && ! is_ipwall portal.html && tokens_query | grep -q "="; then
    PORTAL_OK=1
    break
  fi
  log "  -> dead/slow/portal-empty, next candidate"
done
[ "$PORTAL_OK" = 1 ] || die "none of the passing proxies could hold a step-1 session — rerun later" 2

# ---------------- hop loop ---------------------------------------------------
REFERER="$URL"; EXTRA_URL=""; HOP=0; EMPTY_STREAK=0; LAST_Q=""
while [ $HOP -lt $MAX_HOPS ]; do
  HOP=$((HOP+1))
  Q="$(tokens_query)"
  if [ -n "$Q" ] && [ "$Q" != "$LAST_Q" ]; then
    LAST_Q="$Q"; EMPTY_STREAK=0
    log "hop $HOP: resubmit portal with tokens"
    do_hop "$URL?$Q" "$REFERER"
  elif [ -n "$EXTRA_URL" ]; then
    log "hop $HOP: following decoded target: $EXTRA_URL"
    do_hop "$EXTRA_URL" "$REFERER"; EXTRA_URL=""
  elif [ "$EMPTY_STREAK" -gt 0 ]; then
    log "hop $HOP: previous hop came back empty -> one retry of same query"
    do_hop "$URL?$Q" "$REFERER"; EMPTY_STREAK=$((EMPTY_STREAK+1))
  else
    break
  fi

  CODE="$(sed -n 2p hop.txt | tr -d '\r')"
  REFERER="$(sed -n 1p hop.txt | tr -d '\r')"
  if [ ! -s body.html ] || [ "$CODE" = "000" ]; then
    EMPTY_STREAK=1
    log "  -> empty response (code $CODE)"
    if [ "$EMPTY_STREAK" -ge 2 ]; then break; fi
    continue
  fi
  EMPTY_STREAK=0

  cp body.html state.html
  if is_portal state.html; then
    cp body.html portal.html            # new portal round: fresh tokens
  elif is_ipwall state.html; then
    die "proxy IP got demoted mid-chain — rerun the skill (fresh proxy)" 2
  else
    new="$(decode_meta_b64 body.html)"
    if [ -n "$new" ] && [ "$new" != "$URL" ]; then
      EXTRA_URL="$new"
    else
      break                              # real final page
    fi
  fi
done

if [ ! -s body.html ]; then
  report; echo "NOTE: chain did not produce a final page — see $WORK" >&2
  exit 2
fi
report
exit 0
