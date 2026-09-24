# EX380 Q1 — Troubleshooting Pod Scheduling v6

This pack is built for the RHLS classroom topology:

    master01
    master02
    master03
    worker01
    worker02
    worker03

## Intended exam state

Masters are protected with:

    node-role.kubernetes.io/control-plane:NoSchedule

Workers receive the accidental fault:

    ex380-scheduling=blocked:NoSchedule

Therefore normal application pods cannot run until the worker fault is corrected.

## Commands

Prepare exam state:

    ./setup.sh

Grade:

    ./grade.sh

Restore broken state:

    ./reset.sh

Optional Ruby application test:

    ./test-ruby.sh

Reference repair:

    ./instructor/solution.sh

## Correct student repair

Only remove the worker fault:

    oc adm taint nodes worker01 ex380-scheduling-
    oc adm taint nodes worker02 ex380-scheduling-
    oc adm taint nodes worker03 ex380-scheduling-

Do not remove the control-plane `NoSchedule` taint from the masters.
