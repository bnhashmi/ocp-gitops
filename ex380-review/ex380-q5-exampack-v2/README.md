# EX380 Q5 Practice Exam Pack — OCP 4.18 / OpenShift Logging 6.4

This pack reproduces the EX380-style log-forwarding task for the Red Hat Learning Environment described by the lab owner.

## Environment

- API: `https://api.ocp4.example.com:6443`
- Admin user: `admin`
- Admin password: `redhatocp`
- OpenShift: 4.18
- Logging package: `cluster-logging`
- CatalogSource: auto-detected from PackageManifest (expected `gls-catalog-cs`)
- Channel: auto-detected (expected `stable-6.4`)
- Namespace: `openshift-logging`
- Syslog host: `utility.lab.example.com`
- Syslog SSH user: `root`
- EventRouter image: `registry.ocp4.example.com:8443/openshift-logging/eventrouter-rhel9:v0.4`

## Files

- `setup.sh` — prepares/reset the exam starting state, discovers the custom catalog, ensures Logging 6.4 is installed, and prepares collector RBAC.
- `grade.sh` — grades the candidate configuration semantically.
- `runtime-check.sh` — optional end-to-end checks against the real syslog files on utility.
- `reset.sh` — removes candidate-created Q5 resources but leaves the Logging operator installed.
- `student/QUESTION.md` — candidate question only.
- `instructor/solution-clf.yaml` — reference ClusterLogForwarder.
- `instructor/eventrouter-template.yaml` — reference EventRouter template.
- `instructor/solution.sh` — applies the complete reference solution.

## Typical use

```bash
./setup.sh
cat student/QUESTION.md
# candidate solves the task
./grade.sh
./runtime-check.sh
```

To restore the Q5 starting state:

```bash
./reset.sh
```

To validate the pack with the reference answer:

```bash
./setup.sh
./instructor/solution.sh
./grade.sh
./runtime-check.sh
```

The grader accepts either TCP or UDP on port 514 because the task states the syslog service listens on both.
