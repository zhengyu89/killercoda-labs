
## ⚙️ Trust That Scales: trust-manager

📚 **Reference:**
- [cert-manager: trust-manager](https://cert-manager.io/docs/trust/trust-manager/)
- [trust-manager: Bundle API reference](https://cert-manager.io/docs/trust/trust-manager/bundle/)

The manual copy from step 4 works. It does not scale. Think about what step 4 looks like as the bakery grows:

| Namespaces needing the CA | Manual copies |
|---|---|
| 1 (`usagi`) | fine — you just did it |
| 20 | painful — 20 ConfigMaps, 20 places to forget |
| 100 | bad — and every CA rotation means doing it 100 times again |

`trust-manager` is already installed in this cluster, with no `Bundle` yet — the same way cert-manager started this lab with no issuer. A `Bundle` names a **source** (where the CA certificate comes from) and a **target** (where it gets written), plus a label selector for which namespaces get it. Label a namespace, and the certificate shows up there on its own; remove the label, and trust-manager takes it away again.

### 🎯 Your Tasks

Try these yourself first — all the commands are in the **Solution** below.

#### Task 1: Delete the ConfigMap you made by hand in step 4

You're about to let `trust-manager` own that name instead.

#### Task 2: Label the namespaces that should get the CA

Label `usagi` and `kitchen` with `chiikawa.lab/trust-bundle=true`. `kitchen` is empty and you've never touched it — proof that this happens on its own, not because of anything you did there.

#### Task 3: Create the Bundle

- **Name**: `chiikawa-ca-bundle`
- **Source**: Secret `chiikawa-ca-key-pair`, key `tls.crt` — the same Secret cert-manager already reads for signing; no new Secret needed
- **Target**: ConfigMap key `ca.crt`, in every namespace matching `chiikawa.lab/trust-bundle=true`

A `secret` source has no namespace field — it always reads from trust-manager's one configured namespace, which defaults to `cert-manager`. That's exactly where `chiikawa-ca-key-pair` already lives.

### ✅ Validate it yourself

```plain
kubectl get bundle chiikawa-ca-bundle
```{{exec}}

```plain
kubectl -n usagi get configmap chiikawa-ca-bundle -o jsonpath='{.data.ca\.crt}' | openssl x509 -noout -subject -issuer
```{{exec}}

```plain
kubectl -n kitchen get configmap chiikawa-ca-bundle
```{{exec}}

`kitchen` getting the same ConfigMap, with no manual step of yours in that namespace, is the entire point. And Usagi's Pod from step 4 still works — nothing there was touched, its ConfigMap just has a new owner now:

```plain
GWIP=$(kubectl -n chiikawa get svc chiikawa-gateway-nginx -o jsonpath='{.spec.clusterIP}')
kubectl -n usagi exec deploy/usagi -- curl -sS --cacert /etc/trust/ca.crt --resolve hachiware.chiikawa.lab:443:$GWIP https://hachiware.chiikawa.lab/hostname
```{{exec}}

> **If CHECK does not pass**, run `why`{{exec}} — it prints the exact condition that was not met, and usually the command that shows you why.

<br>

<details><summary>✅ Solution</summary>

```plain
kubectl -n usagi delete configmap chiikawa-ca-bundle
```{{exec}}

```plain
kubectl label namespace usagi chiikawa.lab/trust-bundle=true
```{{exec}}

```plain
kubectl label namespace kitchen chiikawa.lab/trust-bundle=true
```{{exec}}

```plain
kubectl apply -f - <<'EOF'
apiVersion: trust.cert-manager.io/v1alpha1
kind: Bundle
metadata:
  name: chiikawa-ca-bundle
spec:
  sources:
  - secret:
      name: chiikawa-ca-key-pair
      key: tls.crt
  target:
    configMap:
      key: ca.crt
    namespaceSelector:
      matchLabels:
        chiikawa.lab/trust-bundle: "true"
EOF
```{{exec}}

</details>

<details><summary>Tip: if a target namespace has no ConfigMap</summary>

Check the Bundle's own status first — a source it can't read fails the whole `Bundle`, not just one target:

```plain
kubectl get bundle chiikawa-ca-bundle -o jsonpath='{.status.conditions}' | tr ',' '\n'
```{{exec}}

If the Bundle is `Synced: True` but a namespace is still missing the ConfigMap, check its labels — `namespaceSelector` only matches what you actually applied:

```plain
kubectl get namespace usagi kitchen chiikawa --show-labels
```{{exec}}

A `Bundle` with **no** `namespaceSelector` targets every namespace, including ones you never meant to touch — `chiikawa`, `cert-manager`, even `kube-system`. Leaving it out is not "select nothing," it's "select everything."

</details>
