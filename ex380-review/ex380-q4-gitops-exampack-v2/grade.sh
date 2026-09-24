#!/bin/bash
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=common.sh
source "$DIR/common.sh"

login_cluster || exit 1

SCORE=0
PASS_COUNT=0
FAIL_COUNT=0

pass() {
  local pts="$1"; shift
  SCORE=$((SCORE + pts)); PASS_COUNT=$((PASS_COUNT + 1))
  printf '[PASS +%2d] %s\n' "$pts" "$*"
}
fail() {
  local pts="$1"; shift
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '[FAIL + 0/%2d] %s\n' "$pts" "$*"
}

printf '%s\n' "EX380 Q4 grader — OpenShift GitOps" "====================================="

# 1) Operator installation: 20
if ! oc get ns "$OPERATOR_NS" >/dev/null 2>&1; then
  fail 20 "Required project $OPERATOR_NS does not exist"
else
  SUB=$(oc get subscription -n "$OPERATOR_NS" -o jsonpath='{range .items[?(@.spec.name=="openshift-gitops-operator")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -1)
  if [[ -z "$SUB" ]]; then
    fail 20 "GitOps Subscription is not installed in $OPERATOR_NS"
  else
    CSV=$(oc get subscription "$SUB" -n "$OPERATOR_NS" -o jsonpath='{.status.installedCSV}' 2>/dev/null)
    PHASE=""
    [[ -n "$CSV" ]] && PHASE=$(oc get csv "$CSV" -n "$OPERATOR_NS" -o jsonpath='{.status.phase}' 2>/dev/null)
    if [[ "$PHASE" == "Succeeded" ]]; then
      SRC=$(oc get subscription "$SUB" -n "$OPERATOR_NS" -o jsonpath='{.spec.source}' 2>/dev/null)
      pass 20 "GitOps Operator installed in $OPERATOR_NS (CSV Succeeded, source=$SRC)"
    else
      fail 20 "GitOps Operator is not successfully installed in $OPERATOR_NS (CSV phase=${PHASE:-unknown})"
    fi
  fi
fi

# Resolve Argo CD instance once.
ARGO=$(oc get argocd -n "$ARGO_NS" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

# 2) Argo CD route TLS: 20
if [[ -z "$ARGO" ]]; then
  fail 20 "No ArgoCD instance found in $ARGO_NS"
else
  ROUTE=$(oc get route -n "$ARGO_NS" -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.spec.to.name}{"|"}{.spec.tls.termination}{"\n"}{end}' 2>/dev/null | awk -F'|' '$2 ~ /server/ {print; exit}')
  TERM=$(printf '%s' "$ROUTE" | awk -F'|' '{print $3}')
  if [[ "$TERM" == "reencrypt" ]]; then
    pass 20 "Argo CD server Route exists with reencrypt TLS termination"
  else
    CR_TERM=$(oc get argocd "$ARGO" -n "$ARGO_NS" -o jsonpath='{.spec.server.route.tls.termination}' 2>/dev/null)
    fail 20 "Argo CD server Route termination is '${TERM:-missing}' (CR requests '${CR_TERM:-unset}')"
  fi
fi

# 3) Group membership: 15
USERS=$(oc get group "$GROUP_NAME" -o jsonpath='{.users[*]}' 2>/dev/null)
if printf ' %s ' "$USERS" | grep -Fq " $TARGET_USER "; then
  pass 15 "$TARGET_USER is a member of $GROUP_NAME"
else
  fail 15 "$TARGET_USER is not a member of $GROUP_NAME"
fi

# 4) Argo CD RBAC: 25
if [[ -z "$ARGO" ]]; then
  fail 25 "Cannot grade Argo CD RBAC because no ArgoCD instance exists"
else
  POLICY=$(oc get argocd "$ARGO" -n "$ARGO_NS" -o jsonpath='{.spec.rbac.policy}' 2>/dev/null)
  SCOPES=$(oc get argocd "$ARGO" -n "$ARGO_NS" -o jsonpath='{.spec.rbac.scopes}' 2>/dev/null)

  ADMIN_COUNT=$(printf '%s\n' "$POLICY" | grep -Ec 'role:[[:space:]]*admin' || true)
  GOOD_COUNT=$(printf '%s\n' "$POLICY" | grep -Ec '^[[:space:]]*g[[:space:]]*,[[:space:]]*gitops-admins[[:space:]]*,[[:space:]]*role:admin[[:space:]]*$' || true)

  if [[ "$ADMIN_COUNT" -eq 1 && "$GOOD_COUNT" -eq 1 && "$SCOPES" == *groups* ]]; then
    pass 25 "Only gitops-admins is mapped to role:admin and RBAC scope includes groups"
  else
    fail 25 "RBAC policy must have exactly one role:admin group mapping: 'g, gitops-admins, role:admin', with groups scope"
    echo "         Current scopes: ${SCOPES:-<unset>}"
    echo "         Current policy:"
    printf '%s\n' "$POLICY" | sed 's/^/           /'
  fi
fi

# 5) Trusted CA ConfigMap + repo mount: 20 total
CM_OK=0
if oc get configmap cluster-root-ca-bundle -n "$ARGO_NS" >/dev/null 2>&1; then
  LABEL=$(oc get configmap cluster-root-ca-bundle -n "$ARGO_NS" -o jsonpath='{.metadata.labels.config\.openshift\.io/inject-trusted-cabundle}' 2>/dev/null)
  BUNDLE=$(oc get configmap cluster-root-ca-bundle -n "$ARGO_NS" -o jsonpath='{.data.ca-bundle\.crt}' 2>/dev/null)
  if [[ "$LABEL" == "true" && -n "$BUNDLE" ]]; then
    pass 7 "cluster-root-ca-bundle requests trusted CA injection and contains ca-bundle.crt"
    CM_OK=1
  else
    fail 7 "cluster-root-ca-bundle must have inject-trusted-cabundle=true and non-empty data.ca-bundle.crt"
  fi
else
  fail 7 "ConfigMap $ARGO_NS/cluster-root-ca-bundle does not exist"
fi

if [[ -z "$ARGO" ]]; then
  fail 13 "Cannot grade repo-server CA mount because no ArgoCD instance exists"
else
  VOL_CM=$(oc get argocd "$ARGO" -n "$ARGO_NS" -o jsonpath='{range .spec.repo.volumes[?(@.name=="cluster-root-ca-bundle")]}{.configMap.name}{"\n"}{end}' 2>/dev/null | head -1)
  MOUNT_PATH=$(oc get argocd "$ARGO" -n "$ARGO_NS" -o jsonpath='{range .spec.repo.volumeMounts[?(@.name=="cluster-root-ca-bundle")]}{.mountPath}{"\n"}{end}' 2>/dev/null | head -1)
  SUB_PATH=$(oc get argocd "$ARGO" -n "$ARGO_NS" -o jsonpath='{range .spec.repo.volumeMounts[?(@.name=="cluster-root-ca-bundle")]}{.subPath}{"\n"}{end}' 2>/dev/null | head -1)

  if [[ "$VOL_CM" == "cluster-root-ca-bundle" && "$MOUNT_PATH" == "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem" && "$SUB_PATH" == "ca-bundle.crt" ]]; then
    pass 13 "Argo CD repo-server mounts cluster-root-ca-bundle at the required trust-store path with subPath ca-bundle.crt"
  else
    fail 13 "Argo CD spec.repo volume/volumeMount is incorrect"
    echo "         volume ConfigMap: ${VOL_CM:-<unset>}"
    echo "         mountPath:        ${MOUNT_PATH:-<unset>}"
    echo "         subPath:          ${SUB_PATH:-<unset>}"
  fi
fi

echo "-------------------------------------"
printf 'SCORE: %d/100\n' "$SCORE"
if [[ "$SCORE" -ge 80 ]]; then
  echo "RESULT: PASS"
else
  echo "RESULT: NO PASS"
fi
printf 'Checks passed: %d   failed: %d\n' "$PASS_COUNT" "$FAIL_COUNT"
