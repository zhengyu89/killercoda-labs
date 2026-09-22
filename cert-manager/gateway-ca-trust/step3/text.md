
🚪 **A Secret full of PEM is not a website.** Something has to terminate TLS with it.

The controller is already here, and it owns one class:

```plain
kubectl get gatewayclass nginx -o custom-columns=NAME:.metadata.name,CONTROLLER:.spec.controllerName,ACCEPTED:.status.conditions[0].status
```{{exec}}

`gateway.nginx.org/nginx-gateway-controller` — NGINX Gateway Fabric. `GatewayClass` is the cluster-scoped half of the split: an administrator installs the controller and declares the class; you write `Gateway`s against it. Note that **no nginx is running for you yet**:

```plain
kubectl -n chiikawa get deploy,svc
```{{exec}}

Now build the front door, in two objects:

1. A **`Gateway`** named `chiikawa-gateway` in namespace `chiikawa`, class `nginx`, with **one HTTPS listener on port 443** for hostname `hachiware.chiikawa.lab`, terminating TLS with the `hachiware-tls` Secret from step 2.
2. An **`HTTPRoute`** named `hachiware-route` attaching to that Gateway and sending `hachiware.chiikawa.lab` to the `hachiware` Service on port 80.

References: [Gateway API: TLS configuration](https://gateway-api.sigs.k8s.io/guides/user-guides/tls/), [the `Gateway` resource](https://gateway-api.sigs.k8s.io/reference/api-types/gateway/), [the `HTTPRoute` resource](https://gateway-api.sigs.k8s.io/reference/api-types/httproute/), and [NGINX Gateway Fabric: securing traffic](https://docs.nginx.com/nginx-gateway-fabric/traffic-security/).

You are done when the listener is serving your certificate — no request, just the handshake:

```plain
servedcert
```{{exec}}

> **If CHECK does not pass**, run `why`{{exec}} — it prints the exact condition that was not met, and usually the command that shows you why.

<br>

<details><summary>Tip</summary>

The Gateway tells you what it thinks of each listener separately from what it thinks of itself:

```plain
kubectl -n chiikawa get gateway chiikawa-gateway -o jsonpath='{range .status.listeners[*]}{.name}{"\t"}{range .conditions[*]}{.type}={.status} {end}{"\n"}{end}'
```{{exec}}

`ResolvedRefs=False` means it cannot use the Secret you named — wrong name, wrong namespace, or not a TLS Secret. `Programmed` is about the data plane being configured for it.

And the route has its own opinion, recorded per parent it tried to attach to:

```plain
kubectl -n chiikawa describe httproute hachiware-route
```{{exec}}

NGINX Gateway Fabric creates the actual nginx Deployment and Service **when the Gateway is created**, in the Gateway's namespace:

```plain
kubectl -n chiikawa get deploy,svc,pods
```{{exec}}

</details>

<details><summary>Solution</summary>

```plain
kubectl apply -f - <<'YAML'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: chiikawa-gateway
  namespace: chiikawa
spec:
  gatewayClassName: nginx
  listeners:
  - name: https
    protocol: HTTPS
    port: 443
    hostname: hachiware.chiikawa.lab
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: hachiware-tls
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: hachiware-route
  namespace: chiikawa
spec:
  parentRefs:
  - name: chiikawa-gateway
  hostnames:
  - hachiware.chiikawa.lab
  rules:
  - backendRefs:
    - name: hachiware
      port: 80
YAML
```{{exec}}

```plain
kubectl -n chiikawa rollout status deploy/chiikawa-gateway-nginx --timeout=120s
```{{exec}}

An nginx Deployment and a Service appeared that you did not write. That is the shape of Gateway API on this controller: the `Gateway` object *is* the request for a data plane, and NGINX Gateway Fabric creates one per Gateway, in the Gateway's own namespace.

```plain
kubectl -n chiikawa get gateway chiikawa-gateway
```{{exec}}

```plain
servedcert
```{{exec}}

The listener is serving a certificate issued by `CN=chiikawa-root-ca`, with `CA:FALSE` and a SAN of `hachiware.chiikawa.lab`. Nothing copied a file to do this — the listener names a Secret, the Secret is written by cert-manager, and when cert-manager renews it the same listener starts serving the new one without the Gateway being edited.

**`certificateRefs` resolves in the Gateway's namespace.** There is no namespace field to set here by accident, but there is a `namespace` field available on the ref — and pointing it at another namespace does *not* work by default. That is a `ReferenceGrant` in the target namespace, granted by whoever owns the Secret, and its absence shows up as `ResolvedRefs=False` rather than as an apply-time error.

**`mode: Terminate` is what makes any of this the Gateway's business.** The alternative, `Passthrough`, hands the encrypted bytes to the backend untouched — the platform never holds the key, and in exchange it can no longer route on anything inside the request, because it cannot read it.

</details>
