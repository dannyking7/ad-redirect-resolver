#!/usr/bin/env bash
# testproxy.sh — checks ONE proxy against TEST_URL.
# A winner = non-empty HTML that is NOT the "Anonymous Proxy detected" wall.
# Prints "WINNER <proxy>" and saves the body to /tmp-or-cwd win_<proxy>.html
u="$1"
body=$(curl -sS -x "$u" --max-time 9 \
  -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36" \
  -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
  -H "Accept-Language: en-US,en;q=0.9" \
  "${TEST_URL:?TEST_URL not set}" 2>/dev/null)
if [ -n "$body" ] && ! echo "$body" | grep -q "Anonymous Proxy detected" && echo "$body" | grep -q "<html"; then
  echo "WINNER $u"
  echo "$body" > "win_${u//[:\/]/_}.html"
fi
