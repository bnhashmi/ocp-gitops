# EX380 Q4 Exam Pack — OpenShift GitOps Operator / Argo CD RBAC / Trusted CA

This pack prepares and grades **only Q4**:

- Install Red Hat OpenShift GitOps Operator in `openshift-gitops-operator`.
- Ensure the default Argo CD instance uses a Route with **reencrypt** TLS termination.
- Add user `cluster-admin` to group `gitops-admins`.
- Configure Argo CD RBAC so `gitops-admins` is the **only group** mapped to `role:admin`, using the RBAC policy and group scope.
- Create `cluster-root-ca-bundle` in `openshift-gitops`, request cluster trusted CA injection, and mount it into the Argo CD repository server at `/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem` using `subPath: ca-bundle.crt`.

The MachineConfig/Git repository application task is intentionally **not included**; it belongs to Q5.

## Lab defaults

- API: `https://api.ocp4.example.com:6443`
- Setup/grading login: `admin`
- Password: `redhatocp`
- Marketplace namespace: `openshift-marketplace`
- Operator namespace required by the question: `openshift-gitops-operator`
- Default Argo CD namespace: `openshift-gitops`

The pack **does not hard-code the CatalogSource or channel**. It discovers them from the `openshift-gitops-operator` PackageManifest so it works with a GLS/custom classroom catalog.

## Workflow

```bash
unzip ex380-q4-gitops-exampack-v2.zip
cd ex380-q4-gitops-exampack-v2

./setup.sh
cat student/QUESTION.md
# Solve the task
./grade.sh
```

To validate the pack using the instructor solution:

```bash
./setup.sh
./instructor/solution.sh
./grade.sh
```

To return the cluster to the Q4 starting state:

```bash
./reset.sh
```

## Scoring

`grade.sh` scores 100 points:

- 20 — GitOps Operator installed in the required namespace and CSV succeeded
- 20 — Argo CD server Route exists and uses `reencrypt`
- 15 — `cluster-admin` belongs to `gitops-admins`
- 25 — Argo CD RBAC has group scope and only `gitops-admins` is mapped to `role:admin`
- 20 — trusted CA ConfigMap injection and Argo CD repo-server volume/volumeMount are correct

Passing score in this practice pack: **80/100**.

## Important CA detail

The OpenShift trusted CA injector writes the bundle under the ConfigMap key:

```text
ca-bundle.crt
```

Therefore the correct Argo CD repo-server mount uses:

```yaml
subPath: ca-bundle.crt
```

not `ca-bundle-crt`.
