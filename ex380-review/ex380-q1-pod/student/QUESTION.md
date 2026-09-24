# Q1 — Troubleshooting POD Scheduling

A work colleague accidentally misconfigured your OpenShift cluster prior to leaving on vacation.

As a result, application pods are not able to run.

Diagnose and correct the problem so that application pods are able to run on any worker node.

You may use:

    quay.io/openshifttest/hello-openshift:1.2.0

to verify your work.

The image must deploy into a Running container without intervention.

Optional additional application test:

    oc new-app openshift/ruby:25~https://github.com/sclorg/ruby-ex
