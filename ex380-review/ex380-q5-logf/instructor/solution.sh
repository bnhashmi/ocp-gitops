#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
oc apply -f "$HERE/solution-clf.yaml"
oc process -f "$HERE/eventrouter-template.yaml" | oc apply -f -
echo "Reference solution applied."
