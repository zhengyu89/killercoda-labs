## Task 2: Expose a Deployment

1. Expose Deployment `web` in the `shop` namespace as a Service named `web-nodeport`.
2. The Service type must be `NodePort`.
3. The Service must listen on port `80` and forward to the container port `8080`.
4. Let Kubernetes choose the `nodePort`.

```plain
kubectl -n shop get svc web-nodeport
```{{exec}}

<details><summary>Solution</summary>

`kubectl expose` copies the selector from the Deployment, so the labels always match:

```plain
kubectl -n shop expose deployment web --name=web-nodeport --type=NodePort --port=80 --target-port=8080
```{{exec}}

</details>
