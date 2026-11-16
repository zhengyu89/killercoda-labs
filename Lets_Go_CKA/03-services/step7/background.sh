#!/bin/bash
kubectl create namespace legacy
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: legacy-app
  namespace: legacy
  labels:
    role: legacy
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "mkdir -p /www && echo \"hello from $(hostname)\" > /www/index.html && exec httpd -f -p 8080 -h /www"]
    ports:
    - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: legacy-svc
  namespace: legacy
spec:
  ports:
  - name: http
    port: 80
YAML
