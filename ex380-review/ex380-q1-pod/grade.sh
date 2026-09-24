#!/bin/bash
set -e

API="https://api.ocp4.example.com:6443"
IMAGE="quay.io/openshifttest/hello-openshift:1.2.0"
NS="ex380-q1-grade"

oc login "$API" \
  -u admin \
  -p redhatocp \
  --insecure-skip-tls-verify=true >/dev/null

SCORE=0

echo "=== EX380 Q1 GRADER ==="
echo

echo "[1] Checking master protection"
MASTER_OK=true

for NODE in master01 master02 master03
do
  if oc get node "$NODE" -o jsonpath='{.spec.taints}' | \
      grep -q 'node-role.kubernetes.io/control-plane'; then
    echo "PASS: $NODE remains tainted"
  else
    echo "FAIL: $NODE is not protected"
    MASTER_OK=false
  fi
done

if $MASTER_OK; then
  SCORE=$((SCORE+20))
fi

echo
echo "[2] Checking that accidental worker taint is gone"
WORKER_OK=true

for NODE in worker01 worker02 worker03
do
  if oc get node "$NODE" -o jsonpath='{.spec.taints}' | \
      grep -q 'ex380-scheduling'; then
    echo "FAIL: $NODE still has ex380-scheduling taint"
    WORKER_OK=false
  else
    echo "PASS: $NODE is clear"
  fi
done

if $WORKER_OK; then
  SCORE=$((SCORE+30))
fi

echo
echo "[3] Testing hello-openshift on every worker"

oc delete project "$NS" --ignore-not-found --wait=false >/dev/null 2>&1 || true

for X in $(seq 1 60)
do
  oc get project "$NS" >/dev/null 2>&1 || break
  sleep 1
done

oc new-project "$NS" >/dev/null

APP_OK=true
INDEX=0

for NODE in worker01 worker02 worker03
do
  INDEX=$((INDEX+1))

  cat <<EOF | oc apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: hello-${INDEX}
  namespace: ${NS}
spec:
  restartPolicy: Never
  nodeSelector:
    kubernetes.io/hostname: ${NODE}
  containers:
  - name: hello
    image: ${IMAGE}
EOF

done

INDEX=0
for NODE in worker01 worker02 worker03
do
  INDEX=$((INDEX+1))

  if oc wait pod/hello-${INDEX} \
       -n "$NS" \
       --for=condition=Ready \
       --timeout=120s >/dev/null 2>&1
  then
    ACTUAL=$(oc get pod hello-${INDEX} \
      -n "$NS" \
      -o jsonpath='{.spec.nodeName}')

    echo "PASS: hello-${INDEX} Running on $ACTUAL"

    if [ "$ACTUAL" != "$NODE" ]; then
      APP_OK=false
    fi
  else
    echo "FAIL: hello-${INDEX} did not run on $NODE"
    oc describe pod hello-${INDEX} -n "$NS" | tail -25
    APP_OK=false
  fi
done

if $APP_OK; then
  SCORE=$((SCORE+50))
fi

echo
echo "============================"
echo "SCORE: $SCORE/100"

if [ "$SCORE" -eq 100 ]; then
  echo "RESULT: PASS"
else
  echo "RESULT: NO PASS"
fi
