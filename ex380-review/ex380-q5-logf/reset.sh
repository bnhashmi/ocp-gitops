#!/usr/bin/env bash
set -euo pipefail
API="${API:-https://api.ocp4.example.com:6443}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-redhatocp}"
NS="${NS:-openshift-logging}"
SYSLOG_HOST="${SYSLOG_HOST:-utility.lab.example.com}"
SYSLOG_SSH_USER="${SYSLOG_SSH_USER:-root}"

oc login "$API" -u "$ADMIN_USER" -p "$ADMIN_PASS" --insecure-skip-tls-verify=true >/dev/null
oc delete clusterlogforwarder.observability.openshift.io --all -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
oc delete deployment eventrouter -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
oc delete configmap eventrouter -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
oc delete serviceaccount eventrouter -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
oc delete clusterrolebinding event-reader-binding --ignore-not-found >/dev/null 2>&1 || true
oc delete clusterrole event-reader --ignore-not-found >/dev/null 2>&1 || true
if ssh -o BatchMode=yes -o ConnectTimeout=4 "${SYSLOG_SSH_USER}@${SYSLOG_HOST}" true >/dev/null 2>&1; then
  ssh "${SYSLOG_SSH_USER}@${SYSLOG_HOST}" \
    'for f in /var/log/ex380-app.log /var/log/ex380-infra.log /var/log/ex380-audit.log; do : > "$f"; done' || true
fi
echo "Q5 reset complete. Logging operator and logcollector prerequisite remain installed."
