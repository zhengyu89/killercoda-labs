#!/bin/bash
[ "$(kubectl -n workloads get pod web-pod -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" = "True" ] &&
[ "$(kubectl -n workloads get deploy web-deploy -o jsonpath='{.status.readyReplicas}')" = "2" ]
