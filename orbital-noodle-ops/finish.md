<br>

🍜 **The station is running smoothly again.** Ladle-9 has its own badge, the freezers are watched, the broth is back, and the radio is on air. Before you go, put the cold deck back in service:

```plain
kubectl uncordon node01 && kubectl -n cold-deck get pods -o wide -w
```{{exec}}

The `freezer-monitor` Pods leave `Pending` within seconds. Nothing re-created them: they were waiting for a node their affinity allows. (Press `Ctrl+C` to stop watching.)

## 🧩 What you actually did

- **RBAC is judged per request, by the API server.** `kubectl auth can-i --as=...` asks the same authorizer every real request goes through, so it's the honest way to test a Role, including the *negative* cases. `deployments` and `deployments/scale` are different resources, and `resourceNames` narrows a rule to single objects. Together they gave Ladle-9 "change the replica count of one Deployment" and nothing else.
- **Tolerations permit, affinity attracts.** The toleration alone left the scheduler free to use the warm deck. The affinity alone left every Pod `Pending` behind the taint. You needed both, and you tolerated *one* taint rather than every taint.
- **A rollback is a roll forward to an old template.** The winter menu came back as a new, higher revision number, and changing `spec.strategy` created no revision at all, because only `spec.template` does. `maxUnavailable: 0` with `maxSurge: 1` means a bad image costs you a stuck extra Pod instead of a healthy one.
- **Generated Secrets get content-hashed names.** Kustomize named it `pantry-creds-<hash>` and rewrote both references to match. A new token means a new name, a changed Pod template, and a rollout, with no stale env vars. `items` decided which keys became files, and `defaultMode: 0400` (octal) decided who could read them.
- **A CronJob is three layers.** Schedule, time zone and history limits belong to the CronJob. Retries and deadlines belong to the Job. Restart policy and containers belong to the Pod. `create job --from=cronjob/...` ran the exact template the schedule would have run, and recorded that it was manual.
- **Debug a Service from the selector outward.** An empty EndpointSlice meant the selector matched nothing. Once it matched, a refused connection meant `targetPort` named a port nobody listens on. The restart loop was the kubelet faithfully killing a healthy container whose probe checked that same wrong port. You fixed the probe instead of deleting it.
- **Drain is eviction, and eviction respects budgets.** `drain` cordoned the node, skipped DaemonSet Pods, and evicted the rest through the eviction API. Any eviction that would have dropped the jukebox below `minAvailable: 2` was refused with `429` and retried until a replacement was Ready on the warm deck.

## 📚 Documentation used in this lab

- [Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) · [`kubectl auth can-i`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_auth/kubectl_auth_can-i/)
- [Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/) · [Assigning Pods to Nodes](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/) · [Pod Topology Spread Constraints](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/)
- [Deployments: rolling back, max unavailable and max surge](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Managing objects with Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) · [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
- [CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) · [Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
- [Debug Services](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/) · [Liveness, Readiness and Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [Safely Drain a Node](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/) · [Configure a PodDisruptionBudget](https://kubernetes.io/docs/tasks/run-application/configure-pdb/)

## 🚀 Where to go next

- [`gateway-ca-trust`](../gateway-ca-trust/): Chiikawa's Bakery goes HTTPS with a CA you make yourself, cert-manager, and trust-manager

