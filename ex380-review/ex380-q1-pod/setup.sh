#!/bin/bash
set -e

API="https://api.ocp4.example.com:6443"
OCP_USER="admin"
PASSWORD="redhatocp"

echo "=== EX380 Q1 SETUP ==="

echo "==> Login"
oc login "$API" \
  -u "$OCP_USER" \
  -p "$PASSWORD" \
  --insecure-skip-tls-verify=true

echo
echo "==> Protecting control-plane nodes"
for NODE in master01 master02 master03
do
  # Remove the same taint first so setup is repeatable.
  oc adm taint nodes "$NODE" \
    node-role.kubernetes.io/control-plane- \
    2>/dev/null || true

  # Normal application workloads must not run on masters.
  oc adm taint nodes "$NODE" \
    node-role.kubernetes.io/control-plane:NoSchedule
done

echo
echo "==> Injecting scheduling fault on worker nodes"
for NODE in worker01 worker02 worker03
do
  oc adm taint nodes "$NODE" \
    ex380-scheduling- \
    2>/dev/null || true

  oc adm taint nodes "$NODE" \
    ex380-scheduling=blocked:NoSchedule
done

echo
echo "==> Cleaning old test projects"
oc delete project ex380-q1-test \
  --ignore-not-found --wait=false 2>/dev/null || true

oc delete project q1-ruby-test \
  --ignore-not-found --wait=false 2>/dev/null || true

oc delete project ex380-q1-grade \
  --ignore-not-found --wait=false 2>/dev/null || true

echo
echo "==> Resulting node taints"
for NODE in master01 master02 master03 worker01 worker02 worker03
do
  printf "%-10s : " "$NODE"
  oc get node "$NODE" \
    -o jsonpath='{range .spec.taints[*]}{.key}{"="}{.value}{":"}{.effect}{" "}{end}{"\n"}'
done

echo
echo "SETUP COMPLETE"
echo
echo "Expected broken state:"
echo "  master01-03 -> node-role.kubernetes.io/control-plane:NoSchedule"
echo "  worker01-03 -> ex380-scheduling=blocked:NoSchedule"
echo
echo "An ordinary application pod should now remain Pending."
