## 📻 Dead air

📚 **Reference:**
- [Debug Services](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/)
- [Configure Liveness, Readiness and Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [EndpointSlices](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/)

The station radio runs in namespace **`comms`**: a `radio` Deployment behind a `radio` Service. The `listener` Pod is supposed to hear it at `http://radio/hostname`. It hears nothing, and the radio Pods keep restarting. 📡😵

```plain
kubectl -n comms exec deploy/listener -- curl -sS -m 5 http://radio/hostname
```{{exec}}

There's **more than one fault**. Diagnose them; don't just rebuild everything.

### 🎯 Your Tasks

Make the listener hear the radio, and make the radio Pods stop restarting, with these constraints:

- **Don't delete or re-create** the `radio` Service. Fix it in place (`kubectl edit` / `patch`).
- **Don't change** the radio Pods' labels or the container's port (`9090`, named `http`). The radio itself is fine; it's what's pointing at it that's wrong.
- **Keep the liveness probe.** Deleting it would stop the restarts and hide the next real hang. Point it at the right place instead.

Done means: the curl above prints a radio Pod's hostname, both radio Pods are `Ready`, and their restart counts stop climbing.

### ✅ Validate it yourself

A methodical order: is the Service selecting any Pods? Does it send traffic to a port they listen on? Why are the containers being killed?

```plain
kubectl -n comms get svc radio -o wide
```{{exec}}

```plain
kubectl -n comms get endpointslices -l kubernetes.io/service-name=radio
```{{exec}}

```plain
kubectl -n comms get pods --show-labels
```{{exec}}

```plain
kubectl -n comms describe pod -l app=radio | grep -E 'Port:|Liveness:|Restart Count:|Unhealthy|Killing' 
```{{exec}}

> **If CHECK does not pass**, run `why`{{exec}}.

<br>

<details><summary>💡 Tip: reading an empty EndpointSlice</summary>

`ENDPOINTS` showing `<unset>` (or no slice addresses) means the selector matched **no Pods at all**, so check the labels. Addresses that are present but connections still refused or timed out means the selector is fine, but `targetPort` doesn't match a port the container listens on.

`targetPort` can be a number or the container port's **name**. Using the name (`http`) means the Service keeps working if the container's port number ever changes.

</details>

<details><summary>💡 Tip: a probe that fails is the kubelet killing a healthy container</summary>

`Liveness probe failed: ... connection refused` followed by `Container radio failed liveness probe, will be restarted` means the kubelet tried a port where nothing listens and decided the app was dead. The app was fine all along. The probe just needs the same port the app actually serves.

</details>

<details><summary>✅ Solution</summary>

Fault 1 and 2, the Service: its selector is `app: radio-tx` (no Pod has that label), and it targets port `8080` (nothing listens there). Fix both in place:

```plain
kubectl -n comms patch svc radio --type=json -p '[
  {"op":"replace","path":"/spec/selector","value":{"app":"radio"}},
  {"op":"replace","path":"/spec/ports/0/targetPort","value":"http"}
]'
```{{exec}}

Fault 3, the liveness probe: it checks port `8080` too, so the kubelet kills every container ~15s after it starts.

```plain
kubectl -n comms patch deploy radio --type=json -p '[
  {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/httpGet/port","value":"http"}
]'
```{{exec}}

```plain
kubectl -n comms rollout status deploy/radio && kubectl -n comms exec deploy/listener -- curl -sS -m 5 http://radio/hostname; echo
```{{exec}}

If that first curl times out right after the rollout, run it again. Service routing on each node takes a few seconds to catch up with Pods that just changed.

</details>
