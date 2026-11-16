## Task 6: EndpointSlice

In the `legacy` namespace, Service `legacy-svc` has **no selector**, so Kubernetes does not create endpoints for it. Pod `legacy-app` is serving HTTP on port `8080`.

1. Create an EndpointSlice named `legacy-svc-manual` in the `legacy` namespace.
2. Connect it to Service `legacy-svc`.
3. It must send traffic to the IP of Pod `legacy-app` on port `8080`. The port name must match the Service port name, `http`.
4. Do not change the Service.

Verify that the Service now answers:

```plain
curl http://$(kubectl -n legacy get svc legacy-svc -o jsonpath='{.spec.clusterIP}')
```{{exec}}

<details><summary>Solution</summary>

The label `kubernetes.io/service-name` connects an EndpointSlice to its Service.

```plain
POD_IP=$(kubectl -n legacy get pod legacy-app -o jsonpath='{.status.podIP}')
kubectl apply -f - <<YAML
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: legacy-svc-manual
  namespace: legacy
  labels:
    kubernetes.io/service-name: legacy-svc
addressType: IPv4
ports:
- name: http
  protocol: TCP
  port: 8080
endpoints:
- addresses:
  - "$POD_IP"
YAML
```{{exec}}

A manual EndpointSlice is not updated for you. If the Pod is recreated with a new IP, you must update the EndpointSlice.

</details>
