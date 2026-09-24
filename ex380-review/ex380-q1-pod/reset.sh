#!/bin/bash
set -e

API="https://api.ocp4.example.com:6443"
OCP_USER="admin"
PASSWORD="redhatocp"

echo "=== EX380 Q1 RESET ==="

oc login "$API" \
  -u "$OCP_USER" \
  -p "$PASSWORD" \
  --insecure-skip-tls-verify=true >/dev/null

echo "==> Restoring control-plane protection"
for NODE in master01 master02 master03
do
  oc adm taint nodes "$NODE" \
    node-role.kubernetes.io/control-plane- \
    2>/dev/null || true

  oc adm taint nodes "$NODE" \
    node-role.kubernetes.io/control-plane:NoSchedule
done

echo "==> Restoring worker scheduling fault"
for NODE in worker01 worker02 worker03
do
  oc adm taint nodes "$NODE" \
    ex380-scheduling- \
    2>/dev/null || true

  oc adm taint nodes "$NODE" \
    ex380-scheduling=blocked:NoSchedule
done

oc delete project ex380-q1-test \
  --ignore-not-found --wait=false 2>/dev/null || true

oc delete project q1-ruby-test \
  --ignore-not-found --wait=false 2>/dev/null || true

oc delete project ex380-q1-grade \
  --ignore-not-found --wait=false 2>/dev/null || true

echo "RESET COMPLETE"
