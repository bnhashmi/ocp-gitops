#!/usr/bin/env bash
set -euo pipefail

API="${API:-https://api.ocp4.example.com:6443}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-redhatocp}"
NS="${NS:-openshift-logging}"
PKG="${PKG:-cluster-logging}"
EXPECTED_CHANNEL="${CHANNEL:-stable-6.4}"
COLLECTOR_SA="${COLLECTOR_SA:-logcollector}"
SYSLOG_HOST="${SYSLOG_HOST:-utility.lab.example.com}"
SYSLOG_SSH_USER="${SYSLOG_SSH_USER:-root}"

say(){ printf '\n==> %s\n' "$*"; }
warn(){ printf 'WARNING: %s\n' "$*" >&2; }

command -v oc >/dev/null || { echo "oc command not found" >&2; exit 1; }

say "Logging in to ${API}"
oc login "$API" -u "$ADMIN_USER" -p "$ADMIN_PASS" --insecure-skip-tls-verify=true >/dev/null

VERSION=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || true)
echo "OpenShift version: ${VERSION:-unknown}"
[[ "$VERSION" == 4.18.* ]] || warn "Pack targets OCP 4.18; detected ${VERSION:-unknown}"

say "Discovering classroom CatalogSource and Logging channel"
CATALOG=$(oc get packagemanifest "$PKG" -n openshift-marketplace -o jsonpath='{.status.catalogSource}' 2>/dev/null || true)
DEFAULT_CHANNEL=$(oc get packagemanifest "$PKG" -n openshift-marketplace -o jsonpath='{.status.defaultChannel}' 2>/dev/null || true)
if [[ -z "$CATALOG" ]]; then
  echo "Unable to discover CatalogSource for package $PKG" >&2
  echo "Available catalogs:" >&2
  oc get catalogsource -n openshift-marketplace >&2 || true
  exit 1
fi
CHANNEL="$EXPECTED_CHANNEL"
if ! oc get packagemanifest "$PKG" -n openshift-marketplace -o jsonpath='{range .status.channels[*]}{.name}{"\n"}{end}' | grep -qx "$CHANNEL"; then
  warn "Requested channel $CHANNEL not found; using default ${DEFAULT_CHANNEL}"
  CHANNEL="$DEFAULT_CHANNEL"
fi
printf 'CatalogSource : %s\nChannel       : %s\n' "$CATALOG" "$CHANNEL"

say "Ensuring namespace and Logging operator are present"
oc create ns "$NS" --dry-run=client -o yaml | oc apply -f - >/dev/null
oc label ns "$NS" openshift.io/cluster-monitoring=true --overwrite >/dev/null

cat <<YAML | oc apply -f - >/dev/null
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: cluster-logging
  namespace: ${NS}
spec:
  upgradeStrategy: Default
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: cluster-logging
  namespace: ${NS}
spec:
  channel: ${CHANNEL}
  installPlanApproval: Automatic
  name: ${PKG}
  source: ${CATALOG}
  sourceNamespace: openshift-marketplace
YAML

say "Waiting for Logging 6.4 ClusterLogForwarder API"
for i in {1..120}; do
  if oc get crd clusterlogforwarders.observability.openshift.io >/dev/null 2>&1; then
    break
  fi
  [[ $i -eq 120 ]] && { echo "Timed out waiting for Logging CRD" >&2; exit 1; }
  sleep 3
done

say "Waiting for collector RBAC roles"
for i in {1..120}; do
  ok=1
  for role in collect-application-logs collect-infrastructure-logs collect-audit-logs; do
    oc get clusterrole "$role" >/dev/null 2>&1 || ok=0
  done
  [[ $ok -eq 1 ]] && break
  [[ $i -eq 120 ]] && { echo "Timed out waiting for collect-* ClusterRoles" >&2; exit 1; }
  sleep 3
done

say "Preparing the pre-existing collector service account"
oc create sa "$COLLECTOR_SA" -n "$NS" --dry-run=client -o yaml | oc apply -f - >/dev/null
for role in collect-application-logs collect-infrastructure-logs collect-audit-logs; do
  oc adm policy add-cluster-role-to-user "$role" "system:serviceaccount:${NS}:${COLLECTOR_SA}" >/dev/null
 done

say "Removing candidate Q5 resources"
oc delete clusterlogforwarder.observability.openshift.io --all -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
oc delete deployment eventrouter -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
oc delete configmap eventrouter -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
oc delete serviceaccount eventrouter -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
oc delete clusterrolebinding event-reader-binding --ignore-not-found >/dev/null 2>&1 || true
oc delete clusterrole event-reader --ignore-not-found >/dev/null 2>&1 || true

say "Checking syslog host"
getent hosts "$SYSLOG_HOST" | head -1 || warn "DNS lookup failed for $SYSLOG_HOST"
if command -v nc >/dev/null 2>&1; then
  nc -z -w2 "$SYSLOG_HOST" 514 >/dev/null 2>&1 && echo "TCP/514 reachable" || warn "TCP/514 not reachable"
fi

say "Resetting remote grading log files when root SSH is available"
if ssh -o BatchMode=yes -o ConnectTimeout=4 "${SYSLOG_SSH_USER}@${SYSLOG_HOST}" true >/dev/null 2>&1; then
  ssh "${SYSLOG_SSH_USER}@${SYSLOG_HOST}" \
    'for f in /var/log/ex380-app.log /var/log/ex380-infra.log /var/log/ex380-audit.log; do : > "$f"; done' || true
  echo "Remote log files truncated."
else
  warn "Passwordless SSH to ${SYSLOG_SSH_USER}@${SYSLOG_HOST} is unavailable; remote files were not reset."
fi

say "Exam state ready"
echo "API            : $API"
echo "CatalogSource  : $CATALOG"
echo "Logging channel: $CHANNEL"
echo "Namespace      : $NS"
echo "Collector SA   : $COLLECTOR_SA"
echo "Syslog         : $SYSLOG_HOST:514"
echo
printf 'Candidate task: %s\n' "student/QUESTION.md"
