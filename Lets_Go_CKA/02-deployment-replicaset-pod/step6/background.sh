#!/bin/bash
# distroless/static has no ENTRYPOINT and no CMD, and the spec sets no command,
# so the runtime refuses to create the container: "no command specified".
kubectl create namespace tools
kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: toolbox
  namespace: tools
spec:
  replicas: 1
  selector:
    matchLabels:
      app: toolbox
  template:
    metadata:
      labels:
        app: toolbox
    spec:
      containers:
      - name: toolbox
        image: gcr.io/distroless/static-debian12
YAML
