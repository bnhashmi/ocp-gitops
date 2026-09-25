#!/bin/bash
set -e

URL="https://lynx.apps.ocp4.example.com"

GOOD=$(curl -k -sS \
  -o /tmp/lynx-good.out \
  -w '%{http_code}' \
  -u 'admin:Admin1andia!1958' \
  "$URL" || true)

BAD=$(curl -k -sS \
  -o /tmp/lynx-bad.out \
  -w '%{http_code}' \
  -u 'admin:wrongpassword' \
  "$URL" || true)

echo "Correct credentials: HTTP $GOOD"
cat /tmp/lynx-good.out 2>/dev/null || true

echo
echo "Wrong credentials: HTTP $BAD"
cat /tmp/lynx-bad.out 2>/dev/null || true

if [ "$GOOD" = "200" ] && [ "$BAD" = "401" ]; then
  echo
  echo "PASS"
else
  echo
  echo "FAIL"
  exit 1
fi
