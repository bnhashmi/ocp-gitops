#!/bin/bash
set -euo pipefail

API="${API:-https://api.ocp4.example.com:6443}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-redhatocp}"
MARKETPLACE_NS="openshift-marketplace"
OPERATOR_NS="openshift-gitops-operator"
ARGO_NS="openshift-gitops"
PACKAGE="openshift-gitops-operator"
SUB_NAME="openshift-gitops-operator"
ARGO_NAME="openshift-gitops"
GROUP_NAME="gitops-admins"
TARGET_USER="cluster-admin"

login_cluster() {
  if oc whoami >/dev/null 2>&1; then
    return 0
  fi
  oc login "$API" -u "$ADMIN_USER" -p "$ADMIN_PASSWORD" --insecure-skip-tls-verify=true >/dev/null
}

discover_catalog() {
  oc get packagemanifest "$PACKAGE" -n "$MARKETPLACE_NS" \
    -o jsonpath='{.status.catalogSource}' 2>/dev/null
}

discover_channel() {
  oc get packagemanifest "$PACKAGE" -n "$MARKETPLACE_NS" \
    -o jsonpath='{.status.defaultChannel}' 2>/dev/null
}

wait_namespace_deleted() {
  local ns="$1"
  local i
  for i in $(seq 1 90); do
    if ! oc get ns "$ns" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "WARNING: namespace $ns still exists after timeout" >&2
  return 1
}
