# EX380 Q3 — OADP Restore Exam Pack v2

This pack prepares the COMPLETE exam scenario.

Target cluster:

    API: https://api.ocp4.example.com:6443
    Admin: admin
    Password: redhatocp

Application:

    https://lynx.apps.ocp4.example.com
    Username: admin
    Password: Admin1andia!1958

OADP namespace:

    openshift-adp

## What setup.sh does

1. Logs in to the cluster.
2. Auto-detects the classroom CatalogSource and OADP channel.
3. Installs the Red Hat OADP operator in `openshift-adp`.
4. Provisions an ObjectBucketClaim using NooBaa-compatible object storage.
5. Builds the S3 credentials secret.
6. Creates a DataProtectionApplication.
7. Waits until OADP and its BackupStorageLocation are functional.
8. Deploys the Lynx HTTPS application.
9. Verifies `admin/Admin1andia!1958` returns HTTP 200.
10. Creates a Velero Schedule.
11. Waits for a REAL scheduled backup to reach `Completed`.
12. Pauses the schedule so no newer empty backup can appear.
13. Deletes the `lynx-web` project.

At that point, the student's exam question begins.

## Workflow

Prepare the exam:

    ./setup.sh

Student solves Q3.

Grade:

    ./grade.sh

Test only the restored application:

    ./test-app.sh

Reset the scenario while keeping the already-installed operator:

    ./reset.sh

Instructor reference restore:

    ./instructor/solution.sh

Inspect environment prerequisites:

    ./precheck.sh

Full cleanup, including OADP operator and backup storage:

    ./full-clean.sh
