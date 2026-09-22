#!/bin/bash
set -e

USER="cluster-admin"
PASSWORD="redhatocp"
IDP_NAME="local-htpasswd"
SECRET_NAME="htpass-secret"
NS="openshift-config"

echo "==> Backing up existing OAuth configuration"
oc get oauth cluster -o yaml > /tmp/oauth-cluster-backup.yaml

echo "==> Creating HTPasswd file"
rm -f /tmp/users.htpasswd
htpasswd -c -B -b /tmp/users.htpasswd "$USER" "$PASSWORD"

echo "==> Creating/updating HTPasswd secret"
oc create secret generic "$SECRET_NAME" \
  --from-file=htpasswd=/tmp/users.htpasswd \
  -n "$NS" \
  --dry-run=client -o yaml | oc apply -f -

echo "==> Checking whether IDP already exists"
if oc get oauth cluster -o json | \
   jq -e --arg NAME "$IDP_NAME" \
   '.spec.identityProviders[]? | select(.name == $NAME)' >/dev/null; then

    echo "IDP $IDP_NAME already exists. Not adding duplicate."

else

    COUNT=$(oc get oauth cluster \
      -o jsonpath='{.spec.identityProviders}' 2>/dev/null | wc -c)

    if [ "$COUNT" -le 1 ]; then
        echo "==> No existing IDPs. Creating identityProviders list."

        oc patch oauth cluster --type=json -p='[
          {
            "op": "add",
            "path": "/spec/identityProviders",
            "value": [
              {
                "name": "'"$IDP_NAME"'",
                "mappingMethod": "claim",
                "type": "HTPasswd",
                "htpasswd": {
                  "fileData": {
                    "name": "'"$SECRET_NAME"'"
                  }
                }
              }
            ]
          }
        ]'

    else
        echo "==> Existing IDPs detected. Appending HTPasswd IDP."

        oc patch oauth cluster --type=json -p='[
          {
            "op": "add",
            "path": "/spec/identityProviders/-",
            "value": {
              "name": "'"$IDP_NAME"'",
              "mappingMethod": "claim",
              "type": "HTPasswd",
              "htpasswd": {
                "fileData": {
                  "name": "'"$SECRET_NAME"'"
                }
              }
            }
          }
        ]'
    fi
fi

echo "==> Granting cluster-admin privileges"
oc adm policy add-cluster-role-to-user cluster-admin "$USER"

echo "==> Waiting for authentication operator"
oc wait clusteroperator/authentication \
  --for=condition=Available=True \
  --timeout=300s

echo
echo "======================================"
echo "User:     $USER"
echo "Password: $PASSWORD"
echo "IDP:      $IDP_NAME"
echo "======================================"

echo
echo "Configured IDPs:"
oc get oauth cluster \
  -o jsonpath='{range .spec.identityProviders[*]}{.name}{"\t"}{.type}{"\n"}{end}'

echo
echo "Cluster-admin binding:"
oc adm policy who-can '*' '*' | grep -w "$USER" || true

echo
echo "OAuth backup:"
echo "/tmp/oauth-cluster-backup.yaml"
