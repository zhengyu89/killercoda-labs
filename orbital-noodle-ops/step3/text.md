## ⏪ Bad broth

📚 **Reference:**
- [Deployments: Rolling Back a Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-back-a-deployment)
- [Deployments: Max Unavailable and Max Surge](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#max-unavailable)

The `broth-api` Deployment in namespace **`broth`** has had three releases today. The last one, the *experimental spicy menu*, points at an image tag that doesn't exist. The rollout is stuck halfway, and with the default strategy it has **already taken one healthy Pod down** to make room. 🌶️💥

```plain
kubectl -n broth get deploy,rs,pods
```{{exec}}

```plain
kubectl -n broth rollout history deployment broth-api
```{{exec}}

### 🎯 Your Tasks

1. Find the revision number of the **winter menu** release (the last one that worked). Write **just that number** to `/root/answers/broth-revision`.
2. **Roll `broth-api` back** to that revision. Use the rollout tooling, not a hand-edited image.
3. Change the Deployment's rolling-update strategy so that a bad release can **never take a working Pod down** again:
   - `maxUnavailable: 0`
   - `maxSurge: 1`

When you're done, all **4** replicas should be available and running the winter-menu image. No Pod should still be trying to pull the spicy one.

### ✅ Validate it yourself

```plain
kubectl -n broth rollout history deployment broth-api --revision=2
```{{exec}}

```plain
kubectl -n broth get deploy broth-api -o jsonpath='{.spec.strategy}{"\n"}{.spec.template.spec.containers[0].image}{"\n"}'
```{{exec}}

> **If CHECK does not pass**, run `why`{{exec}}.

<br>

<details><summary>💡 Tip: what a rollback actually does to revision numbers</summary>

A rollback doesn't move the Deployment "backwards". It copies the old revision's Pod template forward, and that template becomes the **newest** revision. Run `rollout history` again after undoing: the winter-menu entry will have moved from its old number to a new, higher one. That's why the task asks you to write the number down *before* you roll back.

Changing `spec.strategy` doesn't create a revision at all, because only changes to `spec.template` do.

</details>

<details><summary>💡 Tip: why <code>maxUnavailable: 0</code> protects you</summary>

With 4 replicas, the default 25% / 25% allows 1 extra Pod (surge) and 1 missing Pod (unavailable). When the new image can't start, the controller has already scaled the old ReplicaSet from 4 to 3, and it stays there.

With `maxUnavailable: 0` and `maxSurge: 1`, the controller may only add one new Pod at a time and may not remove an old one until a new one is **Ready**. A broken image then costs you one stuck extra Pod, and no capacity.

</details>

<details><summary>✅ Solution</summary>

Read the history. The `CHANGE-CAUSE` column comes from the `kubernetes.io/change-cause` annotation each release was applied with:

```plain
kubectl -n broth rollout history deployment broth-api
```{{exec}}

```plain
echo 2 > /root/answers/broth-revision
```{{exec}}

```plain
kubectl -n broth rollout undo deployment broth-api --to-revision=2
```{{exec}}

```plain
kubectl -n broth patch deployment broth-api -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxUnavailable":0,"maxSurge":1}}}}'
```{{exec}}

```plain
kubectl -n broth rollout status deployment broth-api
```{{exec}}

</details>
