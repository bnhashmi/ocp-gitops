# Instructor notes

## Broken state created by setup.sh

Control-plane nodes:

    master01
    master02
    master03

must retain:

    node-role.kubernetes.io/control-plane:NoSchedule

Worker nodes:

    worker01
    worker02
    worker03

receive the accidental exam fault:

    ex380-scheduling=blocked:NoSchedule

This makes ordinary application workloads unable to run on the workers,
while the control-plane nodes remain protected from normal workloads.

## Expected diagnosis

Useful commands:

    oc get nodes

    oc describe node worker01

    oc get node worker01 \
      -o jsonpath='{.spec.taints}{"\n"}'

    oc get node master01 \
      -o jsonpath='{.spec.taints}{"\n"}'

A normal application pod should remain Pending while the worker fault exists.

## Correct repair

Remove only the accidental worker taint:

    oc adm taint nodes worker01 ex380-scheduling-
    oc adm taint nodes worker02 ex380-scheduling-
    oc adm taint nodes worker03 ex380-scheduling-

Do NOT remove:

    node-role.kubernetes.io/control-plane:NoSchedule

from the masters.

## Optional Ruby S2I test

    oc new-project q1-ruby-test

    oc new-app \
      openshift/ruby:25~https://github.com/sclorg/ruby-ex \
      --name=ruby-ex \
      -n q1-ruby-test

Then:

    oc get builds,pods -n q1-ruby-test -o wide

    oc get events -n q1-ruby-test \
      --sort-by=.lastTimestamp
