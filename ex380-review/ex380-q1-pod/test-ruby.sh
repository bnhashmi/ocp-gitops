#!/bin/bash
set -e

API="https://api.ocp4.example.com:6443"
NS="q1-ruby-test"

oc login "$API" \
  -u admin \
  -p redhatocp \
  --insecure-skip-tls-verify=true >/dev/null

oc delete project "$NS" --ignore-not-found --wait=false >/dev/null 2>&1 || true

for X in $(seq 1 60)
do
  oc get project "$NS" >/dev/null 2>&1 || break
  sleep 1
done

oc new-project "$NS"

oc new-app centos/ruby-25-centos7~https://github.com/sclorg/ruby-ex.git --name=ruby-ex

echo
echo "Watch the build and application:"
echo "  oc get builds,pods -n $NS -w"
echo
echo "Check scheduler events:"
echo "  oc get events -n $NS --sort-by=.lastTimestamp"
