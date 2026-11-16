## Task 5: Headless Service

1. Create a headless Service named `web-headless` in the `shop` namespace.
2. The Service must select the Pods of Deployment `web`, on port `8080`.

A headless Service has no ClusterIP. A DNS lookup of its name returns the Pod IPs directly:

```plain
kubectl -n shop get svc web-headless
kubectl -n shop run dns-test --rm -it --restart=Never --image=busybox:1.36 -- nslookup web-headless
```{{exec}}

<details><summary>Solution</summary>

```plain
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: web-headless
  namespace: shop
spec:
  clusterIP: None
  selector:
    app: web
  ports:
  - port: 8080
    targetPort: 8080
YAML
```{{exec}}

Compare with `nslookup web-svc`, which returns a single ClusterIP.

</details>
