#!/bin/bash
IP=$(kubectl -n legacy get svc legacy-svc -o jsonpath='{.spec.clusterIP}')
curl -s --max-time 3 "http://$IP" | grep -q "hello from legacy-app"
