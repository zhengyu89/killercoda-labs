#!/bin/bash
S="kubectl -n shop get svc web-svc -o jsonpath"
[ "$($S='{.spec.type}')" = "ClusterIP" ] &&
[ "$($S='{.spec.ports[0].port}')" = "80" ] &&
[ "$($S='{.spec.ports[0].targetPort}')" = "8080" ] &&
[ -n "$(kubectl -n shop get endpointslice -l kubernetes.io/service-name=web-svc -o jsonpath='{.items[*].endpoints[*].addresses[0]}')" ]
