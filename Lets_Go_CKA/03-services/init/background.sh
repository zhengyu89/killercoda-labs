#!/bin/bash
kubectl create namespace shop
kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: shop
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: web
        image: busybox:1.36
        command: ["sh", "-c", "mkdir -p /www && echo \"hello from $(hostname)\" > /www/index.html && exec httpd -f -p 8080 -h /www"]
        ports:
        - containerPort: 8080
YAML
