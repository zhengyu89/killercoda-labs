## 🕸️ Network by hand: install a CNI without an operator

📚 **Reference:**
- [Network Plugins](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/)
- [CNI reference plugins](https://www.cni.dev/plugins/current/): [`bridge`](https://www.cni.dev/plugins/current/main/bridge/), [`host-local`](https://www.cni.dev/plugins/current/ipam/host-local/), [`portmap`](https://www.cni.dev/plugins/current/meta/portmap/) · [Network configuration format](https://www.cni.dev/docs/spec/#section-1-network-configuration-format)
- [containernetworking/plugins releases](https://github.com/containernetworking/plugins/releases)

Look at the annex:

```plain
kubectl get nodes
```{{exec}}

```plain
kubectl -n kube-system get pods -o wide
```{{exec}}

```plain
kubectl describe node | grep -i -A2 'NetworkReady\|Ready '
```{{exec}}

The node is `NotReady` because the runtime reports *"cni plugin not initialized"*, and CoreDNS can't start without a Pod network. Production clusters install a CNI as a DaemonSet that drops two things on every node. In this step **you** put those two things there by hand, and see that this is all a CNI really is:

1. **plugin binaries** in `/opt/cni/bin`, the executables containerd runs for every Pod sandbox
2. a **network config** in `/etc/cni/net.d`, the JSON telling containerd which binaries to chain and with what settings

### 🎯 Your Tasks

1. Install the **reference CNI plugins v1.9.1** (`cni-plugins-linux-amd64-v1.9.1.tgz`) into **`/opt/cni/bin`**.
2. Write **`/etc/cni/net.d/10-annex.conflist`** with `"cniVersion": "1.0.0"` and `"name": "annex-net"`, chaining two plugins:
   - **`bridge`**, on a Linux bridge named **`annex0`**, acting as the Pods' gateway (`isGateway`), masquerading Pod traffic leaving the node (`ipMasq`), with `hairpinMode` on so a Pod can reach itself through a Service. Its IPAM is **`host-local`**, handing out addresses from **this node's own Pod CIDR** with a default route.
   - **`portmap`**, with the `portMappings` capability.
3. **Don't** install a CNI from a manifest, Helm chart or operator. The point is to do it by hand.

Done means: the node is `Ready`, CoreDNS is `Running` with IPs from the node's Pod CIDR, and a new Pod can resolve and reach the API server's Service.

⚠️ **Tempting wrong answer:** using the *cluster's* Pod network `10.77.0.0/16` as the subnet. On one node it even works. But `host-local` hands out addresses **per node**, so on a second node with the same config both nodes would assign the same IPs. Every node gets its own slice in `spec.podCIDR`, and that slice is what belongs in the config.

### ✅ Validate it yourself

```plain
kubectl get node -o jsonpath='{.items[0].spec.podCIDR}{"\n"}'
```{{exec}}

```plain
kubectl get nodes && kubectl -n kube-system get pods -o wide
```{{exec}}

```plain
kubectl run net-test --image=curlimages/curl:8.11.1 --restart=Never --rm -it -- curl -sk https://kubernetes.default.svc/version
```{{exec}}

> **If CHECK does not pass**, run `why`{{exec}}.

<br>

<details><summary>💡 Tip: you don't restart anything</summary>

containerd watches `/etc/cni/net.d` and loads the config as soon as it appears. Within a few seconds the runtime reports its network as ready, the kubelet marks the node `Ready`, and the scheduler places CoreDNS. If two config files exist, containerd uses the one that sorts **first** by name.

The `loopback` plugin isn't in your config, but must be in `/opt/cni/bin`, because containerd uses it to set up every sandbox's `lo`. The release tarball includes it.

</details>

<details><summary>💡 Tip: changed the subnet after Pods started?</summary>

The `bridge` plugin gives `annex0` its gateway address when the **first** Pod starts, and never changes it afterwards. If you fix the subnet in the config later, the bridge keeps the old address, and every new Pod fails with *"annex0 already has an IP address different from ..."*. Delete the bridge and recreate the Pods that use it:

```plain
ip link delete annex0 && kubectl -n kube-system rollout restart deployment coredns
```{{exec}}

</details>

<details><summary>💡 Tip: what this bridge does not give you</summary>

`bridge` connects Pods on **one** node. It doesn't route between nodes and doesn't enforce NetworkPolicy. Multi-node CNIs add an overlay or routing between nodes and a policy engine on top of the same plugin model. This single-node annex needs neither.

</details>

<details><summary>✅ Solution</summary>

```plain
cd /tmp && curl -fLO https://github.com/containernetworking/plugins/releases/download/v1.9.1/cni-plugins-linux-amd64-v1.9.1.tgz
tar -xzf cni-plugins-linux-amd64-v1.9.1.tgz -C /opt/cni/bin
ls /opt/cni/bin
```{{exec}}

```plain
POD_CIDR=$(kubectl get node -o jsonpath='{.items[0].spec.podCIDR}')
cat > /etc/cni/net.d/10-annex.conflist <<EOF
{
  "cniVersion": "1.0.0",
  "name": "annex-net",
  "plugins": [
    {
      "type": "bridge",
      "bridge": "annex0",
      "isGateway": true,
      "ipMasq": true,
      "hairpinMode": true,
      "ipam": {
        "type": "host-local",
        "ranges": [[{ "subnet": "${POD_CIDR}" }]],
        "routes": [{ "dst": "0.0.0.0/0" }]
      }
    },
    {
      "type": "portmap",
      "capabilities": { "portMappings": true }
    }
  ]
}
EOF
python3 -m json.tool /etc/cni/net.d/10-annex.conflist >/dev/null && echo valid JSON
```{{exec}}

```plain
kubectl wait --for=condition=Ready node --all --timeout=90s && kubectl -n kube-system get pods -o wide
```{{exec}}

</details>
