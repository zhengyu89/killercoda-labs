## 🧊 The cold deck

📚 **Reference:**
- [Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)
- [Assigning Pods to Nodes: node affinity](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#node-affinity)

The station has two decks. The worker node sits on the **cold deck**: it carries the label `station.lab/deck=cold` and a taint, `cryo=active:NoSchedule`, that keeps ordinary Pods off it. The control plane is the **warm deck**.

```plain
kubectl get nodes -L station.lab/deck
```{{exec}}

```plain
kubectl describe nodes | grep -E '^Name:|^Taints:'
```{{exec}}

The freezer monitor has to run **next to the freezers, and nowhere else**.

### 🎯 Your Tasks

Create a **Deployment** named `freezer-monitor` in namespace **`cold-deck`**:

- **3 replicas**, image `nginx:1.27-alpine`, Pod label `app: freezer-monitor`
- a **toleration** for exactly the cold-deck taint (key `cryo`, value `active`, effect `NoSchedule`)
- a **required node affinity** (`requiredDuringSchedulingIgnoredDuringExecution`) for nodes where `station.lab/deck` is `cold`

All three Pods must end up **Running on the cold-deck node**.

⚠️ **Tempting wrong answer:** a toleration with `operator: Exists` and no `key` tolerates *every* taint on *every* node, including ones added later for very different reasons (for example `node.kubernetes.io/unschedulable` during a drain). The check rejects it. Tolerate the one taint you mean.

### ✅ Validate it yourself

```plain
kubectl -n cold-deck get pods -o wide
```{{exec}}

Every Pod's `NODE` should be the cold-deck node.

> **If CHECK does not pass**, run `why`{{exec}}.

<br>

<details><summary>💡 Tip: why you need both</summary>

They answer different questions:

- A **toleration** says *"I may run on a node with this taint."* It **permits**, but doesn't attract. With only a toleration, the scheduler may still put the Pod on the warm deck.
- **Node affinity** says *"I must run on a node with this label."* It **attracts**, but doesn't let the Pod past a taint. With only affinity, the Pods stay `Pending`, because the only matching node rejects them.

Try each half on its own and watch `kubectl get pods -o wide` and `kubectl describe pod`. The `Events` section spells out exactly which rule ruled out which node.

</details>

<details><summary>✅ Solution</summary>

```plain
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: freezer-monitor
  namespace: cold-deck
spec:
  replicas: 3
  selector:
    matchLabels:
      app: freezer-monitor
  template:
    metadata:
      labels:
        app: freezer-monitor
    spec:
      tolerations:
      - key: cryo
        operator: Equal
        value: active
        effect: NoSchedule
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: station.lab/deck
                operator: In
                values: ["cold"]
      containers:
      - name: monitor
        image: nginx:1.27-alpine
EOF
```{{exec}}

```plain
kubectl -n cold-deck rollout status deploy/freezer-monitor
```{{exec}}

</details>
