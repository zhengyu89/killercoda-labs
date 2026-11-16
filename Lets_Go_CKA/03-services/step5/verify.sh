#!/bin/bash
[ "$(kubectl -n shop get svc web-headless -o jsonpath='{.spec.clusterIP}')" = "None" ] &&
[ -n "$(kubectl -n shop get endpointslice -l kubernetes.io/service-name=web-headless -o jsonpath='{.items[*].endpoints[*].addresses[0]}')" ]
