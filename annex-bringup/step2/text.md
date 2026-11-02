## 🐳 A second runtime: cri-dockerd from the tarball

📚 **Reference:**
- [Container Runtimes: Docker Engine](https://kubernetes.io/docs/setup/production-environment/container-runtimes/#docker) · [cri-dockerd repository](https://github.com/Mirantis/cri-dockerd) (releases, and `packaging/systemd/`)
- [Debugging Kubernetes nodes with crictl](https://kubernetes.io/docs/tasks/debug/debug-cluster/crictl/)
- [`systemd.socket(5)`](https://www.freedesktop.org/software/systemd/man/latest/systemd.socket.html), on socket activation

The kubelet only speaks **CRI** (Container Runtime Interface), a gRPC API on a Unix socket. containerd speaks it natively. Docker doesn't, so a small adapter, **cri-dockerd**, translates CRI calls into Docker API calls.

The annex's build agents need Docker, and Engineer Wonton wants it reachable over CRI so the same `crictl` tooling works against both runtimes. The **kubelet stays on containerd**. You're adding a second CRI endpoint, not swapping the first.

```plain
systemctl is-active docker && docker info 2>/dev/null | grep 'Server Version'
```{{exec}}

```plain
cat /etc/crictl.yaml 2>/dev/null; ls -l /run/containerd/containerd.sock
```{{exec}}

### 🎯 Your Tasks

1. Install **cri-dockerd v0.4.10** from the upstream **release tarball** (`cri-dockerd-0.4.10.amd64.tgz`, not a `.deb` or `.rpm`), with the binary at **`/usr/local/bin/cri-dockerd`**.
2. Install the upstream **systemd unit files** `cri-docker.service` and `cri-docker.socket` from the same tag (`packaging/systemd/` at `v0.4.10`) into **`/etc/systemd/system/`**, and change `ExecStart` so that it:
   - runs **`/usr/local/bin/cri-dockerd`** (the upstream file assumes `/usr/bin`)
   - adds **`--pod-infra-container-image=<image>`**, where `<image>` is the exact pause image **kubeadm uses for this cluster's Kubernetes version**
3. **Enable** both units, and start the socket. The service should start through socket activation (or directly, either works). Make sure the running process actually has your flag.
4. Prove CRI works: using `crictl` against **`unix:///run/cri-dockerd.sock`**, check the runtime's version, then **pull `docker.io/library/alpine:3.21` through CRI**. Afterwards it must show up in `docker image ls`.
5. Leave the kubelet on containerd.

### ✅ Validate it yourself

```plain
systemctl status cri-docker.socket cri-docker.service --no-pager
```{{exec}}

```plain
crictl --runtime-endpoint unix:///run/cri-dockerd.sock --image-endpoint unix:///run/cri-dockerd.sock version
```{{exec}}

```plain
docker image ls alpine
```{{exec}}

⚠️ **Tempting wrong answer:** `crictl --runtime-endpoint unix:///run/cri-dockerd.sock pull ...` on its own. Look at `/etc/crictl.yaml`: it sets an **`image-endpoint`** too, and image commands use that. Without `--image-endpoint`, your "pull through cri-dockerd" quietly goes into **containerd**, and `docker image ls` stays empty.

> **If CHECK does not pass**, run `why`{{exec}}.

<br>

<details><summary>💡 Tip: finding kubeadm's pause image</summary>

kubeadm can tell you every image it uses for a given version, offline:

```plain
kubeadm config images list --kubernetes-version "$(kubeadm version -o short)"
```{{exec}}

If cri-dockerd's built-in default pause image differs from the one your Kubernetes version expects, Pod sandboxes end up on an image nobody pre-pulled or patched. Pinning it keeps both runtimes on the same sandbox image.

</details>

<details><summary>💡 Tip: what socket activation buys you</summary>

With `cri-docker.socket` enabled, **systemd** owns `/run/cri-dockerd.sock` from early boot and starts `cri-docker.service` on the first connection, passing it the already-open socket (that's what `--container-runtime-endpoint fd://` means). Clients never race a daemon that's still starting. The socket unit sets the file's group to `docker`, so that group must exist.

After editing a unit file, `systemctl daemon-reload` is what makes systemd re-read it. A *running* service keeps its old command line until it's restarted.

</details>

<details><summary>✅ Solution</summary>

```plain
cd /tmp && curl -fLO https://github.com/Mirantis/cri-dockerd/releases/download/v0.4.10/cri-dockerd-0.4.10.amd64.tgz
tar -xzf cri-dockerd-0.4.10.amd64.tgz
install -m 0755 cri-dockerd/cri-dockerd /usr/local/bin/cri-dockerd
cri-dockerd --version
```{{exec}}

```plain
for U in cri-docker.service cri-docker.socket; do
  curl -fsSL -o /etc/systemd/system/$U https://raw.githubusercontent.com/Mirantis/cri-dockerd/v0.4.10/packaging/systemd/$U
done
```{{exec}}

```plain
PAUSE=$(kubeadm config images list --kubernetes-version "$(kubeadm version -o short)" | grep /pause:)
sed -i "s#^ExecStart=.*#ExecStart=/usr/local/bin/cri-dockerd --container-runtime-endpoint fd:// --pod-infra-container-image=${PAUSE}#" /etc/systemd/system/cri-docker.service
grep ^ExecStart /etc/systemd/system/cri-docker.service
```{{exec}}

```plain
systemctl daemon-reload
systemctl enable cri-docker.service
systemctl enable --now cri-docker.socket
```{{exec}}

```plain
crictl -r unix:///run/cri-dockerd.sock -i unix:///run/cri-dockerd.sock version
crictl -r unix:///run/cri-dockerd.sock -i unix:///run/cri-dockerd.sock pull docker.io/library/alpine:3.21
docker image ls alpine
```{{exec}}

</details>
