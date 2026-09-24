#!/bin/bash
set -euo pipefail
DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../common.sh
source "$DIR/common.sh"

login_cluster

CATALOG=$(discover_catalog)
CHANNEL=$(discover_channel)
if [[ -z "$CATALOG" || -z "$CHANNEL" ]]; then
  echo "Cannot discover GitOps PackageManifest/catalog/channel" >&2
  exit 1
fi

echo "Using CatalogSource=$CATALOG channel=$CHANNEL"

oc create namespace "$OPERATOR_NS" --dry-run=client -o yaml | oc apply -f -

cat <<YAML | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-gitops-operator
  namespace: ${OPERATOR_NS}
spec: {}
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ${SUB_NAME}
  namespace: ${OPERATOR_NS}
spec:
  channel: ${CHANNEL}
  installPlanApproval: Automatic
  name: ${PACKAGE}
  source: ${CATALOG}
  sourceNamespace: ${MARKETPLACE_NS}
YAML

echo "Waiting for GitOps Operator CSV..."
CSV=""
for i in $(seq 1 120); do
  CSV=$(oc get subscription "$SUB_NAME" -n "$OPERATOR_NS" -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)
  if [[ -n "$CSV" ]]; then
    PHASE=$(oc get csv "$CSV" -n "$OPERATOR_NS" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [[ "$PHASE" == "Succeeded" ]]; then
      echo "CSV $CSV succeeded"
      break
    fi
  fi
  sleep 3
done
if [[ -z "$CSV" ]] || [[ "$(oc get csv "$CSV" -n "$OPERATOR_NS" -o jsonpath='{.status.phase}' 2>/dev/null || true)" != "Succeeded" ]]; then
  echo "Operator installation did not complete" >&2
  oc get subscription,csv -n "$OPERATOR_NS" >&2 || true
  exit 1
fi

echo "Waiting for default Argo CD instance..."
for i in $(seq 1 120); do
  if oc get argocd "$ARGO_NAME" -n "$ARGO_NS" >/dev/null 2>&1; then
    break
  fi
  sleep 3
done
oc get argocd "$ARGO_NAME" -n "$ARGO_NS" >/dev/null

# Route + RBAC.
oc patch argocd "$ARGO_NAME" -n "$ARGO_NS" --type=merge -p '{
  "spec": {
    "server": {
      "route": {
        "enabled": true,
        "tls": {
          "termination": "reencrypt",
          "insecureEdgeTerminationPolicy": "Redirect"
        }
      }
    },
    "rbac": {
      "policy": "g, gitops-admins, role:admin",
      "scopes": "[groups]"
    }
  }
}'

# Required OpenShift group and membership.
if oc get group "$GROUP_NAME" >/dev/null 2>&1; then
  oc adm groups add-users "$GROUP_NAME" "$TARGET_USER"
else
  oc adm groups new "$GROUP_NAME" "$TARGET_USER"
fi

# Trusted cluster CA bundle for repo-server.
oc create configmap cluster-root-ca-bundle -n "$ARGO_NS" \
  --dry-run=client -o yaml | oc apply -f -

oc label configmap cluster-root-ca-bundle -n "$ARGO_NS" \
  config.openshift.io/inject-trusted-cabundle=true --overwrite

echo "Waiting for ca-bundle.crt injection..."
for i in $(seq 1 60); do
  BUNDLE=$(oc get configmap cluster-root-ca-bundle -n "$ARGO_NS" \
    -o jsonpath='{.data.ca-bundle\.crt}' 2>/dev/null || true)
  [[ -n "$BUNDLE" ]] && break
  sleep 2
done

oc patch argocd "$ARGO_NAME" -n "$ARGO_NS" --type=merge -p '{
  "spec": {
    "repo": {
      "volumeMounts": [
        {
          "name": "cluster-root-ca-bundle",
          "mountPath": "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem",
          "subPath": "ca-bundle.crt",
          "readOnly": true
        }
      ],
      "volumes": [
        {
          "name": "cluster-root-ca-bundle",
          "configMap": {
            "name": "cluster-root-ca-bundle"
          }
        }
      ]
    }
  }
}'

# Wait for route and repo deployment reconciliation.
echo "Waiting for Argo CD route..."
for i in $(seq 1 60); do
  TERM=$(oc get route -n "$ARGO_NS" -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.spec.to.name}{"|"}{.spec.tls.termination}{"\n"}{end}' 2>/dev/null | awk -F'|' '$2 ~ /server/ {print $3; exit}')
  [[ "$TERM" == "reencrypt" ]] && break
  sleep 2
done

echo "Waiting for repo-server rollout..."
REPO_DEPLOY=$(oc get deployment -n "$ARGO_NS" -o name 2>/dev/null | grep 'repo-server' | head -1 || true)
if [[ -n "$REPO_DEPLOY" ]]; then
  oc rollout status -n "$ARGO_NS" "$REPO_DEPLOY" --timeout=180s || true
fi

echo "Instructor solution applied."
echo "Run: $DIR/grade.sh"
