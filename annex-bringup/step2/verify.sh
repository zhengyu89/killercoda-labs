#!/bin/bash
#
# Every exit path below says why. Killercoda only reads the exit code, so the
# explanation is written to /root/.check and the learner reads it with `why`.
LOG=/root/.check
STEP="Step 2 · A second runtime: cri-dockerd from the tarball"
: > "$LOG"
fail() { { echo "x $STEP"; echo; printf '%s\n' "$@"; } | tee "$LOG"; exit 1; }
pass() { echo "OK $STEP -- passed." | tee "$LOG"; exit 0; }
R=""

BIN=/usr/local/bin/cri-dockerd
WANT_VER=0.4.10
SOCK=unix:///run/cri-dockerd.sock
UNIT=/etc/systemd/system/cri-docker.service
PAUSE=$(kubeadm config images list --kubernetes-version "$(kubeadm version -o short 2>/dev/null)" 2>/dev/null | grep '/pause:')

# The argv systemd will use, not merely what the file says -- a unit edited
# without daemon-reload still has its old command line.
execstart() { systemctl show cri-docker.service -p ExecStart --value 2>/dev/null | sed -n 's/.*argv\[\]=\([^;]*\);.*/\1/p' | head -1; }
crictl_d() { crictl --runtime-endpoint "$SOCK" --image-endpoint "$SOCK" --timeout 10s "$@"; }

for _ in $(seq 1 6); do
  [ -x "$BIN" ] || { R="nobin"; sleep 5; continue; }
  VER=$("$BIN" --version 2>&1 | head -1)
  echo "$VER" | grep -q "$WANT_VER" || { R="binver"; sleep 5; continue; }

  FRAG=$(systemctl show cri-docker.service -p FragmentPath --value 2>/dev/null)
  SFRAG=$(systemctl show cri-docker.socket -p FragmentPath --value 2>/dev/null)
  [ "$FRAG" == "$UNIT" ] && [ "$SFRAG" == "/etc/systemd/system/cri-docker.socket" ] \
    || { R="nounits"; sleep 5; continue; }

  ARGV=$(execstart)
  [ "${ARGV%% *}" == "$BIN" ] || { R="execpath"; sleep 5; continue; }
  [ -n "$PAUSE" ] || { R="nopause"; break; }
  echo " $ARGV " | grep -Eq -- "--pod-infra-container-image(=| )${PAUSE//./\\.} " || { R="pauseflag"; sleep 5; continue; }

  SEN=$(systemctl is-enabled cri-docker.socket 2>/dev/null)
  VEN=$(systemctl is-enabled cri-docker.service 2>/dev/null)
  [ "$SEN" == "enabled" ] && [ "$VEN" == "enabled" ] || { R="notenabled"; sleep 5; continue; }
  SACT=$(systemctl is-active cri-docker.socket 2>/dev/null)
  [ "$SACT" == "active" ] || { R="socketdown"; sleep 5; continue; }

  # Talking to the socket starts the service if it is not running yet.
  CVER=$(crictl_d version 2>&1)
  echo "$CVER" | grep -Eq 'RuntimeName:[[:space:]]+docker' || { R="nocri"; sleep 5; continue; }

  PID=$(systemctl show cri-docker.service -p MainPID --value 2>/dev/null)
  CMD=$([ -n "$PID" ] && [ "$PID" != "0" ] && tr '\0' ' ' < "/proc/$PID/cmdline" 2>/dev/null)
  echo " $CMD" | grep -Eq -- "--pod-infra-container-image(=| )${PAUSE//./\\.}( |$)" || { R="stalerun"; sleep 5; continue; }

  docker image inspect docker.io/library/alpine:3.21 >/dev/null 2>&1 \
    || docker image inspect alpine:3.21 >/dev/null 2>&1 || { R="noimage"; sleep 5; continue; }

  RT=$(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.containerRuntimeVersion}' 2>/dev/null)
  echo "$RT" | grep -q '^containerd://' || { R="kubeletmoved"; sleep 5; continue; }

  pass
done

case "$R" in
  nobin) fail \
    "$BIN does not exist or is not executable." \
    "" \
    "The release tarball unpacks to cri-dockerd/cri-dockerd:" \
    "  curl -fLO https://github.com/Mirantis/cri-dockerd/releases/download/v${WANT_VER}/cri-dockerd-${WANT_VER}.amd64.tgz" \
    "  tar -xzf cri-dockerd-${WANT_VER}.amd64.tgz && install -m 0755 cri-dockerd/cri-dockerd $BIN" ;;
  binver) fail \
    "$BIN reports '${VER}', not v${WANT_VER}." ;;
  nounits) fail \
    "systemd is not loading the cri-docker units from /etc/systemd/system/." \
    "" \
    "  cri-docker.service loaded from: ${FRAG:-<not found>}" \
    "  cri-docker.socket  loaded from: ${SFRAG:-<not found>}" \
    "" \
    "Put both upstream files (packaging/systemd/ at tag v${WANT_VER}) in" \
    "/etc/systemd/system/, then: systemctl daemon-reload" ;;
  execpath) fail \
    "cri-docker.service runs '${ARGV%% *}', not $BIN." \
    "" \
    "  systemctl cat cri-docker.service | grep ExecStart" \
    "" \
    "The upstream unit assumes a package install in /usr/bin. Edit ExecStart," \
    "then 'systemctl daemon-reload' -- systemd keeps the old one until you do." ;;
  nopause) fail \
    "Could not work out kubeadm's pause image on this machine:" \
    "  kubeadm config images list --kubernetes-version \"\$(kubeadm version -o short)\"" ;;
  pauseflag) fail \
    "cri-docker.service does not pass --pod-infra-container-image=${PAUSE}." \
    "" \
    "  systemd will run: ${ARGV:-<nothing>}" \
    "" \
    "The value must be the pause image kubeadm lists for this cluster's version." \
    "If the file already has it, you have not run 'systemctl daemon-reload'." ;;
  notenabled) fail \
    "The units are not both enabled (socket: ${SEN:-?}, service: ${VEN:-?})." \
    "" \
    "Enabled means 'started at boot'; without it the CRI endpoint is gone after" \
    "the next restart:" \
    "  systemctl enable cri-docker.service" \
    "  systemctl enable --now cri-docker.socket" ;;
  socketdown) fail \
    "cri-docker.socket is ${SACT:-inactive}." \
    "" \
    "  systemctl status cri-docker.socket --no-pager" \
    "" \
    "'Failed to resolve group docker' means the docker group is missing." ;;
  nocri) fail \
    "Nothing answers CRI on $SOCK as the docker runtime:" \
    "" \
    "$(echo "$CVER" | head -4 | sed 's/^/  /')" \
    "" \
    "  systemctl status cri-docker.service --no-pager" \
    "  journalctl -u cri-docker.service -n 20 --no-pager" ;;
  stalerun) fail \
    "The cri-dockerd process that is running does not have your pause image flag." \
    "" \
    "  running: ${CMD:-<no process>}" \
    "" \
    "The unit file is right, but this process started before you changed it." \
    "Restart it so it picks up the new command line:" \
    "  systemctl restart cri-docker.service" ;;
  noimage) fail \
    "Docker has no alpine:3.21 image." \
    "" \
    "If you pulled with only --runtime-endpoint, the pull went to the" \
    "image-endpoint in /etc/crictl.yaml -- containerd -- not to Docker:" \
    "  crictl -r $SOCK -i $SOCK pull docker.io/library/alpine:3.21" \
    "  docker image ls alpine" ;;
  kubeletmoved) fail \
    "The node now reports runtime '${RT}'. The kubelet must stay on containerd." \
    "" \
    "cri-dockerd was meant to be a second CRI endpoint for tooling, not a" \
    "replacement for the kubelet's runtime. Check what you changed in" \
    "/var/lib/kubelet/kubeadm-flags.env or /var/lib/kubelet/config.yaml." ;;
  *) fail "Unexpected state -- rerun the check." ;;
esac
