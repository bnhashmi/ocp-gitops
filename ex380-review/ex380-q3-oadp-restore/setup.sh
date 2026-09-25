#!/bin/bash
set -e

API="https://api.ocp4.example.com:6443"
ADMIN_USER="admin"
ADMIN_PASSWORD="redhatocp"

OADP_NS="openshift-adp"
APP_NS="lynx-web"
SCHEDULE="lynx-web-schedule"
RESTORE="restore-lynx-web"
OBC="backup-oadp"
DPA="dpa"
HOST="lynx.apps.ocp4.example.com"

echo "=== EX380 Q3 COMPLETE EXAM SETUP ==="

oc login "$API" \
  -u "$ADMIN_USER" \
  -p "$ADMIN_PASSWORD" \
  --insecure-skip-tls-verify=true >/dev/null

echo "==> Connected as $(oc whoami)"

###############################################################################
# 1. Install OADP operator
###############################################################################

echo
echo "==> Detecting OADP CatalogSource and channel"

CATALOG=$(oc get packagemanifest redhat-oadp-operator \
  -n openshift-marketplace \
  -o jsonpath='{.status.catalogSource}' 2>/dev/null || true)

CHANNEL=$(oc get packagemanifest redhat-oadp-operator \
  -n openshift-marketplace \
  -o jsonpath='{.status.defaultChannel}' 2>/dev/null || true)

if [ -z "$CATALOG" ] || [ -z "$CHANNEL" ]; then
  echo "ERROR: redhat-oadp-operator PackageManifest is not available."
  echo
  oc get catalogsource -n openshift-marketplace || true
  exit 1
fi

echo "    CatalogSource: $CATALOG"
echo "    Channel:       $CHANNEL"

oc create namespace "$OADP_NS" \
  --dry-run=client -o yaml | oc apply -f - >/dev/null

cat <<EOF | oc apply -f - >/dev/null
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-adp
  namespace: ${OADP_NS}
spec:
  targetNamespaces:
  - ${OADP_NS}
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: redhat-oadp-operator
  namespace: ${OADP_NS}
spec:
  channel: ${CHANNEL}
  installPlanApproval: Automatic
  name: redhat-oadp-operator
  source: ${CATALOG}
  sourceNamespace: openshift-marketplace
EOF

echo "==> Waiting for OADP CSV"

CSV=""
for i in $(seq 1 180); do
  CSV=$(oc get subscription redhat-oadp-operator \
    -n "$OADP_NS" \
    -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)

  if [ -n "$CSV" ]; then
    PHASE=$(oc get csv "$CSV" \
      -n "$OADP_NS" \
      -o jsonpath='{.status.phase}' 2>/dev/null || true)

    echo "    $CSV -> ${PHASE:-Installing}"

    if [ "$PHASE" = "Succeeded" ]; then
      break
    fi
  fi

  sleep 2
done

if [ -z "$CSV" ]; then
  echo "ERROR: OADP Subscription never produced installedCSV."
  exit 1
fi

PHASE=$(oc get csv "$CSV" \
  -n "$OADP_NS" \
  -o jsonpath='{.status.phase}' 2>/dev/null || true)

if [ "$PHASE" != "Succeeded" ]; then
  echo "ERROR: OADP CSV is not Succeeded."
  oc get csv -n "$OADP_NS"
  exit 1
fi

echo "==> OADP operator installed: $CSV"

###############################################################################
# 2. Provision object storage using an ObjectBucketClaim
###############################################################################

echo
echo "==> Checking ObjectBucketClaim API"

for i in $(seq 1 60); do
  if oc api-resources | grep -q '^objectbucketclaims'; then
    break
  fi
  sleep 2
done

if ! oc api-resources | grep -q '^objectbucketclaims'; then
  echo "ERROR: ObjectBucketClaim API is unavailable."
  echo "This lab needs NooBaa/ObjectBucket storage for the backup."
  exit 1
fi

echo "==> Detecting NooBaa/ObjectBucket StorageClass"

OBC_SC=$(oc get sc -o json | python3 -c '
import json,sys
o=json.load(sys.stdin)
preferred=[]
other=[]
for x in o.get("items",[]):
    name=x["metadata"]["name"]
    prov=x.get("provisioner","")
    line=(name,prov)
    if name=="openshift-storage.noobaa.io":
        preferred.insert(0,line)
    elif "noobaa" in name.lower() or "noobaa" in prov.lower() or "objectbucket" in prov.lower():
        other.append(line)
choices=preferred+other
print(choices[0][0] if choices else "")
')

if [ -z "$OBC_SC" ]; then
  echo "ERROR: No NooBaa/ObjectBucket StorageClass found."
  oc get sc
  exit 1
fi

echo "    OBC StorageClass: $OBC_SC"

# Remove previous Q3 backup configuration if it exists.
oc delete dpa "$DPA" \
  -n "$OADP_NS" \
  --ignore-not-found --wait=true >/dev/null 2>&1 || true

oc delete obc "$OBC" \
  -n "$OADP_NS" \
  --ignore-not-found --wait=true >/dev/null 2>&1 || true

oc delete secret cloud-credentials \
  -n "$OADP_NS" \
  --ignore-not-found >/dev/null 2>&1 || true

cat <<EOF | oc apply -f - >/dev/null
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  name: ${OBC}
  namespace: ${OADP_NS}
spec:
  generateBucketName: ${OBC}
  storageClassName: ${OBC_SC}
EOF

echo "==> Waiting for ObjectBucketClaim credentials"

for i in $(seq 1 120); do
  if oc get cm "$OBC" -n "$OADP_NS" >/dev/null 2>&1 && \
     oc get secret "$OBC" -n "$OADP_NS" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! oc get cm "$OBC" -n "$OADP_NS" >/dev/null 2>&1; then
  echo "ERROR: OBC ConfigMap was not created."
  oc get obc "$OBC" -n "$OADP_NS" -o yaml || true
  exit 1
fi

BUCKET=$(oc get cm "$OBC" -n "$OADP_NS" \
  -o jsonpath='{.data.BUCKET_NAME}')

BUCKET_HOST=$(oc get cm "$OBC" -n "$OADP_NS" \
  -o jsonpath='{.data.BUCKET_HOST}')

BUCKET_PORT=$(oc get cm "$OBC" -n "$OADP_NS" \
  -o jsonpath='{.data.BUCKET_PORT}')

BUCKET_REGION=$(oc get cm "$OBC" -n "$OADP_NS" \
  -o jsonpath='{.data.BUCKET_REGION}' 2>/dev/null || true)

[ -n "$BUCKET_REGION" ] || BUCKET_REGION="us-east-1"

ACCESS_KEY=$(oc get secret "$OBC" -n "$OADP_NS" \
  -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)

SECRET_KEY=$(oc get secret "$OBC" -n "$OADP_NS" \
  -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)

echo "    Bucket:   $BUCKET"
echo "    Endpoint: $BUCKET_HOST:$BUCKET_PORT"
echo "    Region:   $BUCKET_REGION"

cat >/tmp/cloud-credentials <<EOF
[default]
aws_access_key_id=${ACCESS_KEY}
aws_secret_access_key=${SECRET_KEY}
EOF

oc create secret generic cloud-credentials \
  -n "$OADP_NS" \
  --from-file=cloud=/tmp/cloud-credentials \
  --dry-run=client -o yaml | oc apply -f - >/dev/null

###############################################################################
# 3. Create DPA
###############################################################################

echo
echo "==> Creating DataProtectionApplication"

cat <<EOF | oc apply -f - >/dev/null
apiVersion: oadp.openshift.io/v1alpha1
kind: DataProtectionApplication
metadata:
  name: ${DPA}
  namespace: ${OADP_NS}
spec:
  configuration:
    velero:
      defaultPlugins:
      - openshift
      - aws
      - csi
  backupLocations:
  - velero:
      provider: aws
      default: true
      credential:
        key: cloud
        name: cloud-credentials
      objectStorage:
        bucket: ${BUCKET}
        prefix: velero
      config:
        region: ${BUCKET_REGION}
        s3Url: https://${BUCKET_HOST}:${BUCKET_PORT}
        s3ForcePathStyle: "true"
        insecureSkipTLSVerify: "true"
EOF

echo "==> Waiting for DPA reconciliation"

for i in $(seq 1 180); do
  REC=$(oc get dpa "$DPA" -n "$OADP_NS" \
    -o jsonpath='{range .status.conditions[?(@.type=="Reconciled")]}{.status}{end}' \
    2>/dev/null || true)

  if [ "$REC" = "True" ]; then
    break
  fi

  sleep 2
done

REC=$(oc get dpa "$DPA" -n "$OADP_NS" \
  -o jsonpath='{range .status.conditions[?(@.type=="Reconciled")]}{.status}{end}' \
  2>/dev/null || true)

if [ "$REC" != "True" ]; then
  echo "ERROR: DPA did not reconcile."
  oc get dpa "$DPA" -n "$OADP_NS" -o yaml
  exit 1
fi

echo "==> Waiting for Available BackupStorageLocation"

BSL=""
for i in $(seq 1 180); do
  BSL=$(oc get backupstoragelocations.velero.io \
    -n "$OADP_NS" \
    -o jsonpath='{range .items[?(@.status.phase=="Available")]}{.metadata.name}{"\n"}{end}' \
    2>/dev/null | head -1)

  [ -n "$BSL" ] && break
  sleep 2
done

if [ -z "$BSL" ]; then
  echo "ERROR: No BackupStorageLocation reached Available."
  oc get backupstoragelocations.velero.io -n "$OADP_NS" -o wide || true
  exit 1
fi

echo "    BSL: $BSL"

###############################################################################
# 4. Deploy the Lynx application
###############################################################################

echo
echo "==> Removing previous Q3 restore/schedule/backups/application"

oc delete restore "$RESTORE" \
  -n "$OADP_NS" \
  --ignore-not-found >/dev/null 2>&1 || true

oc delete schedule "$SCHEDULE" \
  -n "$OADP_NS" \
  --ignore-not-found >/dev/null 2>&1 || true

for B in $(oc get backups.velero.io \
  -n "$OADP_NS" \
  -l velero.io/schedule-name="$SCHEDULE" \
  -o name 2>/dev/null); do
  oc delete "$B" -n "$OADP_NS" --wait=false >/dev/null 2>&1 || true
done

oc delete project "$APP_NS" \
  --ignore-not-found --wait=false >/dev/null 2>&1 || true

for i in $(seq 1 90); do
  oc get project "$APP_NS" >/dev/null 2>&1 || break
  sleep 2
done

oc new-project "$APP_NS" >/dev/null

cat >/tmp/lynx-app.py <<'PYAPP'
import base64
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

USER = os.environ.get("LYNX_USER", "admin")
PASSWORD = os.environ.get("LYNX_PASSWORD", "Admin1andia!1958")
EXPECTED = "Basic " + base64.b64encode(f"{USER}:{PASSWORD}".encode()).decode()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.headers.get("Authorization", "") != EXPECTED:
            self.send_response(401)
            self.send_header("WWW-Authenticate", 'Basic realm="lynx"')
            self.end_headers()
            self.wfile.write(b"Authentication required\n")
            return

        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"LYNX WEB APPLICATION\n")
        self.wfile.write(b"OADP restore lab\n")

    def log_message(self, fmt, *args):
        print(fmt % args, flush=True)

HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()

PYAPP

oc create configmap lynx-app-code \
  -n "$APP_NS" \
  --from-file=app.py=/tmp/lynx-app.py >/dev/null

oc create secret generic lynx-auth \
  -n "$APP_NS" \
  --from-literal=username=admin \
  --from-literal=password='Admin1andia!1958' >/dev/null

cat <<'EOF' | oc apply -f - >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lynx
  namespace: lynx-web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: lynx
  template:
    metadata:
      labels:
        app: lynx
    spec:
      containers:
      - name: lynx
        image: registry.access.redhat.com/ubi9/python-311:latest
        command:
        - python3
        - /opt/app-root/src/app.py
        ports:
        - containerPort: 8080
        env:
        - name: LYNX_USER
          valueFrom:
            secretKeyRef:
              name: lynx-auth
              key: username
        - name: LYNX_PASSWORD
          valueFrom:
            secretKeyRef:
              name: lynx-auth
              key: password
        volumeMounts:
        - name: app-code
          mountPath: /opt/app-root/src/app.py
          subPath: app.py
      volumes:
      - name: app-code
        configMap:
          name: lynx-app-code
---
apiVersion: v1
kind: Service
metadata:
  name: lynx
  namespace: lynx-web
spec:
  selector:
    app: lynx
  ports:
  - name: http
    port: 8080
    targetPort: 8080
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: lynx
  namespace: lynx-web
spec:
  host: lynx.apps.ocp4.example.com
  to:
    kind: Service
    name: lynx
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
EOF

echo "==> Waiting for Lynx deployment"

oc rollout status deployment/lynx \
  -n "$APP_NS" \
  --timeout=300s

echo "==> Verifying Lynx before backup"

GOOD=$(curl -k -sS \
  -o /tmp/lynx-before.out \
  -w '%{http_code}' \
  -u 'admin:Admin1andia!1958' \
  "https://${HOST}" || true)

BAD=$(curl -k -sS \
  -o /tmp/lynx-before-bad.out \
  -w '%{http_code}' \
  -u 'admin:wrongpassword' \
  "https://${HOST}" || true)

if [ "$GOOD" != "200" ] || [ "$BAD" != "401" ]; then
  echo "ERROR: Lynx application authentication is not correct."
  echo "Correct credentials HTTP=$GOOD"
  echo "Wrong credentials   HTTP=$BAD"
  exit 1
fi

echo "    Lynx is functional."

###############################################################################
# 5. Create a REAL scheduled backup
###############################################################################

echo
echo "==> Creating scheduled backup"

cat <<EOF | oc apply -f - >/dev/null
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: ${SCHEDULE}
  namespace: ${OADP_NS}
spec:
  schedule: "* * * * *"
  paused: false
  template:
    includedNamespaces:
    - ${APP_NS}
    storageLocation: ${BSL}
    ttl: 720h0m0s
EOF

echo "==> Waiting for latest scheduled backup to reach Completed"

BACKUP=""

for i in $(seq 1 180); do
  BACKUP=$(oc get backups.velero.io \
    -n "$OADP_NS" \
    -l velero.io/schedule-name="$SCHEDULE" \
    -o json 2>/dev/null | python3 -c '
import json,sys
o=json.load(sys.stdin)
items=[
  x for x in o.get("items",[])
  if x.get("status",{}).get("phase")=="Completed"
]
items.sort(key=lambda x:x.get("status",{}).get("completionTimestamp",""))
print(items[-1]["metadata"]["name"] if items else "")
' 2>/dev/null || true)

  if [ -n "$BACKUP" ]; then
    break
  fi

  sleep 2
done

if [ -z "$BACKUP" ]; then
  echo "ERROR: scheduled backup never reached Completed."
  oc get schedule "$SCHEDULE" -n "$OADP_NS" -o yaml || true
  oc get backups.velero.io -n "$OADP_NS" || true
  exit 1
fi

echo "    Completed backup: $BACKUP"

echo "==> Pausing schedule"
oc patch schedule "$SCHEDULE" \
  -n "$OADP_NS" \
  --type=merge \
  -p '{"spec":{"paused":true}}' >/dev/null

###############################################################################
# 6. Delete application — this is the student's starting point
###############################################################################

echo
echo "==> Deleting Lynx application project"

oc delete project "$APP_NS" --wait=false >/dev/null

for i in $(seq 1 120); do
  oc get project "$APP_NS" >/dev/null 2>&1 || break
  sleep 2
done

if oc get project "$APP_NS" >/dev/null 2>&1; then
  echo "ERROR: $APP_NS did not finish deleting."
  exit 1
fi

echo
echo "====================================================="
echo "EX380 Q3 EXAM STATE READY"
echo "====================================================="
echo "OADP CSV:             $CSV"
echo "BackupStorageLocation:$BSL"
echo "Schedule:             $SCHEDULE (paused)"
echo "Latest backup:        $BACKUP (Completed)"
echo "Application project:  DELETED"
echo
echo "Student task:"
echo "  Restore latest completed scheduled backup as restore-lynx-web"
echo "====================================================="
