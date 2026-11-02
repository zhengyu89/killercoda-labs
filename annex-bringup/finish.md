<br>

🥟 **The Dumpling Annex is open for business.** The kernel will come back the same after a reboot, Docker answers over CRI, Pods have a network, and the menu is a real Kubernetes resource that refuses nonsense prices.

## 🧩 What you actually did

- **Boot-time settings come from files, and files have an order.** `modules-load.d` loads `br_netfilter` before `sysctl.d` runs, which is the only reason a `net.bridge.*` setting survives a reboot. Among sysctl drop-ins, the file that sorts *last* wins, so a stale `95-` file silently beat your `90-` one until you removed it. `sysctl --system` is the reboot you can run any time.
- **CRI is just a gRPC socket, and anything can sit behind it.** cri-dockerd turned Docker's API into CRI on `/run/cri-dockerd.sock`. systemd owned that socket (`fd://`) and started the daemon on first use. `crictl` talked to it like any other runtime, as long as *both* its runtime and image endpoints pointed there. The kubelet never noticed, because a node has exactly one runtime endpoint and you didn't change it.
- **A unit file's command line is only real once systemd re-reads it and the process restarts.** The upstream unit assumed `/usr/bin`. Your edit didn't exist to systemd until `daemon-reload`, and didn't exist to the running process until a restart.
- **A CNI is two things on disk.** Binaries in `/opt/cni/bin` that containerd executes for every Pod sandbox, and a config in `/etc/cni/net.d` naming which ones to chain. The node went `Ready` within seconds of the file appearing, with no restart. `host-local` allocated from the node's own `spec.podCIDR`, which is what keeps two nodes from handing out the same address. Any CNI DaemonSet does exactly this on every node, plus routing between nodes and a policy engine.
- **A CRD is an API without code.** The structural schema made the API server itself reject a 9000-credit dumpling. `default:` filled in `spiceLevel` without anyone writing it. Printer columns and a category shaped `kubectl get`. The status subresource split one object into two separately writable halves, which is why `apply` couldn't mark it sold out and `--subresource=status` could.

## 📚 Documentation used in this lab

- [Container Runtimes: prerequisites and Docker Engine](https://kubernetes.io/docs/setup/production-environment/container-runtimes/) · [`sysctl.d(5)`](https://man7.org/linux/man-pages/man5/sysctl.d.5.html) · [`modules-load.d(5)`](https://man7.org/linux/man-pages/man5/modules-load.d.5.html)
- [cri-dockerd](https://github.com/Mirantis/cri-dockerd) · [Debugging Kubernetes nodes with crictl](https://kubernetes.io/docs/tasks/debug/debug-cluster/crictl/) · [`systemd.socket(5)`](https://www.freedesktop.org/software/systemd/man/latest/systemd.socket.html)
- [Network Plugins](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/) · [CNI reference plugins](https://www.cni.dev/plugins/current/) · [CNI specification](https://www.cni.dev/docs/spec/)
- [Extend the Kubernetes API with CustomResourceDefinitions](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/) · [Custom Resources](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/)

## 🚀 Where to go next

- [`orbital-noodle-ops`](../orbital-noodle-ops/): the rest of the station, with RBAC, scheduling, rollouts, Kustomize, CronJobs, troubleshooting and node drains
- [`gateway-ca-trust`](../gateway-ca-trust/): Chiikawa's Bakery goes HTTPS with a CA you make yourself, cert-manager, and trust-manager
