## Task 4: Pod vs Service

Run both requests from the node terminal.

1. Pick any one Pod of Deployment `web` in the `shop` namespace. Send an HTTP request to its Pod IP on port `8080` and save the response to `/root/pod-output.txt`.
2. Send an HTTP request to Service `web-svc` (its ClusterIP, port `80`) and save the response to `/root/svc-output.txt`.

```plain
cat /root/pod-output.txt /root/svc-output.txt
```{{exec}}

<details><summary>Solution</summary>

```plain
kubectl -n shop get pods -o wide
POD_IP=$(kubectl -n shop get pods -l app=web -o jsonpath='{.items[0].status.podIP}')
curl -s http://$POD_IP:8080 > /root/pod-output.txt
```{{exec}}

```plain
SVC_IP=$(kubectl -n shop get svc web-svc -o jsonpath='{.spec.clusterIP}')
curl -s http://$SVC_IP:80 > /root/svc-output.txt
```{{exec}}

Run the Service request a few times. A different Pod can answer each time, because the Service load-balances across all of its endpoints:

```plain
for i in 1 2 3 4 5 6; do curl -s http://$SVC_IP; done
```{{exec}}

</details>
