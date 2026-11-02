#!/bin/bash
#
# Every exit path below says why. Killercoda only reads the exit code, so the
# explanation is written to /root/.check and the learner reads it with `why`.
LOG=/root/.check
STEP="Step 3 · Network by hand: install a CNI without an operator"
: > "$LOG"
fail() { { echo "x $STEP"; echo; printf '%s\n' "$@"; } | tee "$LOG"; cleanup; exit 1; }
pass() { echo "OK $STEP -- passed." | tee "$LOG"; cleanup; exit 0; }
R=""

BINDIR=/opt/cni/bin
CONF=/etc/cni/net.d/10-annex.conflist
WANT_VER=v1.9.1
PROBE=annex-cni-probe
cleanup() { kubectl delete pod "$PROBE" -n default --wait=false >/dev/null 2>&1; }

NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
CIDR=$(kubectl get node "$NODE" -o jsonpath='{.spec.podCIDR}' 2>/dev/null)

# in_cidr IP CIDR -> exit 0 if the address is inside the network.
in_cidr() { python3 -c 'import ipaddress,sys; sys.exit(0 if ipaddress.ip_address(sys.argv[1]) in ipaddress.ip_network(sys.argv[2]) else 1)' "$1" "$2" 2>/dev/null; }

for _ in $(seq 1 18); do
  [ -n "$CIDR" ] || { R="nocidr"; break; }

  MISSBIN=""
  for P in bridge host-local portmap loopback; do [ -x "$BINDIR/$P" ] || MISSBIN="$MISSBIN $P"; done
  [ -z "$MISSBIN" ] || { R="nobins"; sleep 5; continue; }
  BVER=$("$BINDIR/bridge" 2>&1 | head -1)
  echo "$BVER" | grep -q "$WANT_VER" || { R="binver"; sleep 5; continue; }

  [ -s "$CONF" ] || { R="noconf"; sleep 5; continue; }
  # The config, flattened to key=value lines. A parse error is its own answer.
  PARSED=$(python3 - "$CONF" <<'PY' 2>&1
import json, sys
c = json.load(open(sys.argv[1]))
pl = c.get("plugins") or []
types = [p.get("type") for p in pl]
br = next((p for p in pl if p.get("type") == "bridge"), {})
pm = next((p for p in pl if p.get("type") == "portmap"), {})
ipam = br.get("ipam") or {}
subnets = [r.get("subnet") for rs in ipam.get("ranges") or [] for r in rs]
if ipam.get("subnet"):
    subnets.append(ipam["subnet"])
routes = [r.get("dst") for r in ipam.get("routes") or []]
print("cniVersion=%s" % c.get("cniVersion"))
print("name=%s" % c.get("name"))
print("types=%s" % ",".join(str(t) for t in types))
print("bridge=%s" % br.get("bridge"))
print("isGateway=%s" % br.get("isGateway"))
print("ipMasq=%s" % br.get("ipMasq"))
print("hairpinMode=%s" % br.get("hairpinMode"))
print("ipamType=%s" % ipam.get("type"))
print("subnets=%s" % ",".join(str(s) for s in subnets))
print("defaultRoute=%s" % ("0.0.0.0/0" in routes))
print("portMappings=%s" % (pm.get("capabilities") or {}).get("portMappings"))
PY
)
  echo "$PARSED" | grep -q '^name=' || { R="badjson"; sleep 5; continue; }
  val() { echo "$PARSED" | sed -n "s/^$1=//p"; }
  BAD=""
  want() { [ "$(val "$1")" == "$2" ] || BAD="${BAD}  $1: '$(val "$1")' (want '$2')"$'\n'; }
  want cniVersion 1.0.0
  want name annex-net
  want types bridge,portmap
  want bridge annex0
  want isGateway True
  want ipMasq True
  want hairpinMode True
  want ipamType host-local
  want defaultRoute True
  want portMappings True
  [ -z "$BAD" ] || { R="conffields"; sleep 5; continue; }
  SUBNETS=$(val subnets)
  [ "$SUBNETS" == "$CIDR" ] || { R="subnet"; sleep 5; continue; }

  FIRST=$(ls /etc/cni/net.d/ 2>/dev/null | grep -E '\.(conf|conflist|json)$' | sort | head -1)
  [ "$FIRST" == "10-annex.conflist" ] || { R="shadowed"; sleep 5; continue; }

  # By hand means no CNI DaemonSet; kube-proxy is the only one kubeadm makes.
  DS=$(kubectl get ds -A --no-headers 2>/dev/null | awk '$2!="kube-proxy" {print $1"/"$2}')
  [ -z "$DS" ] || { R="manifest"; sleep 5; continue; }

  READY=$(kubectl get node "$NODE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  [ "$READY" == "True" ] || { R="notready"; sleep 5; continue; }

  DNS_READY=$(kubectl -n kube-system get deploy coredns -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  DNS_WANT=$(kubectl -n kube-system get deploy coredns -o jsonpath='{.spec.replicas}' 2>/dev/null)
  [ -n "$DNS_READY" ] && [ "$DNS_READY" == "$DNS_WANT" ] || { R="dns"; sleep 5; continue; }
  OUTSIDE=""
  for IP in $(kubectl -n kube-system get pods -l k8s-app=kube-dns -o jsonpath='{.items[*].status.podIP}' 2>/dev/null); do
    in_cidr "$IP" "$CIDR" || OUTSIDE="$OUTSIDE $IP"
  done
  [ -z "$OUTSIDE" ] || { R="dnsip"; sleep 5; continue; }

  ip -4 addr show annex0 >/dev/null 2>&1 || { R="nobridge"; sleep 5; continue; }
  # The bridge keeps whatever address the first Pod gave it. A config whose
  # subnet changed afterwards leaves it stale, and every new sandbox fails.
  GW=$(python3 -c 'import ipaddress,sys; n=ipaddress.ip_network(sys.argv[1]); print("%s/%d" % (next(n.hosts()), n.prefixlen))' "$CIDR" 2>/dev/null)
  BRADDR=$(ip -4 -o addr show annex0 2>/dev/null | awk '{print $4}' | tr '\n' ' ' | sed 's/ $//')
  [ "$BRADDR" == "$GW" ] || { R="bridgeaddr"; sleep 5; continue; }

  # End to end, from a Pod of our own: an address from this node's slice, DNS,
  # and the API server's Service reached through the bridge.
  kubectl get pod "$PROBE" -n default >/dev/null 2>&1 || \
    kubectl run "$PROBE" -n default --image=curlimages/curl:8.11.1 --restart=Never \
      --command -- sleep 600 >/dev/null 2>&1
  kubectl -n default wait --for=condition=Ready "pod/$PROBE" --timeout=30s >/dev/null 2>&1 || { R="probepod"; sleep 5; continue; }
  PIP=$(kubectl -n default get pod "$PROBE" -o jsonpath='{.status.podIP}' 2>/dev/null)
  in_cidr "$PIP" "$CIDR" || { R="probeip"; sleep 5; continue; }
  CODE=$(kubectl -n default exec "$PROBE" -- curl -sk -m 8 -o /dev/null -w '%{http_code}' https://kubernetes.default.svc/version 2>&1)
  [ "$CODE" == "200" ] || { R="probecurl"; sleep 5; continue; }

  pass
done

case "$R" in
  nocidr) fail \
    "Node ${NODE:-?} has no spec.podCIDR, so there is nothing to check against." \
    "" \
    "This comes from the lab's setup, not from you -- see /root/.lab/init.log." ;;
  nobins) fail \
    "These plugin binaries are missing from ${BINDIR}:${MISSBIN}" \
    "" \
    "The reference plugins release has all of them (loopback included):" \
    "  curl -fLO https://github.com/containernetworking/plugins/releases/download/${WANT_VER}/cni-plugins-linux-amd64-${WANT_VER}.tgz" \
    "  tar -xzf cni-plugins-linux-amd64-${WANT_VER}.tgz -C ${BINDIR}" ;;
  binver) fail \
    "${BINDIR}/bridge reports '${BVER}', not ${WANT_VER}." ;;
  noconf) fail \
    "${CONF} does not exist or is empty." ;;
  badjson) fail \
    "${CONF} is not valid JSON:" \
    "" \
    "$(echo "$PARSED" | tail -2 | sed 's/^/  /')" \
    "" \
    "  python3 -m json.tool ${CONF}" ;;
  conffields) fail \
    "${CONF} is valid JSON, but these don't match:" \
    "" \
    "$BAD" \
    "Booleans are JSON true/false, not strings. The plugins list is the chain," \
    "in order: bridge first, then portmap." ;;
  subnet) fail \
    "host-local hands out '${SUBNETS:-<nothing>}', but this node's Pod CIDR is ${CIDR}." \
    "" \
    "  kubectl get node ${NODE} -o jsonpath='{.spec.podCIDR}'" \
    "" \
    "The cluster-wide 10.77.0.0/16 works on one node and collides on two:" \
    "host-local allocates per node, and only spec.podCIDR is this node's own." ;;
  shadowed) fail \
    "containerd will load '${FIRST}', not 10-annex.conflist." \
    "" \
    "It uses the config that sorts first in /etc/cni/net.d:" \
    "  ls /etc/cni/net.d/" ;;
  manifest) fail \
    "There is a DaemonSet besides kube-proxy -- looks like a CNI was installed from a manifest:" \
    "" \
    "$(echo "$DS" | sed 's/^/  /')" \
    "" \
    "This step is about doing it by hand: binaries in /opt/cni/bin, one config" \
    "file in /etc/cni/net.d. Remove what the manifest installed." ;;
  notready) fail \
    "Node ${NODE} is not Ready yet." \
    "" \
    "  kubectl describe node ${NODE} | grep -A1 -i ready" \
    "  journalctl -u containerd -n 20 --no-pager | grep -i cni" ;;
  dns) fail \
    "CoreDNS is not ready (${DNS_READY:-0} of ${DNS_WANT:-?})." \
    "" \
    "  kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide" \
    "  kubectl -n kube-system describe pod -l k8s-app=kube-dns | grep -A10 Events" \
    "" \
    "'failed to find plugin' in the events means a binary is missing from" \
    "/opt/cni/bin; 'failed to set bridge addr' usually means a bad subnet." ;;
  dnsip) fail \
    "CoreDNS Pods have addresses outside ${CIDR}:${OUTSIDE}" \
    "" \
    "They were probably created before your final config. Recreate them:" \
    "  kubectl -n kube-system rollout restart deployment coredns" ;;
  nobridge) fail \
    "There is no annex0 bridge on the node." \
    "" \
    "The bridge plugin creates it with the first Pod. If CoreDNS is running," \
    "it is using a different bridge name -- check \"bridge\" in the config:" \
    "  ip -br link show type bridge" ;;
  bridgeaddr) fail \
    "Bridge annex0 has address '${BRADDR:-<none>}', but your config's gateway is ${GW}." \
    "" \
    "The bridge plugin assigns the gateway address once, when the first Pod" \
    "starts, and never changes it. The subnet in the config changed after that," \
    "so every new Pod now fails with 'already has an IP address different from'." \
    "Remove the stale bridge and let the Pods rebuild it:" \
    "  ip link delete annex0" \
    "  kubectl -n kube-system rollout restart deployment coredns" ;;
  probepod) fail \
    "A test Pod could not become Ready on this network." \
    "" \
    "  kubectl -n default describe pod ${PROBE} | grep -A10 Events" ;;
  probeip) fail \
    "A new Pod got address '${PIP}', outside this node's Pod CIDR ${CIDR}." ;;
  probecurl) fail \
    "A Pod on your network could not reach https://kubernetes.default.svc (got '${CODE}')." \
    "" \
    "DNS and Service traffic both cross the bridge and come back. Check:" \
    "  isGateway: true   -- the Pods' default route needs a gateway" \
    "  ipMasq: true      -- traffic leaving the Pod network must be masqueraded" \
    "  hairpinMode: true -- a Pod reaching a Service that lands on itself" \
    "  sysctl net.bridge.bridge-nf-call-iptables   -- must be 1 for kube-proxy" ;;
  *) fail "Unexpected state -- rerun the check." ;;
esac
