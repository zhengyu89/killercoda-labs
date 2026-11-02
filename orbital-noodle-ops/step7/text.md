## 🛠️ Hull maintenance

📚 **Reference:**
- [Safely Drain a Node](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/)
- [Specifying a Disruption Budget for your Application](https://kubernetes.io/docs/tasks/run-application/configure-pdb/)
- [`kubectl drain`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_drain/)

The cold deck's hull needs patching, and the worker node has to be emptied first. The lounge `jukebox` in namespace **`lounge`** runs 3 replicas spread across *both* decks, and the crew will mutiny if the music drops below 2 players at any moment. 🎶

```plain
kubectl get pods -A -o wide --field-selector spec.nodeName=$(kubectl get nodes -l station.lab/deck=cold -o jsonpath='{.items[0].metadata.name}')
```{{exec}}

### 🎯 Your Tasks

1. Create a **PodDisruptionBudget** named `jukebox-pdb` in `lounge` that selects `app: jukebox` and keeps **at least 2** of its Pods available (`minAvailable: 2`).
2. **Cordon and drain** the cold-deck node (`node01`) so that no workload Pods are left on it. DaemonSet Pods (networking, kube-proxy) stay where they are.
3. **Leave it cordoned.** The maintenance is still in progress when you press CHECK.

At the end, all 3 jukebox replicas must be **Ready on the warm deck**.

⚠️ Your step-2 `freezer-monitor` Pods will go `Pending` after the drain. That's expected and correct: their required affinity allows only the cold deck, which is now closed. They'll come back on their own after you `uncordon` the node.

### ✅ Validate it yourself

```plain
kubectl get nodes
```{{exec}}

```plain
kubectl -n lounge get pdb jukebox-pdb && kubectl -n lounge get pods -o wide
```{{exec}}

> **If CHECK does not pass**, run `why`{{exec}}.

<br>

<details><summary>💡 Tip: when <code>kubectl drain</code> refuses</summary>

`drain` stops and explains itself instead of guessing. The usual reasons:

- **DaemonSet-managed Pods**: they would be re-created on the same node immediately, so drain won't evict them unless told to skip them: `--ignore-daemonsets`.
- **Pods using `emptyDir`**: their scratch data is lost on eviction, so drain needs your consent: `--delete-emptydir-data`.
- **Pods with no controller**: nothing would re-create them, so drain needs `--force`, and those Pods are gone for good. (There are none on node01 in this lab.)

And a slow drain isn't a broken one. If the PDB would be violated, the eviction API answers `429` and drain **retries** until a replacement Pod is Ready elsewhere. That's the budget doing its job.

</details>

<details><summary>💡 Tip: cordon vs drain</summary>

`cordon` only marks the node unschedulable, and existing Pods stay put. `drain` cordons *and* evicts. `uncordon` reverses the cordon. Evicted Pods do not move back on their own.

</details>

<details><summary>✅ Solution</summary>

```plain
kubectl -n lounge create poddisruptionbudget jukebox-pdb --selector=app=jukebox --min-available=2
```{{exec}}

```plain
kubectl -n lounge get pdb jukebox-pdb
```{{exec}}

`ALLOWED DISRUPTIONS` should be `1`: 3 healthy Pods, at least 2 required.

```plain
kubectl drain node01 --ignore-daemonsets --delete-emptydir-data
```{{exec}}

```plain
kubectl -n lounge get pods -o wide
```{{exec}}

When the maintenance is finished (after CHECK), bring the deck back:

```plain
kubectl uncordon node01
```{{exec}}

</details>
