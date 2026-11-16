#!/bin/bash
kubectl create namespace backend
kubectl create namespace frontend
kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
      - name: api
        image: busybox:1.36
        command: ["sh", "-c", "mkdir -p /www && echo \"hello from $(hostname)\" > /www/index.html && exec httpd -f -p 8080 -h /www"]
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: backend
spec:
  selector:
    app: api
  ports:
  - port: 80
    targetPort: 8080
---
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: frontend
spec:
  containers:
  - name: client
    image: busybox:1.36
    command: ["sleep", "86400"]
YAML
