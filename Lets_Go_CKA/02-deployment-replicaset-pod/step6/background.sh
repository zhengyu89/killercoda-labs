#!/bin/bash
kubectl create namespace ops
kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: reporter
  namespace: ops
spec:
  replicas: 1
  minReadySeconds: 5
  selector:
    matchLabels:
      app: reporter
  template:
    metadata:
      labels:
        app: reporter
    spec:
      containers:
      - name: reporter
        image: busybox:1.36
        command: ["/bash", "echo reporter started; sleep 3600"]
YAML
