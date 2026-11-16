#!/bin/bash
P=$(kubectl -n shop get svc web-nodeport -o jsonpath='{.spec.ports[0].nodePort}')
[ -n "$P" ] && [ "$(tr -d '[:space:]' < /root/nodeport.txt)" = "$P" ]
