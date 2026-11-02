## 🔐 Ladle-9 gets a badge

⏱️ **Setup takes 2–5 minutes.** You'll see a line of dots and then `done` in the terminal. Until then, commands may fail with "not found" or "connection refused".

📚 **Reference:**
- [Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/), in particular *Referring to resources* (subresources and `resourceNames`)
- [Configure Service Accounts for Pods](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)
- [`kubectl auth can-i`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_auth/kubectl_auth_can-i/)

Ladle-9 has one job: when the lunch rush hits, it adds more noodle cooks. It reads Pods (and their logs) to judge the queue, and it changes the **replica count** of the `noodle-line` Deployment. Right now it does that with the chef's admin credentials. Chef Udon would like that to stop. 😬

Have a look at the galley first:

```plain
kubectl -n galley get deploy,pods,secrets
```{{exec}}

### 🎯 Your Tasks

All objects go in namespace **`galley`**.

1. A **ServiceAccount** named `order-bot`.
2. A **Role** named `order-bot` that allows exactly:

   | API group | Resource | Names | Verbs |
   |---|---|---|---|
   | `""` (core) | `pods` | any | `get`, `list`, `watch` |
   | `""` (core) | `pods/log` | any | `get` |
   | `apps` | `deployments` | **only** `noodle-line` | `get` |
   | `apps` | `deployments/scale` | **only** `noodle-line` | `get`, `patch`, `update` |

3. A **RoleBinding** named `order-bot` that binds that Role to that ServiceAccount.
4. Then **acting as the bot** (impersonate it with `--as`), scale `noodle-line` to **4** replicas.

The bot must **not** be able to delete or create Pods, read Secrets, edit the `noodle-line` Deployment itself (only its *scale*), touch `dish-washer` at all, or do anything outside `galley`.

### ✅ Validate it yourself

The bot's identity, as the API server sees it, is `system:serviceaccount:galley:order-bot`:

```plain
kubectl -n galley auth can-i patch deployments.apps/noodle-line --subresource=scale --as=system:serviceaccount:galley:order-bot
```{{exec}}

```plain
kubectl -n galley auth can-i patch deployments.apps/noodle-line --as=system:serviceaccount:galley:order-bot
```{{exec}}

The first should say `yes`, the second `no`. If both say `yes`, the bot can rewrite the whole Deployment (image, command, everything), not just its replica count.

```plain
kubectl -n galley get deploy noodle-line
```{{exec}}

> **If CHECK does not pass**, run `why`{{exec}}. It names each permission the bot has but shouldn't, or lacks but needs.

<br>

<details><summary>💡 Tip: why <code>deployments/scale</code> is its own resource</summary>

`kubectl scale` doesn't send a whole new Deployment. It writes to the Deployment's `scale` **subresource**, a tiny object holding only `replicas`. RBAC treats `deployments` and `deployments/scale` as separate resources, so you can grant one without the other. That is how you hand out "may change the replica count" without "may change the image".

`kubectl scale` also reads the Deployment once before scaling, which is why the bot needs `get` on `deployments` itself, still limited to `noodle-line` by `resourceNames`.

Note: `resourceNames` can't restrict `list`, `watch` or `create`, because those requests don't name a single object. That's fine here, since the bot doesn't need them on Deployments.

</details>

<details><summary>✅ Solution</summary>

```plain
kubectl -n galley create serviceaccount order-bot
```{{exec}}

```plain
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: order-bot
  namespace: galley
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  resourceNames: ["noodle-line"]
  verbs: ["get"]
- apiGroups: ["apps"]
  resources: ["deployments/scale"]
  resourceNames: ["noodle-line"]
  verbs: ["get", "patch", "update"]
EOF
```{{exec}}

```plain
kubectl -n galley create rolebinding order-bot --role=order-bot --serviceaccount=galley:order-bot
```{{exec}}

```plain
kubectl -n galley scale deployment noodle-line --replicas=4 --as=system:serviceaccount:galley:order-bot
```{{exec}}

A useful negative test, which should be refused:

```plain
kubectl -n galley scale deployment dish-washer --replicas=2 --as=system:serviceaccount:galley:order-bot
```{{exec}}

</details>
