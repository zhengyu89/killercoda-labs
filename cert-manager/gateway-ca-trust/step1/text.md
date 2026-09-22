
## 🔑 Create the Chiikawa Bakery CA

📚 **Reference:**
- [cert-manager: CA — Setting up CA Issuers](https://cert-manager.io/docs/configuration/ca/)
- [cert-manager: Cluster Resource Namespace](https://cert-manager.io/docs/configuration/#cluster-resource-namespace)

Nobody will sign a certificate for the bakery, so the bakery is going to sign for itself. A private CA is nothing more than **a certificate and a private key**, made with `openssl`. cert-manager does not create that authority — it only signs with it, once you tell it where the keypair lives. Here, that is you.

### Setup: make the keypair (run these first)

A 4096-bit RSA key, then a self-signed certificate over it:

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

`-x509` is what makes it self-signed: there is no CSR and no second party, the key signs a certificate for itself. The two `-addext` lines are what make it *a CA* rather than merely a certificate — `CA:TRUE` is the bit every verifier checks before accepting a signature from this key, and `keyCertSign` is the permission to make one. Neither can be added after the fact.

```plain
openssl x509 -in /root/ca/ca.crt -noout -subject -issuer -dates -ext basicConstraints
```{{exec}}

Subject and issuer are the same string — that is the definition of a root.

### 🎯 Your Tasks

#### Task 1: Store the keypair as a Secret

- **Name**: `chiikawa-ca-key-pair`
- **Namespace**: `cert-manager` — not `chiikawa` (see below for why)
- **Type**: `kubernetes.io/tls`, holding `tls.crt` and `tls.key` — the exact key names cert-manager looks for

```plain
kubectl create secret tls chiikawa-ca-key-pair \
  --cert=/root/ca/ca.crt \
  --key=/root/ca/ca.key \
  -n cert-manager
```{{exec}}

#### Task 2: Create a ClusterIssuer referencing that Secret

- **Name**: `chiikawa-ca-issuer`
- **Kind**: `ClusterIssuer` (cluster-scoped, not namespaced)
- **Type**: `ca`, backed by `secretName: chiikawa-ca-key-pair`

```plain
kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: chiikawa-ca-issuer
spec:
  ca:
    secretName: chiikawa-ca-key-pair
EOF
```{{exec}}

**Why `cert-manager` and not `chiikawa`.** A `ClusterIssuer` has no namespace of its own, so it has no namespace to resolve `secretName` against. cert-manager gives it one instead — `--cluster-resource-namespace`, defaulting to wherever cert-manager itself runs — and every Secret a `ClusterIssuer` ever reads comes from there: CA keypairs, ACME account keys, cloud credentials, all of them. Put the Secret anywhere else and the error is `secrets "chiikawa-ca-key-pair" not found`, with **no namespace named**, while `kubectl get secret` shows it to you quite happily wherever you actually put it.

### ✅ Validate it yourself

```plain
kubectl -n cert-manager get secret chiikawa-ca-key-pair
```{{exec}}

```plain
kubectl get clusterissuer chiikawa-ca-issuer
```{{exec}}

You are done when the second command says `True` and `Signing CA verified`. This is also the CHECK for this step.

> **If CHECK does not pass**, run `why`{{exec}} — it prints the exact condition that was not met, and usually the command that shows you why.

<br>

<details><summary>Tip: reading the full status message</summary>

```plain
kubectl get clusterissuer chiikawa-ca-issuer -o jsonpath='{.status.conditions[0].message}'
```{{exec}}

If it says a Secret is not found, look at the deployment's own arguments to see which namespace it is actually reading from:

```plain
kubectl -n cert-manager get deploy cert-manager -o jsonpath='{.spec.template.spec.containers[0].args}' | tr ',' '\n'
```{{exec}}

</details>
