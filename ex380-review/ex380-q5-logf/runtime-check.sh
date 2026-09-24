#!/usr/bin/env bash
set -u
NS="${NS:-openshift-logging}"
SYSLOG_HOST="${SYSLOG_HOST:-utility.lab.example.com}"
SYSLOG_SSH_USER="${SYSLOG_SSH_USER:-root}"

echo "== EventRouter functional check =="
oc get pod -n "$NS" -l component=eventrouter 2>/dev/null || true
printf '\nLatest EventRouter output:\n'
oc logs -n "$NS" deployment/eventrouter --tail=5 2>/dev/null || echo "No EventRouter logs available"

printf '\n== Syslog receiver files ==\n'
if ssh -o BatchMode=yes -o ConnectTimeout=4 "${SYSLOG_SSH_USER}@${SYSLOG_HOST}" true >/dev/null 2>&1; then
  ssh "${SYSLOG_SSH_USER}@${SYSLOG_HOST}" '
    for f in /var/log/ex380-app.log /var/log/ex380-infra.log /var/log/ex380-audit.log; do
      echo "--- $f ---"
      if [ -e "$f" ]; then
        wc -l "$f"
        tail -3 "$f"
      else
        echo MISSING
      fi
    done'
else
  echo "Unable to SSH to ${SYSLOG_SSH_USER}@${SYSLOG_HOST}"
fi
