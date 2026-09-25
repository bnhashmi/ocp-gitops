#!/bin/bash
set -e

API="https://api.ocp4.example.com:6443"

echo "=== EX380 Q3 PRECHECK ==="

oc login "$API" \
  -u admin \
  -p redhatocp \
  --insecure-skip-tls-verify=true >/dev/null

echo
echo "CatalogSources:"
oc get catalogsource -n openshift-marketplace

echo
echo "OADP PackageManifest:"
oc get packagemanifest redhat-oadp-operator \
  -n openshift-marketplace \
  -o custom-columns=NAME:.metadata.name,CATALOG:.status.catalogSource,DEFAULT_CHANNEL:.status.defaultChannel

echo
echo "OADP channels:"
oc get packagemanifest redhat-oadp-operator \
  -n openshift-marketplace \
  -o jsonpath='{range .status.channels[*]}{.name}{" -> "}{.currentCSV}{"\n"}{end}'

echo
echo "StorageClasses:"
oc get storageclass

echo
echo "ObjectBucketClaim API:"
if oc api-resources | grep -q '^objectbucketclaims'; then
  echo "ObjectBucketClaim API is available."
else
  echo "WARNING: ObjectBucketClaim API is NOT available."
fi

echo
echo "Candidate NooBaa/ObjectBucket storage classes:"
oc get sc -o json | python3 -c '
import json,sys
o=json.load(sys.stdin)
for x in o.get("items",[]):
    name=x["metadata"]["name"]
    prov=x.get("provisioner","")
    if "noobaa" in name.lower() or "noobaa" in prov.lower() or "objectbucket" in prov.lower():
        print(name, prov)
'
