# Q4: Deploy OpenShift GitOps Operator

Deploy the OpenShift GitOps operator according to the following requirements:

- The operator is installed in the `openshift-gitops-operator` project.
- The ArgoCD instance deployed by the operator has TLS enabled with **reencrypt** termination.
- The `cluster-admin` user is a member of the `gitops-admins` group.
- The `gitops-admins` group is the **only group** configured as `role:admin` with the Argo CD RBAC `policy` key.
- In the `openshift-gitops` project, a ConfigMap named `cluster-root-ca-bundle` requests injection of the cluster trusted CA bundle using the label `config.openshift.io/inject-trusted-cabundle=true`.
- The Argo CD repository server mounts that ConfigMap as volume `cluster-root-ca-bundle` at:

  `/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem`

  using the injected ConfigMap key `ca-bundle.crt` as the `subPath`.

Do not modify unrelated identity providers or cluster configuration.
