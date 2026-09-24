#!/bin/bash
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=common.sh
source "$DIR/common.sh"

login_cluster

echo "==> Connected to $(oc whoami --show-server) as $(oc whoami)"

echo "==> Checking GitOps package in the learning catalog"
CATALOG=$(discover_catalog || true)
CHANNEL=$(discover_channel || true)
if [[ -z "$CATALOG" || -z "$CHANNEL" ]]; then
  echo "ERROR: PackageManifest '$PACKAGE' is not available in $MARKETPLACE_NS." >&2
  echo "Available catalog sources:" >&2
  oc get catalogsource -n "$MARKETPLACE_NS" >&2 || true
  exit 1
fi
printf '    CatalogSource: %s\n    Default channel: %s\n' "$CATALOG" "$CHANNEL"

cat > /tmp/ex380-q4-env <<ENV
CATALOG=$CATALOG
CHANNEL=$CHANNEL
ENV

echo "==> Removing previous Q4 GitOps installation, if present"
# Remove any Subscription for this package, regardless of namespace.
while IFS='|' read -r ns name csv; do
  [[ -z "$ns" || -z "$name" ]] && continue
  echo "    Deleting Subscription $ns/$name"
  oc delete subscription "$name" -n "$ns" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  if [[ -n "$csv" ]]; then
    echo "    Deleting CSV $ns/$csv"
    oc delete csv "$csv" -n "$ns" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  fi
done < <(oc get subscription -A -o jsonpath='{range .items[?(@.spec.name=="openshift-gitops-operator")]}{.metadata.namespace}{"|"}{.metadata.name}{"|"}{.status.installedCSV}{"\n"}{end}' 2>/dev/null || true)

# Delete the two namespaces created/used by this exercise.
for ns in "$ARGO_NS" "$OPERATOR_NS"; do
  if oc get ns "$ns" >/dev/null 2>&1; then
    echo "    Deleting namespace $ns"
    oc delete ns "$ns" --wait=false >/dev/null 2>&1 || true
  fi
done
for ns in "$ARGO_NS" "$OPERATOR_NS"; do
  wait_namespace_deleted "$ns" || true
done

# Remove the exercise group.
oc delete group "$GROUP_NAME" --ignore-not-found >/dev/null 2>&1 || true

echo
printf '%s\n' "Q4 environment is ready." \
  "Student must install GitOps Operator and configure Argo CD." \
  "CatalogSource available: $CATALOG" \
  "Channel available:       $CHANNEL"
