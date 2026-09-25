#!/bin/bash
set -e

API="https://api.ocp4.example.com:6443"
OADP_NS="openshift-adp"
SCHEDULE="lynx-web-schedule"
RESTORE="restore-lynx-web"
URL="https://lynx.apps.ocp4.example.com"

SCORE=0

pass_check() {
  SCORE=$((SCORE+$1))
  echo "[PASS +$1] $2"
}

fail_check() {
  echo "[FAIL +0] $1"
}

echo "=== EX380 Q3 GRADER ==="

oc login "$API" \
  -u admin \
  -p redhatocp \
  --insecure-skip-tls-verify=true >/dev/null

LATEST=$(oc get backups.velero.io \
  -n "$OADP_NS" \
  -l velero.io/schedule-name="$SCHEDULE" \
  -o json 2>/dev/null | python3 -c '
import json,sys
o=json.load(sys.stdin)
items=[x for x in o.get("items",[]) if x.get("status",{}).get("phase")=="Completed"]
items.sort(key=lambda x:x.get("status",{}).get("completionTimestamp",""))
print(items[-1]["metadata"]["name"] if items else "")
' 2>/dev/null || true)

echo "Latest Completed scheduled backup: ${LATEST:-NONE}"

if [ -n "$LATEST" ]; then
  pass_check 15 "Completed scheduled backup exists"
else
  fail_check "No Completed scheduled backup found"
fi

if oc get restore "$RESTORE" -n "$OADP_NS" >/dev/null 2>&1; then
  pass_check 15 "restore-lynx-web exists"
else
  fail_check "restore-lynx-web does not exist"
fi

BACKUP_NAME=$(oc get restore "$RESTORE" \
  -n "$OADP_NS" \
  -o jsonpath='{.spec.backupName}' 2>/dev/null || true)

SCHEDULE_NAME=$(oc get restore "$RESTORE" \
  -n "$OADP_NS" \
  -o jsonpath='{.spec.scheduleName}' 2>/dev/null || true)

if [ -n "$LATEST" ] && [ "$BACKUP_NAME" = "$LATEST" ]; then
  pass_check 20 "Restore uses latest Completed backup: $LATEST"
elif [ "$SCHEDULE_NAME" = "$SCHEDULE" ]; then
  pass_check 20 "Restore selects latest successful backup from schedule $SCHEDULE"
else
  fail_check "Restore did not use the latest completed scheduled backup"
  echo "  latest backup: $LATEST"
  echo "  backupName:    $BACKUP_NAME"
  echo "  scheduleName:  $SCHEDULE_NAME"
fi

PHASE=$(oc get restore "$RESTORE" \
  -n "$OADP_NS" \
  -o jsonpath='{.status.phase}' 2>/dev/null || true)

if [ "$PHASE" = "Completed" ]; then
  pass_check 20 "Restore phase is Completed"
else
  fail_check "Restore phase is ${PHASE:-missing}"
fi

if oc get deployment lynx -n lynx-web >/dev/null 2>&1 && \
   oc get service lynx -n lynx-web >/dev/null 2>&1 && \
   oc get route lynx -n lynx-web >/dev/null 2>&1; then
  pass_check 10 "Lynx deployment, service and route restored"
else
  fail_check "Lynx application resources are incomplete"
fi

READY=$(oc get deployment lynx \
  -n lynx-web \
  -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)

if [ "${READY:-0}" -ge 1 ] 2>/dev/null; then
  pass_check 10 "Lynx pod is Ready"
else
  fail_check "Lynx deployment is not Ready"
fi

GOOD=$(curl -k -sS \
  -o /tmp/q3-good.out \
  -w '%{http_code}' \
  -u 'admin:Admin1andia!1958' \
  "$URL" 2>/dev/null || true)

BAD=$(curl -k -sS \
  -o /tmp/q3-bad.out \
  -w '%{http_code}' \
  -u 'admin:wrongpassword' \
  "$URL" 2>/dev/null || true)

if [ "$GOOD" = "200" ] && [ "$BAD" = "401" ]; then
  pass_check 10 "Required credentials work over HTTPS"
else
  fail_check "Application authentication failed"
  echo "  correct credentials HTTP=$GOOD"
  echo "  wrong credentials   HTTP=$BAD"
fi

echo
echo "-----------------------------"
echo "SCORE: $SCORE/100"

if [ "$SCORE" -eq 100 ]; then
  echo "RESULT: PASS"
else
  echo "RESULT: NO PASS"
fi
