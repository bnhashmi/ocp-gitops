#!/bin/bash
set -e

API="https://api.ocp4.example.com:6443"

oc login "$API" \
  -u admin \
  -p redhatocp \
  --insecure-skip-tls-verify=true >/dev/null

echo "Removing only the accidental worker taints..."

for NODE in worker01 worker02 worker03
do
  oc adm taint nodes "$NODE" ex380-scheduling-
done

echo
echo "Do NOT remove:"
echo "  node-role.kubernetes.io/control-plane:NoSchedule"
echo
echo "Current node taints:"
for NODE in master01 master02 master03 worker01 worker02 worker03
do
  printf "%-10s : " "$NODE"
  oc get node "$NODE" \
    -o jsonpath='{range .spec.taints[*]}{.key}{"="}{.value}{":"}{.effect}{" "}{end}{"\n"}'
done
