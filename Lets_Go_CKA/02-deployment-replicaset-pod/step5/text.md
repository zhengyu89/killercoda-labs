## Task 4: ImagePullBackOff

A Deployment named `frontend` in the `web` namespace has a Pod stuck in `ImagePullBackOff`.

1. Find out why the image cannot be pulled.
2. Fix the Deployment so its Pod is Running and Ready.
3. The container must still run NGINX `1.27` (Alpine variant).

```plain
kubectl -n web get pods -l app=frontend
```{{exec}}

<details><summary>Hint</summary>

The image was never pulled, so the container never started and has no logs. Read the Events at the bottom of `kubectl describe pod` and look closely at the image name the kubelet is trying to pull.

</details>

<details><summary>Solution</summary>

The Pod events show which image the kubelet is trying to pull:

```plain
kubectl -n web describe pod -l app=frontend | grep -A10 Events
```{{exec}}

The tag `1.27-alpne` is a typo. Set the correct image:

```plain
kubectl -n web set image deploy/frontend nginx=nginx:1.27-alpine
kubectl -n web rollout status deploy/frontend
```{{exec}}

</details>
