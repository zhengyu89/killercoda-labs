## Task 7: Cross-namespace Service discovery

Service `api` runs in the `backend` namespace. Pod `client` runs in the `frontend` namespace.

1. From inside Pod `client`, send an HTTP request to Service `api` using its DNS name.
2. Save the response to `/root/cross-ns.txt` on the node.

Try the short name first and see why it fails:

```plain
kubectl -n frontend exec client -- wget -qO- -T 3 http://api
```{{exec}}

<details><summary>Solution</summary>

A short name like `api` only resolves inside the client's own namespace. To reach another namespace, add the namespace: `api.backend`, or the full name `api.backend.svc.cluster.local`.

```plain
kubectl -n frontend exec client -- wget -qO- http://api.backend.svc.cluster.local > /root/cross-ns.txt
cat /root/cross-ns.txt
```{{exec}}

</details>
