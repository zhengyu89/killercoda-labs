## Task 3: CrashLoopBackOff

A Deployment named `worker` in the `batch` namespace is running, but its Pod is in `CrashLoopBackOff`.

1. Find out why the container keeps exiting.
2. Fix the Deployment so its Pod is Running and Ready.
3. Do not change the image or the command.

```plain
kubectl -n batch get pods -l app=worker
```{{exec}}

<details><summary>Solution</summary>

The container log gives the reason:

```plain
kubectl -n batch logs deploy/worker
```{{exec}}

Set the missing environment variable. The Deployment rolls out a new Pod:

```plain
kubectl -n batch set env deploy/worker APP_MODE=production
kubectl -n batch rollout status deploy/worker
```{{exec}}

</details>
