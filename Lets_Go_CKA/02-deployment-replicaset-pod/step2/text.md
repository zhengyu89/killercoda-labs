## Task 2: ReplicaSet

Create a ReplicaSet named `web-rs` in the `workloads` namespace:

1. `3` replicas, image `nginx:1.27-alpine`.
2. Use the label `app: web-rs` for both the selector and the Pod template.

All 3 Pods must be Running and Ready. Verify with:

```plain
kubectl -n workloads get rs web-rs
```{{exec}}

> There is no `kubectl create replicaset`. Write a manifest, or start from a Deployment with `--dry-run=client -o yaml` and change it.

<details><summary>Solution</summary>

```plain
kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: web-rs
  namespace: workloads
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web-rs
  template:
    metadata:
      labels:
        app: web-rs
    spec:
      containers:
      - name: nginx
        image: nginx:1.27-alpine
YAML
```{{exec}}

</details>
