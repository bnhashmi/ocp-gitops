#!/bin/bash
set -e

API="https://api.ocp4.example.com:6443"
OADP_NS="openshift-adp"
SCHEDULE="lynx-web-schedule"
RESTORE="restore-lynx-web"

oc login "$API" \
  -u admin \
  -p redhatocp \
  --insecure-skip-tls-verify=true >/dev/null

echo "==> Finding latest Completed backup from $SCHEDULE"

LATEST=$(oc get backups.velero.io \
  -n "$OADP_NS" \
  -l velero.io/schedule-name="$SCHEDULE" \
  -o json | python3 -c '
import json,sys
o=json.load(sys.stdin)
items=[x for x in o.get("items",[]) if x.get("status",{}).get("phase")=="Completed"]
items.sort(key=lambda x:x.get("status",{}).get("completionTimestamp",""))
print(items[-1]["metadata"]["name"] if items else "")
')

if [ -z "$LATEST" ]; then
  echo "ERROR: no Completed scheduled backup found."
  exit 1
fi

echo "    Latest: $LATEST"

oc delete restore "$RESTORE" \
  -n "$OADP_NS" \
  --ignore-not-found >/dev/null 2>&1 || true

cat <<EOF | oc apply -f -
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: ${RESTORE}
  namespace: ${OADP_NS}
spec:
  backupName: ${LATEST}
EOF

echo "==> Waiting for restore"

for i in $(seq 1 180); do
  PHASE=$(oc get restore "$RESTORE" \
    -n "$OADP_NS" \
    -o jsonpath='{.status.phase}' 2>/dev/null || true)

  echo "    ${PHASE:-New}"

  if [ "$PHASE" = "Completed" ]; then
    break
  fi

  case "$PHASE" in
    Failed|FailedValidation|PartiallyFailed)
      oc describe restore "$RESTORE" -n "$OADP_NS"
      exit 1
      ;;
  esac

  sleep 2
done

echo
oc get all,route -n lynx-web
