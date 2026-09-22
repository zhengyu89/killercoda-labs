
🐰 **Usagi's turn.** You trust the bakery. Nothing else in the cluster does.

Your laptop's `--cacert` flag is not a distribution strategy — every client that talks to `hachiware.chiikawa.lab` needs the same certificate, and clients are Pods with their own filesystems and their own trust stores.

There's a client waiting in `/root/usagi.yaml`: a Pod in namespace `usagi` that mounts a ConfigMap called `chiikawa-ca-bundle` at `/etc/trust`. Read it first — it will tell you what it needs:

```plain
cat /root/usagi.yaml
```{{exec}}

Your task:

1. Create the **ConfigMap `chiikawa-ca-bundle`** in namespace `usagi`, with the bakery's CA certificate under the key **`ca.crt`**
2. Apply the client and get it Running
3. Prove the difference from inside the cluster:

```plain
insidecurl
```{{exec}}

```plain
insidecurl /etc/trust/ca.crt
```{{exec}}

⚠️ The check reads what you put in that ConfigMap, and it will fail you for putting **too much** in it.

> **If CHECK does not pass**, run `why`{{exec}} — it prints the exact condition that was not met, and usually the command that shows you why.

<br>

<details><summary>Tip</summary>

`kubectl create configmap --from-file=<key>=<path>` sets the key name explicitly — and the key name is the filename that appears inside the container.

If the Pod never starts, look at *why* rather than at the logs:

```plain
kubectl -n usagi describe pod -l app=usagi | tail -20
```{{exec}}

A volume from a ConfigMap that does not exist does not make the Pod crash — it makes it wait, forever, in `ContainerCreating`.

</details>

<details><summary>Solution</summary>

```plain
kubectl -n usagi create configmap chiikawa-ca-bundle --from-file=ca.crt=/root/answers/ca.crt
```{{exec}}

```plain
kubectl apply -f /root/usagi.yaml
```{{exec}}

```plain
kubectl -n usagi rollout status deploy/usagi --timeout=120s
```{{exec}}

```plain
insidecurl
```{{exec}}

```plain
insidecurl /etc/trust/ca.crt
```{{exec}}

Exit 60, then the Pod name of the bakery backend. 🎉 Same Pod, same request, same listener — one mounted file apart.

**The key must never be in there.** A trust bundle is public by construction: it is copied into every namespace, mounted by every workload, and readable by anyone who can read a ConfigMap. `tls.crt` and `ca.crt` are certificates and belong in one. `tls.key` is the CA's private key, and anything holding it can mint a certificate for any name in your organisation. The check rejects a bundle containing a private key for that reason, and `trust-manager` refuses it outright with *only CERTIFICATE blocks are permitted*.

**And this ConfigMap is a copy, not a control loop.** You made it by hand from a file on a node. Nothing keeps it in step with the CA: rotate the root, and this ConfigMap still holds the old one, in this namespace, plus every other copy anyone made anywhere. A new namespace gets nothing until someone remembers it exists.

That is the job [trust-manager](https://cert-manager.io/docs/trust/trust-manager/) exists to do — a `Bundle` resource naming a source and a label selector, writing the CA into every matching namespace and keeping it there:

```plain
kubectl get crd bundles.trust.cert-manager.io 2>/dev/null || echo "trust-manager is not installed in this lab -- see cert-manager/issuers-and-trust"
```{{exec}}

</details>
