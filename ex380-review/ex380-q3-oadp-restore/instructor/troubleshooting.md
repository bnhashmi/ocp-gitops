# Q3 Instructor Troubleshooting

## Operator

    oc get sub,csv -n openshift-adp
    oc get pods -n openshift-adp

## DPA

    oc get dpa -n openshift-adp
    oc describe dpa dpa -n openshift-adp

Expected:

    Reconciled=True

## ObjectBucketClaim

    oc get obc -n openshift-adp
    oc get cm backup-oadp -n openshift-adp -o yaml
    oc get secret backup-oadp -n openshift-adp -o yaml

## BackupStorageLocation

    oc get backupstoragelocations.velero.io -n openshift-adp

Expected:

    Available

## Schedule

    oc get schedules.velero.io -n openshift-adp

## Backups from the schedule

    oc get backups.velero.io \
      -n openshift-adp \
      -l velero.io/schedule-name=lynx-web-schedule

The pack pauses the schedule after a successful backup so that deleting
the application does not create a newer empty backup.

## Find latest Completed backup

    oc get backups.velero.io \
      -n openshift-adp \
      -l velero.io/schedule-name=lynx-web-schedule \
      -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,COMPLETED:.status.completionTimestamp

## Restore

    apiVersion: velero.io/v1
    kind: Restore
    metadata:
      name: restore-lynx-web
      namespace: openshift-adp
    spec:
      backupName: <LATEST-COMPLETED-BACKUP>

## Watch restore

    oc get restore restore-lynx-web -n openshift-adp -w

## Test

    curl -k \
      -u 'admin:Admin1andia!1958' \
      https://lynx.apps.ocp4.example.com
