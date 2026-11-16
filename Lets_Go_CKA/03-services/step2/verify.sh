#!/bin/bash
S="kubectl -n shop get svc web-nodeport -o jsonpath"
[ "$($S='{.spec.type}')" = "NodePort" ] &&
[ "$($S='{.spec.ports[0].port}')" = "80" ] &&
[ "$($S='{.spec.ports[0].targetPort}')" = "8080" ] &&
[ -n "$(kubectl -n shop get endpointslice -l kubernetes.io/service-name=web-nodeport -o jsonpath='{.items[*].endpoints[*].addresses[0]}')" ]
