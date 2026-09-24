# Q5: Configure LOG Forwarding

Configure the `openshift-logging` project in your OpenShift cluster to forward logs to an external aggregator according to the following specifications:

- The log collector type is **Vector**.
- **Application** and **infrastructure** logs are forwarded to the syslog service on host `utility.lab.example.com`.
- **Audit** logs are forwarded to the syslog service on host `utility.lab.example.com`.
- The syslog service listens on **TCP/514** and **UDP/514**.
- Application logs are tagged with `procID: app`.
- Infrastructure logs are tagged with `procID: infra`.
- Audit logs are tagged with `procID: audit`.
- All logs are tagged with `appName: openshift`.

The Event Router must be running using the registry image:

`registry.ocp4.example.com:8443/openshift-logging/eventrouter-rhel9:v0.4`

The syslog server is already configured to filter messages using the `procID` attribute into:

- `/var/log/ex380-app.log`
- `/var/log/ex380-infra.log`
- `/var/log/ex380-audit.log`

The OpenShift API is:

`https://api.ocp4.example.com:6443`

Do not modify the syslog server configuration.
