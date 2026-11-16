#!/bin/bash
# minReadySeconds stops the crashing container from counting as available
# during the instant it is up before it exits.
kubectl create namespace batch
kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: worker
  namespace: batch
spec:
  replicas: 1
  minReadySeconds: 5
  selector:
    matchLabels:
      app: worker
  template:
    metadata:
      labels:
        app: worker
    spec:
      containers:
      - name: worker
        image: busybox:1.36
        command:
        - sh
        - -c
        - |
          if [ -z "$APP_MODE" ]; then
            echo "ERROR: environment variable APP_MODE is not set (expected: production)"
            exit 1
          fi
          echo "worker started in $APP_MODE mode"
          sleep 3600
YAML
