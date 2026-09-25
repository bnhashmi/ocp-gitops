#!/bin/bash
set -e

API="https://api.ocp4.example.com:6443"
NS="openshift-adp"

oc login "$API" \
  -u admin \
  -p redhatocp \
  --insecure-skip-tls-verify=true >/dev/null

echo "=== FULL Q3 CLEANUP ==="

oc delete project lynx-web \
  --ignore-not-found --wait=false 2>/dev/null || true

oc delete restore restore-lynx-web \
  -n "$NS" \
  --ignore-not-found >/dev/null 2>&1 || true

oc delete schedule lynx-web-schedule \
  -n "$NS" \
  --ignore-not-found >/dev/null 2>&1 || true

for B in $(oc get backups.velero.io \
  -n "$NS" \
  -l velero.io/schedule-name=lynx-web-schedule \
  -o name 2>/dev/null); do
  oc delete "$B" -n "$NS" --wait=false >/dev/null 2>&1 || true
done

oc delete dpa dpa -n "$NS" \
  --ignore-not-found --wait=true >/dev/null 2>&1 || true

oc delete obc backup-oadp -n "$NS" \
  --ignore-not-found --wait=true >/dev/null 2>&1 || true

oc delete secret cloud-credentials -n "$NS" \
  --ignore-not-found >/dev/null 2>&1 || true

SUBCSV=$(oc get subscription redhat-oadp-operator \
  -n "$NS" \
  -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)

oc delete subscription redhat-oadp-operator \
  -n "$NS" \
  --ignore-not-found >/dev/null 2>&1 || true

if [ -n "$SUBCSV" ]; then
  oc delete csv "$SUBCSV" \
    -n "$NS" \
    --ignore-not-found >/dev/null 2>&1 || true
fi

oc delete operatorgroup openshift-adp \
  -n "$NS" \
  --ignore-not-found >/dev/null 2>&1 || true

echo "FULL CLEANUP COMPLETE"
