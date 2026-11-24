## Task 5: RunContainerError

A Deployment named `reporter` in the `ops` namespace has a Pod that cannot start. Its status switches between `RunContainerError` and `CrashLoopBackOff`.

1. Find out why the container cannot start.
2. Fix the Deployment so its Pod is Running and Ready.
3. Do not change the image. The container must still run the shell command `echo reporter started; sleep 3600`.

```plain
kubectl -n ops get pods -l app=reporter
```{{exec}}

<details><summary>Hint</summary>

The container never started, so it has no logs. Read the Events at the bottom of `kubectl describe pod`. The error names the file the kubelet could not find. Then check which shell the `busybox` image actually has.

</details>

<details><summary>Solution</summary>

The Pod events show the error:

```plain
kubectl -n ops describe pod -l app=reporter | grep -A10 Events
```{{exec}}

`exec: "/bash": stat /bash: no such file or directory`. `/bash` does not exist, and `busybox` has no bash at all. Its shell is `/bin/sh`.

Fixing only the path is not enough. Without `-c`, `sh` treats the next argument as a script file name and fails with `can't open 'echo reporter started; sleep 3600'`. The command needs to be `/bin/sh`, `-c`, then the shell command:

```plain
kubectl -n ops patch deploy reporter --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/command","value":["/bin/sh","-c","echo reporter started; sleep 3600"]}
]'
kubectl -n ops rollout status deploy/reporter
kubectl -n ops logs deploy/reporter
```{{exec}}

Or run `kubectl -n ops edit deploy reporter` and change the command to:

```yaml
command: ["/bin/sh", "-c", "echo reporter started; sleep 3600"]
```

</details>
