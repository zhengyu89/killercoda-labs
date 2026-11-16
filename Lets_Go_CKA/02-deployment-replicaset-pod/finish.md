## Done

You created a Pod, a Deployment and a ReplicaSet, and fixed Pods stuck in:

| Status | Usual cause | Where to look |
| --- | --- | --- |
| `CrashLoopBackOff` | The container starts, then exits | `kubectl logs` (add `--previous` after a restart) |
| `ImagePullBackOff` | Wrong image name or tag, or no access to the registry | `kubectl describe pod` → Events |
| `CreateContainerError` | The runtime cannot create the container, e.g. no command | `kubectl describe pod` → Events |
