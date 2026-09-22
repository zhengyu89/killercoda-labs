
🔑 **Nobody will sign a certificate for the bakery, so the bakery is going to sign for itself.**

cert-manager signs certificates. It does not conjure authorities out of nothing — a `ca` issuer is a pointer at a keypair that already exists, and somebody has to make that keypair. Here, that is you.

Build the bakery's certificate authority, in three moves:

1. With `openssl`, a **4096-bit RSA key** and a **self-signed certificate** for common name `chiikawa-root-ca`, valid for ten years. Keep them in `/root/ca/`.
2. A Kubernetes **Secret of type `kubernetes.io/tls`** named `chiikawa-ca-key-pair` holding that pair — `tls.crt` and `tls.key`, the names cert-manager looks for.
3. A **`ClusterIssuer`** named `chiikawa-ca-issuer`, of type `ca`, backed by that Secret.

The reference for all three is [cert-manager: CA — Setting up CA Issuers](https://cert-manager.io/docs/configuration/ca/).

You are done when this says `True` and `Signing CA verified`:

```plain
kubectl get clusterissuer chiikawa-ca-issuer
```{{exec}}

**Expect the first attempt not to get there.** When it doesn't, read the issuer's own status message before you change anything — the interesting part of this step is what that message leaves out.

> **If CHECK does not pass**, run `why`{{exec}} — it prints the exact condition that was not met, and usually the command that shows you why.

<br>

<details><summary>Tip</summary>

The status message, in full:

```plain
kubectl get clusterissuer chiikawa-ca-issuer -o jsonpath='{.status.conditions[0].message}'
```{{exec}}

If it says a Secret is not found, go and look at that Secret — `kubectl get secret` will show it to you quite happily, wherever you put it. So the question is not whether it exists. It is **which namespace cert-manager looked in**, and why a cluster-scoped object could not have looked anywhere else:

```plain
kubectl -n cert-manager get deploy cert-manager -o jsonpath='{.spec.template.spec.containers[0].args}' | tr ',' '\n'
```{{exec}}

See [cert-manager: Cluster Resource Namespace](https://cert-manager.io/docs/configuration/#cluster-resource-namespace).

</details>

<details><summary>Solution</summary>

The key, then a self-signed certificate over it:

```plain
openssl genrsa -out /root/ca/ca.key 4096
```{{exec}}

```plain
openssl req -x509 -new -nodes -sha256 -days 3650 \
  -key /root/ca/ca.key \
  -subj "/CN=chiikawa-root-ca/O=Nantoka Bakery" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -out /root/ca/ca.crt
```{{exec}}

`-x509` is what makes it self-signed: there is no CSR and no second party, the key signs a certificate for itself. The two `-addext` lines are what make it *a CA* rather than merely a certificate — `CA:TRUE` is the bit every verifier checks before it will accept a signature made by this key, and `keyCertSign` is the permission to make one. cert-manager's own example reaches the same place through `-extensions v3_ca` and your `openssl.cnf`; `-addext` says it inline and does not depend on a config file you have not read.

Look at what you made:

```plain
openssl x509 -in /root/ca/ca.crt -noout -subject -issuer -dates -ext basicConstraints
```{{exec}}

Subject and issuer are the same string. That is the definition of a root.

Now into the cluster — **in namespace `cert-manager`**:

```plain
kubectl create secret tls chiikawa-ca-key-pair \
  --cert=/root/ca/ca.crt \
  --key=/root/ca/ca.key \
  -n cert-manager
```{{exec}}

```plain
kubectl apply -f - <<'YAML'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: chiikawa-ca-issuer
spec:
  ca:
    secretName: chiikawa-ca-key-pair
YAML
```{{exec}}

```plain
kubectl get clusterissuer chiikawa-ca-issuer
```{{exec}}

**Why `cert-manager` and not `chiikawa`.** A `ClusterIssuer` has no namespace of its own, so it has no namespace to resolve `secretName` against. cert-manager gives it one — `--cluster-resource-namespace`, defaulting to wherever cert-manager itself runs — and every Secret a `ClusterIssuer` ever reads comes from there: CA keypairs, ACME account keys, cloud credentials, all of them.

The error when you get it wrong is `secrets "chiikawa-ca-key-pair" not found`, with **no namespace named**, while the Secret sits in plain sight in the namespace you created it in. Nothing about the message suggests the lookup happened somewhere else entirely.

(A namespaced `Issuer` would have read the Secret from its own namespace instead — same `spec.ca`, different scope. This lab uses a `ClusterIssuer` because step 2's `Certificate` lives in `chiikawa`, and one CA that several namespaces can ask is the entire point of having one.)

</details>
