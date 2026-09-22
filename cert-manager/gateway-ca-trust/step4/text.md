
## 🐰 Usagi Receives the CA By Hand

📚 **Reference:**
- [Kubernetes: ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Kubernetes: mounting a ConfigMap as a volume](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/#populate-a-volume-with-data-stored-in-a-configmap)

You trust the bakery. Nothing else in the cluster does — not even a Pod one namespace away. Your `visit /root/answers/ca.crt` from step 3 is not a distribution strategy — every client that talks to `hachiware.chiikawa.lab` needs the same certificate, and clients are Pods with their own filesystems and their own trust stores.

There's a client waiting in `/root/usagi.yaml`: a Pod in namespace `usagi` that mounts a ConfigMap called `chiikawa-ca-bundle` at `/etc/trust`. Read it first — it names the ConfigMap it needs before that ConfigMap exists:

```plain
cat /root/usagi.yaml
```{{exec}}

### 🎯 Your Tasks

#### Task 1: Create the trust ConfigMap

- **Name**: `chiikawa-ca-bundle`
- **Namespace**: `usagi`
- **Key**: `ca.crt` — that key name becomes the filename inside the container
- **Data**: the CA certificate from step 3's `/root/answers/ca.crt`

```plain
kubectl -n usagi create configmap chiikawa-ca-bundle --from-file=ca.crt=/root/answers/ca.crt
```{{exec}}

#### Task 2: Apply the client and get it Running

```plain
kubectl apply -f /root/usagi.yaml
```{{exec}}

```plain
kubectl -n usagi rollout status deploy/usagi --timeout=120s
```{{exec}}

#### Task 3: Prove the difference, from inside the cluster

```plain
insidecurl
```{{exec}}

```plain
insidecurl /etc/trust/ca.crt
```{{exec}}

Exit 60, then the backend Pod's own name. Same Pod, same request, same listener — one mounted file apart.

⚠️ The check reads what you put in that ConfigMap, and it will fail you for putting **too much** in it — read on before you build it a different way.

> **If CHECK does not pass**, run `why`{{exec}} — it prints the exact condition that was not met, and usually the command that shows you why.

<br>

<details><summary>Tip: if the Pod never starts</summary>

```plain
kubectl -n usagi describe pod -l app=usagi | tail -20
```{{exec}}

A volume from a ConfigMap that does not exist does not crash the Pod — it makes it wait, forever, in `ContainerCreating`, with the reason on the Pod's events and nowhere else.

</details>

<details><summary>Why the private key must never go in this ConfigMap</summary>

A trust bundle is public by construction: it is copied into every namespace, mounted by every workload, and readable by anyone who can read a ConfigMap. `tls.crt` and `ca.crt` are certificates and belong in one. `tls.key` is the CA's private key, and anything holding it can mint a certificate for any name in your organisation. The check rejects a bundle containing a private key for that reason, and `trust-manager` — step 5's subject — refuses it outright with *only CERTIFICATE blocks are permitted*.

**And this ConfigMap is a copy, not a control loop.** You made it by hand from a file on a node. Nothing keeps it in step with the CA: rotate the root, and this ConfigMap still holds the old one, in this namespace, plus every other copy anyone made anywhere. A new namespace gets nothing until someone remembers it exists. That is the scaling problem step 5 solves.

</details>
