## Done

You created ClusterIP, NodePort and headless Services, connected a Service to a backend by hand, and reached a Service across namespaces.

| Service type | Reachable from | Used for |
| --- | --- | --- |
| `ClusterIP` | Inside the cluster | Default; Pod-to-Pod traffic through a stable IP and DNS name |
| `NodePort` | `<node IP>:<nodePort>` (30000-32767) | Simple outside access; builds on ClusterIP |
| `LoadBalancer` | An external load balancer from the cloud provider | Production outside access; builds on NodePort |
| `ExternalName` | Inside the cluster, as a DNS `CNAME` | Giving an outside hostname an in-cluster name; no proxying |
| Headless (`clusterIP: None`) | Inside the cluster, through DNS | DNS returns the Pod IPs directly; used with StatefulSets |
