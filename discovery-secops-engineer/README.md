Welcome to the SecOps Engineer Discovery Lab!
This short lab will give you an initial overview of Cilium and Tetragon features specifically relevant to SecOps teams.

In particular, you will learn about:

    Connectivity Visibility with Hubble
    Cilium Network Policies
    Mutual Authentication with Cilium
    Transparent Flow Encryption with Cilium
    Runtime Security Observability with Tetragon

Securing Kubernetes

Kubernetes default settings are not automatically tailored for security sensitive environments.

It is the responsibility of the SecOps and Platform team to secure the platform.

Proper security measures are crucial to protect against data breaches, unauthorized access, and other potential risks.

In this hands-on lab, we'll explore how Cilium and Tetragon can enhance your security posture.

Network Policies

Network policies define rules and restrictions for network traffic within your Kubernetes cluster.

Without proper network policies, containers can communicate freely, potentially exposing sensitive data and services to unauthorized access.

Network policies help you control and isolate network traffic, limiting communication between pods to only what's necessary.

Cilium supports Network Policies with extended features, including DNS names and layer 7 filtering. We will explore these in the upcoming challenge.

Encryption in Cilium

Cilium actually provides two options to encrypt traffic between Cilium-managed endpoints: IPsec and WireGuard.

In this lab, we'll be using WireGuard transparent encryption to secure traffic between nodes.

Mutual Authentication

Mutual authentication ensures that both the client and the server in a communication exchange verify each other's identity.

This prevents unauthorized access and man-in-the-middle attacks, safeguarding your cluster's integrity.

Mutual authentication is a key component of a robust Kubernetes security strategy.

We will see how Cilium adds mutual authentication to the Network Policy layer in this challenge.

Ready? Let's go!

In this lab, a Kind Kubernetes cluster has been deployed, with Cilium to provide the network implementation.

In order to verify that Cilium is properly installed and functioning, enter the following in the >_ Terminal tab:

root@server:~# cilium status --wait
    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    OK
 \__/¯¯\__/    Hubble Relay:       OK
    \__/       ClusterMesh:        disabled

Deployment             hubble-ui          Desired: 1, Ready: 1/1, Available: 1/1
Deployment             cilium-operator    Desired: 1, Ready: 1/1, Available: 1/1
Deployment             hubble-relay       Desired: 1, Ready: 1/1, Available: 1/1
DaemonSet              cilium-envoy       Desired: 3, Ready: 3/3, Available: 3/3
DaemonSet              cilium             Desired: 3, Ready: 3/3, Available: 3/3
Containers:            cilium             Running: 3
                       hubble-ui          Running: 1
                       cilium-operator    Running: 1
                       cilium-envoy       Running: 3
                       hubble-relay       Running: 1
Cluster Pods:          7/7 managed by Cilium
Helm chart version:    
Image versions         cilium             quay.io/cilium/cilium:v1.16.0@sha256:46ffa4ef3cf6d8885dcc4af5963b0683f7d59daa90d49ed9fb68d3b1627fe058: 3
                       hubble-ui          quay.io/cilium/hubble-ui:v0.13.1@sha256:e2e9313eb7caf64b0061d9da0efbdad59c6c461f6ca1752768942bfeda0796c6: 1
                       hubble-ui          quay.io/cilium/hubble-ui-backend:v0.13.1@sha256:0e0eed917653441fded4e7cdb096b7be6a3bddded5a2dd10812a27b1fc6ed95b: 1
                       cilium-operator    quay.io/cilium/operator-generic:v1.16.0@sha256:d6621c11c4e4943bf2998af7febe05be5ed6fdcf812b27ad4388f47022190316: 1
                       cilium-envoy       quay.io/cilium/cilium-envoy:v1.29.7-39a2a56bbd5b3a591f69dbca51d3e30ef97e0e51@sha256:bd5ff8c66716080028f414ec1cb4f7dc66f40d2fb5a009fff187f4a9b90b566b: 3
                       hubble-relay       quay.io/cilium/hubble-relay:v1.16.0@sha256:33fca7776fc3d7b2abe08873319353806dc1c5e07e12011d7da4da05f836ce8d: 1


Now that we know that the Kubernetes cluster is ready, let's deploy an application to it.

The endor.yaml manifest will deploy a Star Wars-inspired demo application which consists of:

    an endor Namespace, containing
    a deathstar Deployment with 2 replicas (you never know if a Death Star might explode 😬)
    a Kubernetes Service to access the Death Star pods
    a tiefighter Deployment with 1 replica
    an xwing Deployment with 1 replica

Deploy the manifest with:
kubectl apply -f endor.yaml
kubectl get -f endor.yaml

Switch to the 🔗 🛰️ Hubble UI tab, a project that is part of the Cilium realm, which lets you visualize traffic in a Kubernetes cluster as a service map.

At the moment, you are seeing three pod identities in the endor namespace:

    xwing is for pods from the xwing deployment
    tiefighter represents pods from the tiefighter deployment
    deathstar represents the various pods deployed by the deathstar deployment

Both the tiefighter and xwing pods make requests to:

    the deathstar service (HTTP)
    disney.com and swapi.dev (HTTPS)

The domain names for disney.com and swapi.dev are known by Hubble because Cilium has been configured to proxy DNS traffic and cache the DNS responses from Kube DNS, providing a way to both inspect and secure traffic by DNS name.

Click on the xwing box in the service map. This filters traffic to only show flows involving the xwing identity.

Observe that all flows end with a red section, indicating that traffic coming from the xwing identity is being dropped.

You can also see at the bottom of the screen all the flow logs confirming that communications coming from the xwing identity are dropped.

This is because the endor namespace has been secured with Network Policies, allowing only specific traffic.

Click on one of the log entries to see the details. You will see the drop reason (Policy denied) as well as the traffic direction (egress). You will also see details of the source and destination identities, based on Kubernetes labels.

Navigate back to the >_ Terminal tab to view these logs in the command line with:

root@server:~# hubble observe --pod endor/xwing --type policy-verdict
Aug  8 00:19:20.281: endor/xwing-5fc94ff679-ww7f8:46602 (ID:28141) <> swapi.dev:443 (ID:16777218) policy-verdict:none EGRESS DENIED (TCP Flags: SYN)
Aug  8 00:19:22.286: endor/xwing-5fc94ff679-ww7f8:43910 (ID:28141) -> kube-system/coredns-76f75df574-jplsj:53 (ID:43683) policy-verdict:L3-L4 EGRESS ALLOWED (UDP)
Aug  8 00:19:22.287: endor/xwing-5fc94ff679-ww7f8:58250 (ID:28141) <> endor/deathstar-f449b9b55-nw5xm:80 (ID:48882) policy-verdict:none EGRESS DENIED (TCP Flags: SYN)
Aug  8 00:19:23.291: endor/xwing-5fc94ff679-ww7f8:58161 (ID:28141) -> kube-system/coredns-76f75df574-kg5w4:53 (ID:43683) policy-verdict:L3-L4 EGRESS ALLOWED (UDP)

Switch back to the 🔗 🛰️ Hubble UI tab.

Hubble features a web UI which displays a service map of the communication between pods in a namespace, in real time!

Click on the deathstar box. You can see that traffic is coming to the deathstar identity from two pods identities: xwing and tiefighter.

Note that the box tells you that traffic coming to the deathstar pods is entirely on port 80/TCP.

In the >_ Terminal tab, annotate the deathstar pods to add layer 7 visibility on 80/TCP ingress traffic, parsing it as HTTP:
root@server:~# kubectl -n endor annotate pods -l class=deathstar \
  policy.cilium.io/proxy-visibility="<Ingress/80/TCP/HTTP>"
pod/deathstar-f449b9b55-nw5xm annotated
pod/deathstar-f449b9b55-xm8jz annotated

You can even see that the /v1/request-landing HTTP path was called, using the POST method!

This is because the deathstar pods have been annotated to add layer 7 visibility on port 80. This can also be achieved with layer 7 network policies.

Click on the tiefighter box. All logs at the bottom of the screen are green, indicating that traffic is allowed and forwarded to the three destinations.

In addition, notice that the segment between the tiefighter and deathstar boxes is marked with a lock icon 🔒.

This means that this specific flow is secured with mutual authentication, an extra parameter in the Cilium Network Policy between these two identities.

In the >_ Terminal tab, check the Network Policy with:

root@server:~# kubectl -n endor get ciliumnetworkpolicy deathstar -o yaml | yq '.spec'
endpointSelector:
  matchLabels:
    class: deathstar
    org: empire
ingress:
  - authentication:
      mode: required
    fromEndpoints:
      - matchLabels:
          k8s:app.kubernetes.io/name: tiefighter
          k8s:class: tiefighter
          k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name: endor
          k8s:io.kubernetes.pod.namespace: endor
          k8s:org: empire
    toPorts:
      - ports:
          - port: "80"


Activating mutual authentication in Cilium is that simple!

In Cilium, Mutual Authentication is implemented at kernel level using eBPF instead of relying on sidecar proxies. This also makes it totally transparent and protocol-agnostic.

Mutual authentication is usually typically implemented using mTLS, which provides both authentication and flow encryption. In Cilium, both features are provided separately. In this track, Cilium has been configured to encrypt traffic using WireGuard.

Navigate back to the >_ Terminal tab and verify this setting with:
root@server:~# cilium config view | grep enable-wireguard
enable-wireguard                                  true

This means that all traffic between pods located on different nodes of the cluster will be encrypted by WireGuard.

In this setup, we have also enabled node-to-node encryption, so that cross-node communication between any processes on Kubernetes nodes will be encrypted with WireGuard. Check this setting with:
root@server:~# cilium config view | grep encrypt-node
encrypt-node                                      true

Runtime Security Visibility and Enforcement with Tetragon

We've seen how to secure traffic using Network Policies, Mutual Authentication, and Encryption in transit.

But what about runtime security? If an attacker were to execute a command in a pod, could we find the link with the resulting actions and network flows?

Let's find out, using Cilium Tetragon!

You're getting a radio call from the Death Star Security team. It's Darth Vader. Quick, answer the call in the >_ Terminal tab with:
starcom --interactive

The Death Star security team has noticed that a Death Star pod has exploded!

Check it in the >_ Terminal tab with:
root@server:~# kubectl -n endor get pod -l class=deathstar
NAME                        READY   STATUS    RESTARTS      AGE
deathstar-f449b9b55-nw5xm   1/1     Running   0             19m
deathstar-f449b9b55-xm8jz   1/1     Running   1 (52s ago)   19m

You will see that the deathstar-f449b9b55-xm8jz pod has recently restarted (it says 1 in the RESTARTS column).

What could have happened?

Let's check the logs from the previous instance of the pod:
root@server:~# kubectl -n endor logs deathstar-f449b9b55-xm8jz --previous
2024/08/08 00:15:51 Serving deathstar at http://[::]:80
panic: deathstar exploded

goroutine 538 [running]:
github.com/cilium/starwars-docker/restapi.configureAPI.func2.1()
        /app/restapi/configure_deathstar.go:82 +0x31
created by github.com/cilium/starwars-docker/restapi.configureAPI.func2
        /app/restapi/configure_deathstar.go:80 +0x25

Switch to the 🔗 🛰️ Hubble UI tab, and click on the deathstar box.

Notice that there are now two HTTP requests listed. The new one is a PUT request on /v1/exhaust-port.

Oh no! Now you vaguely remember that the Death Star engineers told you last week about a known security vulnerability involving the Death Star's exhaust port, and it was clearly planned to patch it. Soon. Promise 😬

In the >_ Terminal tab, filter flows to the Death Star using the /v1/exhaust-port path:
root@server:~# hubble observe \
  --to-pod endor/deathstar \
  --http-path /v1/exhaust-port
Aug  8 00:34:40.187: endor/tiefighter-7c8d559f5d-5962f:60564 (ID:16845) -> endor/deathstar-f449b9b55-xm8jz:80 (ID:48882) http-request FORWARDED (HTTP/1.1 PUT http://deathstar.endor.svc.cluster.local/v1/exhaust-port)      

It shows that this request came from the tiefighter-7c8d559f5d-5962f pod.

Wait — that means it wasn't even a rebel ship that destroyed the Empire's Death Star! It was an Empire vessel that destroyed its own! (This makes sense, since we saw earlier that X-Wings are not allowed to access the Death Star thanks to Network Policies in place)

We know which pod was used to launch the attack, but could we see all the events that happened on that pod?

For this, we need a tool that can give us observability at the runtime level. Let's use Tetragon, an eBPF-based security observability tool that is part of the Cilium family.

Let's inspect Tetragon's logs for the node where the tiefighter-7c8d559f5d-5962f pod is running.

Start by finding out which node that is:
root@server:~# kubectl -n endor get pod tiefighter-7c8d559f5d-5962f -o wide
NAME                          READY   STATUS    RESTARTS   AGE   IP             NODE          NOMINATED NODE   READINESS GATES
tiefighter-7c8d559f5d-5962f   1/1     Running   0          24m   10.244.2.185   kind-worker   <none>           <none>

Now that we know that it runs on kind-worker, let's inspect and filter the Tetragon logs.

Find out which Tetragon pod is running on the kind-worker node:
root@server:~# kubectl -n kube-system get po -l app.kubernetes.io/name=tetragon \
  --field-selector spec.nodeName=kind-worker -o name
pod/tetragon-vq2vd

Next, inspect the Tetragon logs and find the events relating to /v1/exhaust-port and the tiefighter-7c8d559f5d-5962f pod.

We will look for occurrences of /v1/exhaust-port in the Tetragon logs on the node, then pipe the resulting JSON logs into the tetra CLI provided in the image in order to display a compact and colored view of the logs (instead of raw JSON) for better readability:

root@server:~# kubectl -n kube-system exec -ti pod/tetragon-vq2vd -c tetragon -- \
  sh -c 'cat /var/run/cilium/tetragon/tetragon*.log | \
    grep /v1/exhaust-port | \
    tetra getevents -o compact --pods tiefighter-7c8d559f5d-5962f'
🚀 process endor/tiefighter-7c8d559f5d-5962f /usr/bin/curl -s -XPUT deathstar.endor.svc.cluster.local/v1/exhaust-port 
🔌 connect endor/tiefighter-7c8d559f5d-5962f /usr/bin/curl tcp 10.244.2.185:60564 -> 10.244.2.206:80 
🧹 close   endor/tiefighter-7c8d559f5d-5962f /usr/bin/curl tcp 10.244.2.185:60564 -> 10.244.2.206:80 
💥 exit    endor/tiefighter-7c8d559f5d-5962f /usr/bin/curl -s -XPUT deathstar.endor.svc.cluster.local/v1/exhaust-port 0 

root@server:~# kubectl -n kube-system exec pod/tetragon-vq2vd -c tetragon -- \
  sh -c 'cat /var/run/cilium/tetragon/tetragon*.log' | \
    grep '/v1/exhaust-port' | \
    jq '.process_exec.process | select(.pod.name=="tiefighter-7c8d559f5d-5962f")'
{
  "exec_id": "a2luZC13b3JrZXI6NzgwOTU0Njg0MjkzMTozNTQ3Nw==",
  "pid": 35477,
  "uid": 0,
  "cwd": "/",
  "binary": "/usr/bin/curl",
  "arguments": "-s -XPUT deathstar.endor.svc.cluster.local/v1/exhaust-port",
  "flags": "execve rootcwd clone",
  "start_time": "2024-08-08T00:34:40.184013787Z",
  "auid": 4294967295,
  "pod": {
    "namespace": "endor",
    "name": "tiefighter-7c8d559f5d-5962f",
    "container": {
      "id": "containerd://00da5619d8770ead6b24559d09fcdf8c058e19263bf7d7476ec5a40274aa96e9",
      "name": "starship",
      "image": {
        "id": "docker.io/tgraf/netperf@sha256:8e86f744bfea165fd4ce68caa05abc96500f40130b857773186401926af7e9e6",
        "name": "docker.io/tgraf/netperf:latest"
      },
      "start_time": "2024-08-08T00:15:52Z",
      "pid": 2717
    },
    "pod_labels": {
      "app.kubernetes.io/name": "tiefighter",
      "class": "tiefighter",
      "org": "empire",
      "pod-template-hash": "7c8d559f5d"
    },
    "workload": "tiefighter",
    "workload_kind": "Deployment"
  },
  "docker": "00da5619d8770ead6b24559d09fcdf8",
  "parent_exec_id": "a2luZC13b3JrZXI6NjY3NjQwMTMwNTA1MDoyMDI1MA==",
  "cap": {
    "permitted": [
      "CAP_CHOWN",
      "DAC_OVERRIDE",
      "CAP_FOWNER",
      "CAP_FSETID",
      "CAP_KILL",
      "CAP_SETGID",
      "CAP_SETUID",
      "CAP_SETPCAP",
      "CAP_NET_BIND_SERVICE",
      "CAP_NET_RAW",
      "CAP_SYS_CHROOT",
      "CAP_MKNOD",
      "CAP_AUDIT_WRITE",
      "CAP_SETFCAP"
    ],
    "effective": [
      "CAP_CHOWN",
      "DAC_OVERRIDE",
      "CAP_FOWNER",
      "CAP_FSETID",
      "CAP_KILL",
      "CAP_SETGID",
      "CAP_SETUID",
      "CAP_SETPCAP",
      "CAP_NET_BIND_SERVICE",
      "CAP_NET_RAW",
      "CAP_SYS_CHROOT",
      "CAP_MKNOD",
      "CAP_AUDIT_WRITE",
      "CAP_SETFCAP"
    ]
  },
  "ns": {
    "uts": {
      "inum": 4026533742
    },
    "ipc": {
      "inum": 4026533743
    },
    "mnt": {
      "inum": 4026533758
    },
    "pid": {
      "inum": 4026533759
    },
    "pid_for_children": {
      "inum": 4026533759
    },
    "net": {
      "inum": 4026533593
    },
    "time": {
      "inum": 4026531834,
      "is_host": true
    },
    "time_for_children": {
      "inum": 4026531834,
      "is_host": true
    },
    "cgroup": {
      "inum": 4026533760
    },
    "user": {
      "inum": 4026531837,
      "is_host": true
    }
  },
  "tid": 35477,
  "process_credentials": {
    "uid": 0,
    "gid": 0,
    "euid": 0,
    "egid": 0,
    "suid": 0,
    "sgid": 0,
    "fsuid": 0,
    "fsgid": 0
  }
}

These logs can also easily be exported to your favorite SIEM for forensics analysis and alerting!
Have you identified the binary and arguments that caused the panic attack on the Death Star pod?

Submit your report to the Death Star security team using the answers.yaml file you can find in the </> Editor.

Then click the check button to finish this challenge!
