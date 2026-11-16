## Task 1: ClusterIP Service

A Deployment named `web` is running in the `shop` namespace. Its Pods have the label `app: web` and listen on port `8080`.

1. Create a Service named `web-svc` of type `ClusterIP` in the `shop` namespace.
2. The Service must select the Pods of Deployment `web`.
3. The Service must listen on port `80` and forward to the container port `8080`.

Verify that the Service has endpoints:

```plain
kubectl -n shop get svc web-svc
kubectl -n shop get endpointslice -l kubernetes.io/service-name=web-svc
```{{exec}}

<details><summary>Solution</summary>

```plain
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: web-svc
  namespace: shop
spec:
  type: ClusterIP
  selector:
    app: web
  ports:
  - port: 80
    targetPort: 8080
YAML
```{{exec}}

`port` is what clients connect to on the Service. `targetPort` is where the traffic goes on the Pod.

> `kubectl create service clusterip web-svc --tcp=80:8080` sets the selector to `app: web-svc`, which matches no Pods, so the Service gets no endpoints. Labels are how a Service finds its Pods.

</details>
