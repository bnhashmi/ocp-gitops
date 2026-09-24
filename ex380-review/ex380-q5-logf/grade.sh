#!/usr/bin/env bash
set -uo pipefail

API="${API:-https://api.ocp4.example.com:6443}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-redhatocp}"
NS="${NS:-openshift-logging}"
SYSLOG_HOST="${SYSLOG_HOST:-utility.lab.example.com}"
EVENT_IMAGE="${EVENT_IMAGE:-registry.ocp4.example.com:8443/openshift-logging/eventrouter-rhel9:v0.4}"

TOTAL=0
MAX=100
PASS=0
FAIL=0

ok(){ local pts="$1"; shift; TOTAL=$((TOTAL+pts)); PASS=$((PASS+1)); printf '[PASS +%2d] %s\n' "$pts" "$*"; }
no(){ local pts="$1"; shift; FAIL=$((FAIL+1)); printf '[FAIL +%2d] %s\n' "$pts" "$*"; }
info(){ printf '[INFO] %s\n' "$*"; }

command -v oc >/dev/null || { echo "oc command not found" >&2; exit 2; }
command -v python3 >/dev/null || { echo "python3 command not found" >&2; exit 2; }

if ! oc login "$API" -u "$ADMIN_USER" -p "$ADMIN_PASS" --insecure-skip-tls-verify=true >/dev/null 2>&1; then
  echo "Unable to login to $API" >&2
  exit 2
fi

printf '\nEX380 Q5 grader — OpenShift Logging 6.4\n'
printf '========================================\n'
CATALOG=$(oc get packagemanifest cluster-logging -n openshift-marketplace -o jsonpath='{.status.catalogSource}' 2>/dev/null || true)
CHANNEL=$(oc get packagemanifest cluster-logging -n openshift-marketplace -o jsonpath='{.status.defaultChannel}' 2>/dev/null || true)
info "Detected catalog=${CATALOG:-unknown}, channel=${CHANNEL:-unknown}"

# 1) Operator / CRD readiness — 5 points
if oc get crd clusterlogforwarders.observability.openshift.io >/dev/null 2>&1; then
  ok 5 "Logging 6.4 ClusterLogForwarder API is available"
else
  no 5 "ClusterLogForwarder observability.openshift.io/v1 CRD is missing"
fi

# Obtain all CLFs.
CLF_JSON=$(mktemp)
oc get clusterlogforwarder.observability.openshift.io -n "$NS" -o json >"$CLF_JSON" 2>/dev/null || echo '{"items":[]}' >"$CLF_JSON"

# Semantic CLF checks. Output is key=value lines.
CLF_CHECK=$(python3 - "$CLF_JSON" "$SYSLOG_HOST" <<'PY'
import json, re, sys
path, host = sys.argv[1], sys.argv[2]
with open(path) as f:
    data=json.load(f)
items=data.get('items',[])
print('clf_exists=' + ('1' if items else '0'))
ready=False
for c in items:
    for cond in c.get('status',{}).get('conditions',[]) or []:
        if cond.get('type')=='Ready' and str(cond.get('status')).lower()=='true':
            ready=True
print('clf_ready=' + ('1' if ready else '0'))

want={'app':'application','infra':'infrastructure','audit':'audit'}
result={k:{'output':False,'route':False,'appname':False,'rfc':False} for k in want}
valid_url=re.compile(r'^(tcp|udp)://' + re.escape(host) + r':514$')
sa_names=[]
for c in items:
    spec=c.get('spec',{}) or {}
    sa=((spec.get('serviceAccount') or {}).get('name'))
    if sa: sa_names.append(sa)
    outputs=spec.get('outputs',[]) or []
    pipelines=spec.get('pipelines',[]) or []
    byname={o.get('name'):o for o in outputs if o.get('name')}
    for proc, input_name in want.items():
        candidates=[]
        for o in outputs:
            if o.get('type')!='syslog':
                continue
            s=o.get('syslog',{}) or {}
            if s.get('procId')==proc and valid_url.match(str(s.get('url',''))):
                result[proc]['output']=True
                result[proc]['appname']=(s.get('appName')=='openshift')
                result[proc]['rfc']=(s.get('rfc') in (None,'RFC5424'))
                candidates.append(o.get('name'))
        for p in pipelines:
            if input_name in (p.get('inputRefs',[]) or []) and any(n in (p.get('outputRefs',[]) or []) for n in candidates):
                result[proc]['route']=True
                break
print('serviceaccounts=' + ','.join(sorted(set(sa_names))))
for proc in ('app','infra','audit'):
    for k,v in result[proc].items():
        print(f'{proc}_{k}=' + ('1' if v else '0'))
PY
)
rm -f "$CLF_JSON"

getv(){ printf '%s\n' "$CLF_CHECK" | awk -F= -v k="$1" '$1==k{print substr($0,index($0,"=")+1)}'; }

if [[ "$(getv clf_exists)" == 1 ]]; then ok 5 "ClusterLogForwarder exists in $NS"; else no 5 "No ClusterLogForwarder exists in $NS"; fi
if [[ "$(getv clf_ready)" == 1 ]]; then ok 10 "ClusterLogForwarder reports Ready=True"; else no 10 "ClusterLogForwarder is not Ready=True"; fi

# 2) Three syslog outputs and routes — 45 points
for pair in "app:application" "infra:infrastructure" "audit:audit"; do
  proc=${pair%%:*}; input=${pair##*:}
  if [[ "$(getv ${proc}_output)" == 1 ]]; then ok 8 "$input output uses tcp/udp://${SYSLOG_HOST}:514 with procId=${proc}"; else no 8 "$input output missing/wrong host, port, protocol, or procId=${proc}"; fi
  if [[ "$(getv ${proc}_route)" == 1 ]]; then ok 4 "$input pipeline routes to the matching procId=${proc} syslog output"; else no 4 "$input pipeline is not routed to its matching syslog output"; fi
  if [[ "$(getv ${proc}_appname)" == 1 ]]; then ok 3 "$input syslog output has appName=openshift"; else no 3 "$input syslog output does not have appName=openshift"; fi
 done

# 3) Collector service account RBAC — 10 points
SA_LIST="$(getv serviceaccounts)"
if [[ -z "$SA_LIST" ]]; then
  no 10 "ClusterLogForwarder does not reference a service account"
else
  SA="${SA_LIST%%,*}"
  info "ClusterLogForwarder service account: ${SA}"
  rbac_ok=1
  CRB_JSON=$(mktemp)
  oc get clusterrolebinding -o json >"$CRB_JSON" 2>/dev/null || echo '{"items":[]}' >"$CRB_JSON"
  for role in collect-application-logs collect-infrastructure-logs collect-audit-logs; do
    if ! python3 - "$CRB_JSON" "$role" "$NS" "$SA" <<'PY'
import json,sys
path,role,ns,sa=sys.argv[1:]
with open(path) as f:
    d=json.load(f)
ok=False
for b in d.get('items',[]):
    rr=b.get('roleRef',{})
    if rr.get('kind')!='ClusterRole' or rr.get('name')!=role:
        continue
    for s in b.get('subjects',[]) or []:
        if s.get('kind')=='ServiceAccount' and s.get('namespace')==ns and s.get('name')==sa:
            ok=True
            break
    if ok:
        break
sys.exit(0 if ok else 1)
PY
    then
      rbac_ok=0
    fi
  done
  rm -f "$CRB_JSON"
  if [[ $rbac_ok -eq 1 ]]; then ok 10 "Collector service account is authorized for application, infrastructure, and audit logs"; else no 10 "Collector service account is missing one or more collect-* role bindings"; fi
fi

# 4) Vector collector — 5 points. Logging 6.4 uses Vector; verify managed collector daemonset is ready.
DS_JSON=$(mktemp)
oc get daemonset -n "$NS" -o json >"$DS_JSON" 2>/dev/null || echo '{"items":[]}' >"$DS_JSON"
if python3 - "$DS_JSON" <<'PY'
import json,sys
with open(sys.argv[1]) as f: d=json.load(f)
ok=False
for ds in d.get('items',[]):
    st=ds.get('status',{}) or {}
    desired=st.get('desiredNumberScheduled',0) or 0
    ready=st.get('numberReady',0) or 0
    text=json.dumps(ds).lower()
    if desired>0 and ready==desired and ('vector' in text or 'collector' in ds.get('metadata',{}).get('name','').lower()):
        ok=True; break
sys.exit(0 if ok else 1)
PY
then ok 5 "Vector/collector DaemonSet is present and ready"; else no 5 "No ready collector DaemonSet detected"; fi
rm -f "$DS_JSON"

# 5) EventRouter — 20 points
DEPLOY_JSON=$(mktemp)
oc get deploy -n "$NS" -o json >"$DEPLOY_JSON" 2>/dev/null || echo '{"items":[]}' >"$DEPLOY_JSON"
ER=$(python3 - "$DEPLOY_JSON" "$EVENT_IMAGE" <<'PY'
import json,sys
with open(sys.argv[1]) as f: d=json.load(f)
image=sys.argv[2]
for dep in d.get('items',[]):
    cs=((dep.get('spec',{}).get('template',{}).get('spec',{}).get('containers')) or [])
    if any(c.get('image')==image for c in cs):
        name=dep.get('metadata',{}).get('name','')
        ready=dep.get('status',{}).get('readyReplicas',0) or 0
        spec=dep.get('spec',{}).get('template',{}).get('spec',{}) or {}
        sa=spec.get('serviceAccountName') or spec.get('serviceAccount') or 'default'
        vols=spec.get('volumes',[]) or []
        cms={v.get('name'):((v.get('configMap') or {}).get('name')) for v in vols if v.get('configMap')}
        mounted=False; cmname=''
        for c in cs:
            if c.get('image')!=image: continue
            for m in c.get('volumeMounts',[]) or []:
                if m.get('mountPath')=='/etc/eventrouter' and m.get('name') in cms:
                    mounted=True; cmname=cms[m.get('name')] or ''
        print(f'name={name}')
        print(f'ready={ready}')
        print(f'sa={sa}')
        print('mounted=' + ('1' if mounted else '0'))
        print(f'cm={cmname}')
        sys.exit(0)
sys.exit(1)
PY
)
ER_RC=$?
rm -f "$DEPLOY_JSON"

erv(){ printf '%s\n' "$ER" | awk -F= -v k="$1" '$1==k{print substr($0,index($0,"=")+1)}'; }

if [[ $ER_RC -eq 0 ]]; then
  ER_NAME="$(erv name)"; ER_SA="$(erv sa)"; ER_CM="$(erv cm)"
  ok 5 "EventRouter Deployment uses the exact required v0.4 image"
  if [[ "$(erv ready)" =~ ^[1-9][0-9]*$ ]]; then ok 5 "EventRouter has at least one ready replica"; else no 5 "EventRouter Deployment is not ready"; fi
  if [[ "$(erv mounted)" == 1 && -n "$ER_CM" ]] && oc get cm "$ER_CM" -n "$NS" -o jsonpath='{.data.config\.json}' 2>/dev/null | grep -Eq '"sink"[[:space:]]*:[[:space:]]*"stdout"'; then
    ok 5 "EventRouter config.json is mounted at /etc/eventrouter with sink=stdout"
  else
    no 5 "EventRouter ConfigMap/mount/sink=stdout is incomplete"
  fi
  rb=1
  for verb in get list watch; do
    if [[ "$(oc auth can-i "$verb" events --all-namespaces --as="system:serviceaccount:${NS}:${ER_SA}" 2>/dev/null)" != yes ]]; then rb=0; fi
  done
  if [[ $rb -eq 1 ]]; then ok 5 "EventRouter service account can get/list/watch cluster Events"; else no 5 "EventRouter RBAC is incomplete"; fi
  info "EventRouter deployment: $ER_NAME; service account: $ER_SA"
else
  no 5 "No Deployment uses exact image $EVENT_IMAGE"
  no 5 "EventRouter ready replica check skipped"
  no 5 "EventRouter config mount check skipped"
  no 5 "EventRouter RBAC check skipped"
fi


# Optional real receiver visibility (informational, not scored because delivery can be asynchronous).
if ssh -o BatchMode=yes -o ConnectTimeout=3 root@utility.lab.example.com true >/dev/null 2>&1; then
  for f in /var/log/ex380-app.log /var/log/ex380-infra.log /var/log/ex380-audit.log; do
    lines=$(ssh root@utility.lab.example.com "test -f '$f' && wc -l < '$f' || echo 0" 2>/dev/null | tr -d '[:space:]')
    info "Receiver $f lines=${lines:-0}"
  done
else
  info "root SSH to utility.lab.example.com unavailable; receiver-file check skipped"
fi

printf '\n----------------------------------------\n' 
printf 'SCORE: %d/%d\n' "$TOTAL" "$MAX"
printf 'Checks passed: %d   failed: %d\n' "$PASS" "$FAIL"

if [[ $TOTAL -ge 80 ]]; then
  echo "RESULT: PASS (practice threshold 80%)"
  exit 0
else
  echo "RESULT: NO PASS (practice threshold 80%)"
  exit 1
fi
