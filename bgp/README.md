BGP is a Data Center Standard

BGP is not just the foundational protocol behind the Internet; it is now the standard within data centers.

Modern data center network fabrics are typically based on a “leaf-and-spine” architecture where BGP is typically used to propagate endpoint reachability information.

Given that such endpoints can be Kubernetes Pods, it was natural that Cilium should introduce support for BGP.

In this lab, you will be deploying BGP with Cilium and peer with a virtual leaf/spine data center network. By the end of the lab, you will see how easy it is to connect your data center network with your Cilium-managed Kubernetes clusters!

We are going to be using Kind to set up our Kubernetes cluster, and on top of that Cilium.

Let's have a look at its configuration:
root@server:~# yq cluster.yaml
kind: Cluster
name: clab-bgp-cplane-demo
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
  podSubnet: "10.1.0.0/16"
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-ip: "10.0.1.2"
            node-labels: "rack=rack0"
  - role: worker
    kubeadmConfigPatches:
      - |
        kind: JoinConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-ip: "10.0.2.2"
            node-labels: "rack=rack0"
  - role: worker
    kubeadmConfigPatches:
      - |
        kind: JoinConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-ip: "10.0.3.2"
            node-labels: "rack=rack1"
  - role: worker
    kubeadmConfigPatches:
      - |
        kind: JoinConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-ip: "10.0.4.2"
            node-labels: "rack=rack1"
containerdConfigPatches:
  - |-
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:5000"]
      endpoint = ["http://kind-registry:5000"]


In the networking section of the configuration file, the default CNI has been disabled so the cluster won't have any Pod network when it starts. Instead, Cilium will be deployed to the cluster to provide this functionality.

To see if the Kind cluster is installed, verify that the nodes are up and joined:
root@server:~# kubectl get nodes
NAME                                 STATUS     ROLES           AGE     VERSION
clab-bgp-cplane-demo-control-plane   NotReady   control-plane   3m56s   v1.29.2
clab-bgp-cplane-demo-worker          NotReady   <none>          3m31s   v1.29.2
clab-bgp-cplane-demo-worker2         NotReady   <none>          3m33s   v1.29.2
clab-bgp-cplane-demo-worker3         NotReady   <none>          3m32s   v1.29.2


Networking Fabric

To showcase the Cilium BGP feature, we need a BGP-capable device to peer with.

For this purpose, we will be leveraging Containerlab and FRR (Free Range Routing). These great tools provide the ability to simulate networking environment in containers.

Containerlab

Containerlab is a platform that enables users to deploy virtual networking topologies, based on containers and virtual machines. One of the virtual routing appliances that can be deployed via Containerlab is FRR - a feature-rich open-source networking platform.

By the end of the lab, you will have established BGP peering with the FRR virtual devices.


If you're curious, you can check out in details the containerlab topology we are deploying as part of the lab.

root@server:~# yq topo.yaml

Go to the 🔗 🗺️ Network Topology tab to observe the architecture.

The main thing to notice is that we are deploying 3 main routing nodes: a backbone router (router0) and two Top of Rack (ToR) routers (tor0 and tor1). We are pre-configuring them at boot time with their IP and BGP configuration. At the end of the YAML file, you will also note we are establishing virtual links between the backbone and the ToR routers.

In the following tasks, we will configure Cilium to run BGP on the kind nodes and to establish BGP peering with the ToR devices.

Here is what the overall final topology looks like (note you can resize this window if the diagram is too small):
In the >_ Terminal, deploy the topology previously described:
root@server:~# containerlab -t topo.yaml deploy
INFO[0000] Containerlab v0.31.1 started                 
INFO[0000] Parsing & checking topology file: topo.yaml  
INFO[0000] Could not read docker config: open /root/.docker/config.json: no such file or directory 
INFO[0000] Pulling docker.io/nicolaka/netshoot:latest Docker image 
INFO[0008] Done pulling docker.io/nicolaka/netshoot:latest 
INFO[0008] Could not read docker config: open /root/.docker/config.json: no such file or directory 
INFO[0008] Pulling docker.io/frrouting/frr:v8.2.2 Docker image 
INFO[0013] Done pulling docker.io/frrouting/frr:v8.2.2  
INFO[0013] Creating lab directory: /root/clab-bgp-cplane-demo 
INFO[0013] Creating docker network: Name="clab", IPv4Subnet="172.20.20.0/24", IPv6Subnet="2001:172:20:20::/64", MTU="1500" 
INFO[0013] Creating container: "router0"                
INFO[0013] Creating container: "srv-worker2"            
INFO[0013] Creating container: "srv-control-plane"      
INFO[0013] Creating container: "srv-worker"             
INFO[0013] Creating container: "srv-worker3"            
INFO[0013] Creating container: "tor1"                   
INFO[0013] Creating container: "tor0"                   
INFO[0014] Creating virtual wire: tor0:net2 <--> srv-worker:net0 
INFO[0014] Creating virtual wire: tor0:net1 <--> srv-control-plane:net0 
INFO[0014] Creating virtual wire: router0:net0 <--> tor0:net0 
INFO[0014] Creating virtual wire: tor1:net1 <--> srv-worker2:net0 
INFO[0014] Creating virtual wire: tor1:net2 <--> srv-worker3:net0 
INFO[0014] Creating virtual wire: router0:net1 <--> tor1:net0 
INFO[0014] Adding containerlab host entries to /etc/hosts file 
INFO[0015] Executed command '/usr/lib/frr/frrinit.sh start' on clab-bgp-cplane-demo-tor1. stdout:
Started watchfrr 
INFO[0015] Executed command '/usr/lib/frr/frrinit.sh start' on clab-bgp-cplane-demo-router0. stdout:
Started watchfrr 
INFO[0016] Executed command '/usr/lib/frr/frrinit.sh start' on clab-bgp-cplane-demo-tor0. stdout:
Started watchfrr 
INFO[0016] 🎉 New containerlab version 0.56.0 is available! Release notes: https://containerlab.dev/rn/0.56/
Run 'containerlab version upgrade' to upgrade or go check other installation options at https://containerlab.dev/install/ 
+---+----------------------------------------+--------------+--------------------------+-------+---------+----------------+----------------------+
| # |                  Name                  | Container ID |          Image           | Kind  |  State  |  IPv4 Address  |     IPv6 Address     |
+---+----------------------------------------+--------------+--------------------------+-------+---------+----------------+----------------------+
| 1 | clab-bgp-cplane-demo-router0           | c0f5bb4f29cd | frrouting/frr:v8.2.2     | linux | running | 172.20.20.4/24 | 2001:172:20:20::4/64 |
| 2 | clab-bgp-cplane-demo-srv-control-plane | 67c9c5bf7dda | nicolaka/netshoot:latest | linux | running | N/A            | N/A                  |
| 3 | clab-bgp-cplane-demo-srv-worker        | 97733e01b3bb | nicolaka/netshoot:latest | linux | running | N/A            | N/A                  |
| 4 | clab-bgp-cplane-demo-srv-worker2       | 2ba6de698073 | nicolaka/netshoot:latest | linux | running | N/A            | N/A                  |
| 5 | clab-bgp-cplane-demo-srv-worker3       | 2463cc13f972 | nicolaka/netshoot:latest | linux | running | N/A            | N/A                  |
| 6 | clab-bgp-cplane-demo-tor0              | 3c6ded4022fc | frrouting/frr:v8.2.2     | linux | running | 172.20.20.2/24 | 2001:172:20:20::2/64 |
| 7 | clab-bgp-cplane-demo-tor1              | e490639ecec6 | frrouting/frr:v8.2.2     | linux | running | 172.20.20.3/24 | 2001:172:20:20::3/64 |
+---+----------------------------------------+--------------+--------------------------+-------+---------+----------------+----------------------+

root@server:~# docker ps
CONTAINER ID   IMAGE                          COMMAND                  CREATED          STATUS          PORTS                                           NAMES
67c9c5bf7dda   nicolaka/netshoot:latest       "bash"                   27 seconds ago   Up 26 seconds                                                   clab-bgp-cplane-demo-srv-control-plane
2ba6de698073   nicolaka/netshoot:latest       "bash"                   27 seconds ago   Up 26 seconds                                                   clab-bgp-cplane-demo-srv-worker2
2463cc13f972   nicolaka/netshoot:latest       "bash"                   27 seconds ago   Up 26 seconds                                                   clab-bgp-cplane-demo-srv-worker3
97733e01b3bb   nicolaka/netshoot:latest       "bash"                   27 seconds ago   Up 26 seconds                                                   clab-bgp-cplane-demo-srv-worker
e490639ecec6   frrouting/frr:v8.2.2           "/sbin/tini -- bash"     27 seconds ago   Up 26 seconds                                                   clab-bgp-cplane-demo-tor1
c0f5bb4f29cd   frrouting/frr:v8.2.2           "/sbin/tini -- bash"     27 seconds ago   Up 26 seconds                                                   clab-bgp-cplane-demo-router0
3c6ded4022fc   frrouting/frr:v8.2.2           "/sbin/tini -- bash"     27 seconds ago   Up 26 seconds                                                   clab-bgp-cplane-demo-tor0
80b5554b220b   ghcr.io/srl-labs/clab:latest   "containerlab graph …"   7 minutes ago    Up 7 minutes    0.0.0.0:50080->50080/tcp, :::50080->50080/tcp   wizardly_goldwasser
c8707dff5240   kindest/node:v1.29.2           "/usr/local/bin/entr…"   12 minutes ago   Up 12 minutes   127.0.0.1:38041->6443/tcp                       clab-bgp-cplane-demo-control-plane
05c9e4fb0fcb   kindest/node:v1.29.2           "/usr/local/bin/entr…"   12 minutes ago   Up 12 minutes                                                   clab-bgp-cplane-demo-worker2
1826f8c5a156   kindest/node:v1.29.2           "/usr/local/bin/entr…"   12 minutes ago   Up 12 minutes                                                   clab-bgp-cplane-demo-worker
91951a216b57   kindest/node:v1.29.2           "/usr/local/bin/entr…"   12 minutes ago   Up 12 minutes                                                   clab-bgp-cplane-demo-worker3

At this stage, BGP should be up between our Top of Rack switches and the backbone router router0.
Let's verify this with this command.
root@server:~# docker exec -it clab-bgp-cplane-demo-router0 vtysh -c 'show bgp ipv4 summary wide'

IPv4 Unicast Summary (VRF default):
BGP router identifier 10.0.0.0, local AS number 65000 vrf-id 0
BGP table version 8
RIB entries 15, using 2760 bytes of memory
Peers 2, using 1433 KiB of memory
Peer groups 1, using 64 bytes of memory

Neighbor        V         AS    LocalAS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt Desc
tor0(net0)      4      65010      65000        45        44        0    0    0 00:01:48            3        9 N/A
tor1(net1)      4      65011      65000        45        45        0    0    0 00:01:49            3        9 N/A

Total number of neighbors 2
Let's explain briefly this command.

    docker exec -it lets us enter the router0 shell. As mentioned earlier, router0 is based on the open-source Free Range Routing platform (FRR).
    vtysh is the integrated shell on FRR devices.
    show bgp ipv4 summary wide lets us check the BGP status.

If you're familiar with using BGP on traditional CLIs such as Cisco IOS, this will look familiar. If not, let's go through some of the key outputs of the command above.

This commands provides information about the BGP status on router0. It shows router0's local AS number (65000), the remote AS number of the routers it is peering with (65010 for tor0 and 65011 for tor1).

It also shows, in the Up/Down column where the session is established (if that's the case, it will show for how long the session has been up - in our case, it's been up for 00:01:41).

Finally, it shows how many prefixes have been received and sent (see State/PfxRcd and PfxSnt).

Let's run this command on the Top of Rack switches. Two of the sessions remain "Active" - it means the peering sessions are configured and actively trying to peer but they are not established yet.

It's to be expected: BGP is not established with the Kind nodes as we haven't deployed Cilium yet.

On tor0:
root@server:~# docker exec -it clab-bgp-cplane-demo-tor0 vtysh -c 'show bgp ipv4 summary wide'

IPv4 Unicast Summary (VRF default):
BGP router identifier 10.0.0.1, local AS number 65010 vrf-id 0
BGP table version 9
RIB entries 15, using 2760 bytes of memory
Peers 3, using 2149 KiB of memory
Peer groups 2, using 128 bytes of memory

Neighbor        V         AS    LocalAS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt Desc
router0(net0)   4      65000      65010       155       157        0    0    0 00:07:21            6        9 N/A
10.0.1.2        4          0      65010         0         0        0    0    0    never       Active        0 N/A
10.0.2.2        4          0      65010         0         0        0    0    0    never       Active        0 N/A

Total number of neighbors 3

On tor1:
root@server:~# docker exec -it clab-bgp-cplane-demo-tor1 vtysh -c 'show bgp ipv4 summary wide'

IPv4 Unicast Summary (VRF default):
BGP router identifier 10.0.0.2, local AS number 65011 vrf-id 0
BGP table version 9
RIB entries 15, using 2760 bytes of memory
Peers 3, using 2149 KiB of memory
Peer groups 2, using 128 bytes of memory

Neighbor        V         AS    LocalAS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt Desc
router0(net0)   4      65000      65011       169       170        0    0    0 00:08:05            6        9 N/A
10.0.3.2        4          0      65011         0         0        0    0    0    never       Active        0 N/A
10.0.4.2        4          0      65011         0         0        0    0    0    never       Active        0 N/A

Total number of neighbors 3


The cilium CLI tool is provided in this environment to install and check the status of Cilium in the cluster.

Let's start by installing Cilium on the Kind cluster, with BGP enabled.
root@server:~# cilium install \
    --version v1.16.0 \
    --set ipam.mode=kubernetes \
    --set tunnel=disabled \
    --set ipv4NativeRoutingCIDR="10.0.0.0/8" \
    --set bgpControlPlane.enabled=true \
    --set k8s.requireIPv4PodCIDR=true
🔮 Auto-detected Kubernetes kind: kind
✨ Running "kind" validation checks
✅ Detected kind version "0.22.0"
ℹ️  Using Cilium version 1.16.0
🔮 Auto-detected cluster name: kind-clab-bgp-cplane-demo
🔮 Auto-detected kube-proxy has been installed

The installation usually takes a couple of minutes. While we wait for the installation to complete, let's review some Cilium BGP aspects:

    As you can see in the Cilium Helm values above, bgpControlPlane is the main requirement to enable BGP on Cilium.
    The configuration for BGP peers and Autonomous System Numbers (ASN) will be configured through a Kubernetes CRD (that's the next task).

For more details on the BGP configuration options, you can read up more on the official Cilium BGP documentation.

The installation should now have finished. Let's verify the status of Cilium:
root@server:~# cilium status --wait
    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    OK
 \__/¯¯\__/    Hubble Relay:       disabled
    \__/       ClusterMesh:        disabled

DaemonSet              cilium-envoy       Desired: 4, Ready: 4/4, Available: 4/4
DaemonSet              cilium             Desired: 4, Ready: 4/4, Available: 4/4
Deployment             cilium-operator    Desired: 1, Ready: 1/1, Available: 1/1
Containers:            cilium             Running: 4
                       cilium-envoy       Running: 4
                       cilium-operator    Running: 1
Cluster Pods:          3/3 managed by Cilium
Helm chart version:    
Image versions         cilium-operator    quay.io/cilium/operator-generic:v1.16.0@sha256:d6621c11c4e4943bf2998af7febe05be5ed6fdcf812b27ad4388f47022190316: 1
                       cilium             quay.io/cilium/cilium:v1.16.0@sha256:46ffa4ef3cf6d8885dcc4af5963b0683f7d59daa90d49ed9fb68d3b1627fe058: 4
                       cilium-envoy       quay.io/cilium/cilium-envoy:v1.29.7-39a2a56bbd5b3a591f69dbca51d3e30ef97e0e51@sha256:bd5ff8c66716080028f414ec1cb4f7dc66f40d2fb5a009fff187f4a9b90b566b: 4

Cilium is now functional on our cluster.

Let's verify that BGP has been successfully enabled by checking the Cilium configuration:
root@server:~# cilium config view | grep enable-bgp
enable-bgp-control-plane                          true       

Lab setup

Our networking infrastructure is now ready: we can set up peering between our BGP peers and let them exchange routes.

Once BGP is up, we will complete the lab by verifying end-to-end connectivity across our virtual network.


Let's first walk through the BGP Peering configuration.

Peering policies can be provisioned using simple Kubernetes CRDs, of the kind CiliumBGPPeeringPolicy.
root@server:~# yq cilium-bgp-peering-policies.yaml
---
apiVersion: "cilium.io/v2alpha1"
kind: CiliumBGPPeeringPolicy
metadata:
  name: rack0
spec:
  nodeSelector:
    matchLabels:
      rack: rack0
  virtualRouters:
    - localASN: 65010
      exportPodCIDR: true
      neighbors:
        - peerAddress: "10.0.0.1/32"
          peerASN: 65010
---
apiVersion: "cilium.io/v2alpha1"
kind: CiliumBGPPeeringPolicy
metadata:
  name: rack1
spec:
  nodeSelector:
    matchLabels:
      rack: rack1
  virtualRouters:
    - localASN: 65011
      exportPodCIDR: true
      neighbors:
        - peerAddress: "10.0.0.2/32"
          peerASN: 65011


The key aspects of the policy are:

    the remote peer IP address (peerAddress) and AS Number (peerASN)
    your own local AS Number (localASN) And that's it!

In this lab, we specify the loopback IP addresses of our BGP peers: the Top of Rack devices tor0 (10.0.0.1/32) and tor1 (10.0.0.2/32).

Note that BGP configuration on Cilium is label-based - the Cilium-managed nodes with a matching label will deploy a virtual router for BGP peering purposes.

Verify the label configuration with the following commands:
root@server:~# kubectl get nodes -l 'rack in (rack0,rack1)'
NAME                                 STATUS   ROLES           AGE   VERSION
clab-bgp-cplane-demo-control-plane   Ready    control-plane   27m   v1.29.2
clab-bgp-cplane-demo-worker          Ready    <none>          27m   v1.29.2
clab-bgp-cplane-demo-worker2         Ready    <none>          27m   v1.29.2
clab-bgp-cplane-demo-worker3         Ready    <none>          27m   v1.29.2

It's time to now deploy the BGP peering policy.
root@server:~# kubectl apply -f cilium-bgp-peering-policies.yaml
ciliumbgppeeringpolicy.cilium.io/rack0 created
ciliumbgppeeringpolicy.cilium.io/rack1 created

Now that we have set up our BGP peering, the peering sessions between the Cilium nodes and the Top of Rack switches should be established successfully. Let's verify that the sessions have been established and that routes are learned successfully (it might take a few seconds for the sessions to come up).

On tor0:
root@server:~# docker exec -it clab-bgp-cplane-demo-tor0 vtysh -c 'show bgp ipv4 summary wide'

IPv4 Unicast Summary (VRF default):
BGP router identifier 10.0.0.1, local AS number 65010 vrf-id 0
BGP table version 13
RIB entries 23, using 4232 bytes of memory
Peers 3, using 2149 KiB of memory
Peer groups 2, using 128 bytes of memory

Neighbor                                     V         AS    LocalAS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt Desc
router0(net0)                                4      65000      65010       357       360        0    0    0 00:17:20            8       13 N/A
clab-bgp-cplane-demo-control-plane(10.0.1.2) 4      65010      65010        14        20        0    0    0 00:00:35            1       11 N/A
clab-bgp-cplane-demo-worker(10.0.2.2)        4      65010      65010        14        20        0    0    0 00:00:35            1       11 N/A

Total number of neighbors 3


On tor1:
root@server:~# docker exec -it clab-bgp-cplane-demo-tor0 vtysh -c 'show bgp ipv4 summary wide'

IPv4 Unicast Summary (VRF default):
BGP router identifier 10.0.0.1, local AS number 65010 vrf-id 0
BGP table version 13
RIB entries 23, using 4232 bytes of memory
Peers 3, using 2149 KiB of memory
Peer groups 2, using 128 bytes of memory

Neighbor                                     V         AS    LocalAS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt Desc
router0(net0)                                4      65000      65010       357       360        0    0    0 00:17:20            8       13 N/A
clab-bgp-cplane-demo-control-plane(10.0.1.2) 4      65010      65010        14        20        0    0    0 00:00:35            1       11 N/A
clab-bgp-cplane-demo-worker(10.0.2.2)        4      65010      65010        14        20        0    0    0 00:00:35            1       11 N/A

Total number of neighbors 3

This time, you should see that the session between the ToR devices and the Cilium nodes are no longer "Active" (that is to say, unsuccessfully trying to establish peering) but up (you will see how long the session has been up on the Up/Down column).

We will also be deploying a networking utility called netshoot by using a DaemonSet. We will be using it to verify end-to-end connectivity at the end of the lab.

root@server:~# yq netshoot-ds.yaml 
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: netshoot
spec:
  selector:
    matchLabels:
      app: netshoot
  template:
    metadata:
      labels:
        app: netshoot
    spec:
      tolerations:
        - key: node-role.kubernetes.io/master
          operator: Exists
          effect: NoSchedule
      containers:
        - name: netshoot
          image: nicolaka/netshoot:latest
          command: ["sleep", "infinite"]
root@server:~# kubectl apply -f netshoot-ds.yaml

To verify the netshoot pods have been successfully deployed, simply run:
root@server:~# kubectl rollout status ds/netshoot -w
Waiting for daemon set "netshoot" rollout to finish: 2 of 3 updated pods are available...
daemon set "netshoot" successfully rolled out
root@server:~# kubectl rollout status ds/netshoot -w
daemon set "netshoot" successfully rolled out

We will now be running a series of connectivity tests, from a source Pod on a node in rack0 to a destination Pod in rack1. These packets will traverse the our virtual networking backbone and validate that the whole data path is working as expected.

Run the following commands.

First, let's find the name of a source Pod in rack0.

root@server:~# SRC_POD=$(kubectl get pods -o wide | grep "cplane-demo-worker " | awk '{ print($1); }')
root@server:~# DST_IP=$(kubectl get pods -o wide | grep worker3 | awk '{ print($6); }')
root@server:~# kubectl exec -it $SRC_POD -- ping $DST_IP
PING 10.1.2.145 (10.1.2.145) 56(84) bytes of data.
64 bytes from 10.1.2.145: icmp_seq=1 ttl=63 time=0.268 ms
64 bytes from 10.1.2.145: icmp_seq=2 ttl=63 time=0.132 ms
64 bytes from 10.1.2.145: icmp_seq=3 ttl=63 time=0.126 ms
--- 10.1.2.145 ping statistics ---
9 packets transmitted, 9 received, 0% packet loss, time 8203ms
rtt min/avg/max/mdev = 0.104/0.149/0.268/0.048 ms


You should see packets flowing across your virtual data center. Well done: your Kubernetes Pods located in different rack servers in your (virtual) datacenter can communicate together across the network backbone! 🥳

Great job - you have successfully completed this lab and now understand how you can use BGP on Cilium to easily connect your Kubernetes clusters to your DC network.

In this practical exam, you still have access to the Kind cluster you used in the lab, and Cilium is still installed on it.

However, the BGP peering policies have been removed, and you have to set them up and deploy them again.

You can use the template manifest (cilium-bgp-peering-policy-template.yaml) provided in the current directory and edit them in the </> Editor tab. Don't forget to apply the manifests in the >_  Terminal!

Note

    You need to create two BGP peering policies: one for rack0 and one for rack1.
    You can find out the AS numbers for each rack with:

shell

docker exec clab-bgp-cplane-demo-router0 vtysh -c 'show bgp ipv4 summary'

    Remember you will need to set up iBGP (internal BGP, where localASN == peerASN) sessions between the Cilium nodes and the torX devices.
    You can get the IP addresses of a tor with:

shell

docker exec clab-bgp-cplane-demo-torX ip a

    Use tor IP addresses in the 10.0.0.0/24 range for the peering.
    If new files don't show up in the Editor, you can refresh it.

root@server:~# yq cilium-bgp-peering-policy-template.yaml 
---
apiVersion: "cilium.io/v2alpha1"
kind: CiliumBGPPeeringPolicy
metadata:
  name: rack0
spec:
  nodeSelector:
    matchLabels:
      rack: rack0
  virtualRouters:
    - localASN: 65010
      exportPodCIDR: true
      neighbors:
        - peerAddress: "10.0.0.1/32"
          peerASN: 65010
---
apiVersion: "cilium.io/v2alpha1"
kind: CiliumBGPPeeringPolicy
metadata:
  name: rack1
spec:
  nodeSelector:
    matchLabels:
      rack: rack1
  virtualRouters:
    - localASN: 65011
      exportPodCIDR: true
      neighbors:
        - peerAddress: "10.0.0.2/32"
          peerASN: 65011
root@server:~# k apply -f cilium-bgp-peering-policy-template.yaml 
ciliumbgppeeringpolicy.cilium.io/rack0 created
ciliumbgppeeringpolicy.cilium.io/rack1 created

root@server:~# docker exec clab-bgp-cplane-demo-router0 vtysh -c 'show bgp ipv4 summary'

IPv4 Unicast Summary (VRF default):
BGP router identifier 10.0.0.0, local AS number 65000 vrf-id 0
BGP table version 28
RIB entries 23, using 4232 bytes of memory
Peers 2, using 1433 KiB of memory
Peer groups 1, using 64 bytes of memory

Neighbor        V         AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt Desc
tor0(net0)      4      65010       686       681        0    0    0 00:33:03            5       13 N/A
tor1(net1)      4      65011       684       682        0    0    0 00:33:04            5       13 N/A

Total number of neighbors 2

root@server:~# docker exec clab-bgp-cplane-demo-tor0 ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet 10.0.0.1/32 scope global lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
23: net2@if22: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9500 qdisc noqueue state UP group default 
    link/ether aa:c1:ab:36:9b:55 brd ff:ff:ff:ff:ff:ff link-netnsid 1
    inet 10.0.2.1/24 scope global net2
       valid_lft forever preferred_lft forever
    inet6 fe80::a8c1:abff:fe36:9b55/64 scope link 
       valid_lft forever preferred_lft forever
25: net1@if24: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9500 qdisc noqueue state UP group default 
    link/ether aa:c1:ab:16:ec:fa brd ff:ff:ff:ff:ff:ff link-netnsid 2
    inet 10.0.1.1/24 scope global net1
       valid_lft forever preferred_lft forever
    inet6 fe80::a8c1:abff:fe16:ecfa/64 scope link 
       valid_lft forever preferred_lft forever
26: net0@if27: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9500 qdisc noqueue state UP group default 
    link/ether aa:c1:ab:ff:51:8a brd ff:ff:ff:ff:ff:ff link-netnsid 3
    inet6 fe80::a8c1:abff:feff:518a/64 scope link 
       valid_lft forever preferred_lft forever
root@server:~# docker exec clab-bgp-cplane-demo-tor1 ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet 10.0.0.2/32 scope global lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
29: net1@if28: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9500 qdisc noqueue state UP group default 
    link/ether aa:c1:ab:71:2d:fd brd ff:ff:ff:ff:ff:ff link-netnsid 3
    inet 10.0.3.1/24 scope global net1
       valid_lft forever preferred_lft forever
    inet6 fe80::a8c1:abff:fe71:2dfd/64 scope link 
       valid_lft forever preferred_lft forever
31: net2@if30: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9500 qdisc noqueue state UP group default 
    link/ether aa:c1:ab:63:e1:d9 brd ff:ff:ff:ff:ff:ff link-netnsid 1
    inet 10.0.4.1/24 scope global net2
       valid_lft forever preferred_lft forever
    inet6 fe80::a8c1:abff:fe63:e1d9/64 scope link 
       valid_lft forever preferred_lft forever
32: net0@if33: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9500 qdisc noqueue state UP group default 
    link/ether aa:c1:ab:76:7a:54 brd ff:ff:ff:ff:ff:ff link-netnsid 2
    inet6 fe80::a8c1:abff:fe76:7a54/64 scope link 
       valid_lft forever preferred_lft forever
root@server:~# 