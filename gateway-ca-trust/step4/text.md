
## 🐰 Usagi Receives the CA By Hand

📚 **Reference:**
- [Kubernetes: ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Kubernetes: mounting a ConfigMap as a volume](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/#populate-a-volume-with-data-stored-in-a-configmap)

You trust the bakery now. Nothing else in the cluster does — not even a Pod one namespace away. Saving `/root/answers/ca.crt` on this node in step 3 only helped *this* node; every other client that talks to `hachiware.chiikawa.lab` needs its own copy of the same file.

There's a client waiting in `/root/usagi.yaml`: a Pod in namespace `usagi` that mounts a ConfigMap called `chiikawa-ca-bundle` at `/etc/trust`. Read it first — it names a ConfigMap that doesn't exist yet:

```plain
cat /root/usagi.yaml
```{{exec}}

### 🎯 Your Tasks

Try these yourself first — the commands are in the **Solution** below.

#### Task 1: Create the trust ConfigMap

- **Name**: `chiikawa-ca-bundle`
- **Namespace**: `usagi`
- **Key**: `ca.crt` — this key name becomes the filename inside the container
- **Data**: the file from step 3, `/root/answers/ca.crt`

#### Task 2: Apply the client and wait for it to be Running

### ✅ Validate it yourself

First, find the Gateway's address and try the request from inside Usagi's Pod, with no CA file — it should still fail:

```plain
GWIP=$(kubectl -n chiikawa get svc chiikawa-gateway-nginx -o jsonpath='{.spec.clusterIP}')
kubectl -n usagi exec deploy/usagi -- curl -sS --resolve hachiware.chiikawa.lab:443:$GWIP https://hachiware.chiikawa.lab/hostname
```{{exec}}

Now the same request, pointed at the file the ConfigMap mounted:

```plain
kubectl -n usagi exec deploy/usagi -- curl -sS --cacert /etc/trust/ca.crt --resolve hachiware.chiikawa.lab:443:$GWIP https://hachiware.chiikawa.lab/hostname
```{{exec}}

Exit 60, then the backend Pod's own name. Same Pod, same request, same listener — one mounted file apart.

⚠️ The check reads what you put in that ConfigMap, and it will fail you for putting **too much** in it — read on before you build it a different way.

> **If CHECK does not pass**, run `why`{{exec}} — it prints the exact condition that was not met, and usually the command that shows you why.

<br>

<details><summary>✅ Solution</summary>

```plain
kubectl -n usagi create configmap chiikawa-ca-bundle --from-file=ca.crt=/root/answers/ca.crt
```{{exec}}

```plain
kubectl apply -f /root/usagi.yaml
```{{exec}}

```plain
kubectl -n usagi rollout status deploy/usagi --timeout=120s
```{{exec}}

</details>

<details><summary>Tip: if the Pod never starts</summary>

```plain
kubectl -n usagi describe pod -l app=usagi | tail -20
```{{exec}}

A volume from a ConfigMap that doesn't exist doesn't crash the Pod — it just waits, forever, in `ContainerCreating`, with the reason on the Pod's events and nowhere else.

</details>

<details><summary>Why the private key must never go in this ConfigMap</summary>

This ConfigMap is meant to be copied into every namespace and mounted by every workload — anyone who can read a ConfigMap can read it. `tls.crt` and `ca.crt` are certificates, fine to share. `tls.key` is the CA's private key: anyone holding it can sign a certificate for any name in this bakery. The check fails you if a private key ends up in this ConfigMap, and `trust-manager` (step 5) refuses one outright with *only CERTIFICATE blocks are permitted*.

**And this ConfigMap is a copy, not something that stays up to date on its own.** You made it by hand from a file on a node. If the CA is ever regenerated, this ConfigMap still holds the old one — in this namespace, and in every other copy anyone made anywhere. A new namespace gets nothing until someone remembers to copy it there by hand. Step 5 fixes that.

</details>
