## Task 3: Find the nodePort

1. Find the `nodePort` that Kubernetes assigned to Service `web-nodeport` in the `shop` namespace.
2. Write only the port number to `/root/nodeport.txt`.
3. Check that the application answers on that port on the node:

```plain
curl http://localhost:$(cat /root/nodeport.txt)
```{{exec}}

<details><summary>Solution</summary>

The `PORT(S)` column shows `80:<nodePort>/TCP`:

```plain
kubectl -n shop get svc web-nodeport
```{{exec}}

Or extract only the number:

```plain
kubectl -n shop get svc web-nodeport -o jsonpath='{.spec.ports[0].nodePort}' > /root/nodeport.txt
cat /root/nodeport.txt
```{{exec}}

</details>
