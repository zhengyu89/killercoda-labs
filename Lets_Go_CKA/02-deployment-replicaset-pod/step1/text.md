## Task 1: Pod and Deployment

Create the following resources in the `workloads` namespace:

1. A Pod named `web-pod` using image `nginx:1.27-alpine`.
2. A Deployment named `web-deploy` using image `nginx:1.27-alpine` with `2` replicas.

Both must be Running and Ready. Verify with:

```plain
kubectl -n workloads get pod web-pod
kubectl -n workloads get deploy web-deploy
```{{exec}}

<details><summary>Solution</summary>

```plain
kubectl -n workloads run web-pod --image=nginx:1.27-alpine
kubectl -n workloads create deployment web-deploy --image=nginx:1.27-alpine --replicas=2
```{{exec}}

</details>
