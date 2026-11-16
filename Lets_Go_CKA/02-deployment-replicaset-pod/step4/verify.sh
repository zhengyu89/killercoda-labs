#!/bin/bash
NS=batch
D=worker
[ "$(kubectl -n $NS get deploy $D -o jsonpath='{.status.availableReplicas}')" -ge 1 ] 2>/dev/null &&
[ -z "$(kubectl -n $NS get deploy $D -o jsonpath='{.status.unavailableReplicas}')" ]
