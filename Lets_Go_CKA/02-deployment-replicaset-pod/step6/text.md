## Task 5: CreateContainerError

A Deployment named `toolbox` in the `tools` namespace has a Pod stuck in `CreateContainerError`.

1. Find out why the container cannot be created.
2. Fix the Deployment so its Pod is Running and Ready.
3. The container must use image `busybox:1.36` and run the command `sleep 3600`.

```plain
kubectl -n tools get pods -l app=toolbox
```{{exec}}

<details><summary>Solution</summary>

The Pod events show the error:

```plain
kubectl -n tools describe pod -l app=toolbox | grep -A10 Events
```{{exec}}

`no command specified`: the image defines no default command, and the Pod spec does not set one either. Changing only the image is not enough. `busybox` defaults to `sh`, which exits at once and gives you `CrashLoopBackOff`. Set both the image and the command:

```plain
kubectl -n tools patch deploy toolbox --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/image","value":"busybox:1.36"},
  {"op":"add","path":"/spec/template/spec/containers/0/command","value":["sleep","3600"]}
]'
kubectl -n tools rollout status deploy/toolbox
```{{exec}}

Or run `kubectl -n tools edit deploy toolbox` and make the same two changes.

</details>
