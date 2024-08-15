Cilium BIG TCP

100Gbps and beyond

Many of the organizations adopting Cilium – cloud providers, financial institutions and telecommunication providers – all have something in common: they all want to extract as much performance from the network as possible.

These organizations are building networks capable of 100Gbps and beyond but with the adoption of 100Gbps network adapters comes the inevitable challenge: how can a CPU deal with 8,000,000 packets per second (assuming a MTU of 1,538 bytes)?

That leaves only 120 nanoseconds per packet for the system to handle, which is unrealistic.

How could we reduce the number of packets a CPU has to deal with?

By grouping packets together, of course!

GRO and GSO

Within the Linux stack, grouping packets has been done for a while through the GRO (Generic Receive Offload) and TSO (Transmit Segmentation Offload) protocols.

On the receiving end, GRO would group packets into a super-sized 64KB packet within the stack and pass it up the networking stack. Likewise, on the transmitting end, TSO would segment TCP super-sized packets for the NIC to handle.

While that super-sized 64K packet helps, modern CPUs can actually handle much larger packets.

But 64K had remained a hard limit: the length of an IP packet is specified, in octets, in a 16-bit field. Its maximum value is therefore 65,535 bytes (64KB).

BIG TCP

In this lab, you will discover a new Linux networking technology called BIG TCP.

BIG TCP lets you group more packets together as they cross the networking stack and can significantly improve performance.

BIG TCP support on Cilium was introduced in 1.13 for IPv6 and in 1.14 for IPv4.

To support BIG TCP for IPv4 and IPv6, we will need a recent Linux kernel (6.3 and above is required).

Let's install the 6.4.0 kernel with the script below. The ugprade will be pretty seamless.
wget https://raw.githubusercontent.com/pimlie/ubuntu-mainline-kernel.sh/master/ubuntu-mainline-kernel.sh
chmod +x ubuntu-mainline-kernel.sh
mv ubuntu-mainline-kernel.sh /usr/local/bin/
ubuntu-mainline-kernel.sh -c
ubuntu-mainline-kernel.sh -i v6.4.0

Once the Kernel upgrade is completed, reboot your host with:
reboot
root@server:~# uname -a
Linux server 6.4.0-060400-generic #202306271339 SMP PREEMPT_DYNAMIC Tue Jun 27 14:26:34 UTC 2023 x86_64 x86_64 x86_64 GNU/Linux
You are ready to use BIG TCP and Cilium. But first, let's deploy our Kubernetes cluster.

Before we deploy the Kubernetes cluster (based on Kind), let's have a look at its configuration:
root@server:~# cat /etc/kind/nocni_2workers_dual.yaml
---
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
networking:
  ipFamily: dual
  disableDefaultCNI: true

The important parameters here are:

    disableDefaultCNI is set to true as Cilium will be deployed instead of the default CNI.
    ipFamily set to dual for Dual Stack (IPv4 and IPv6 support). More details can be found on the official Kubernetes docs.

In the networking section of the configuration file, the default CNI has been disabled so the cluster won't have any Pod network when it starts. Instead, Cilium is being deployed to the cluster to provide this functionality.

To see if the Kind cluster is ready, verify that the cluster is properly running by listing its nodes:
root@server:~# kubectl get nodes
NAME                 STATUS     ROLES           AGE   VERSION
kind-control-plane   NotReady   control-plane   41s   v1.27.3
kind-worker          NotReady   <none>          18s   v1.27.3
kind-worker2         NotReady   <none>          17s   v1.27.3

You should see the three nodes appear, all marked as NotReady. This is normal, since the CNI is disabled, and we will install Cilium in the next step. If you don't see all nodes, the worker nodes might still be joining the cluster. Relaunch the command until you can see all three nodes listed.

Now that we have a Kind cluster deployed, let's install Cilium on it!
Let's start by installing Cilium on the Kind cluster.

In this lab, we will be installing Cilium with Helm and we will verify the Cilium status with the Cilium CLI (note that the Cilium CLI can be also be used to install Cilium).

First, let's add the Cilium Helm repo.
root@server:~# helm repo add cilium https://helm.cilium.io/
"cilium" has been added to your repositories
Check the Cilium configuration below and apply it.

Note that we are enabling IPv6 (it's disabled by default) and that BIG TCP will not be enabled yet (it's also disabled by default but we are just showing the flags here for information).
helm install cilium cilium/cilium --version v1.16.0 \
  --namespace kube-system \
  --set routingMode=native \
  --set bpf.masquerade=true \
  --set ipv6.enabled=true \
  --set enableIPv6Masquerade=false \
  --set kubeProxyReplacement=true \
  --set ipam.mode=kubernetes \
  --set nodePort.enabled=true \
  --set autoDirectNodeRoutes=true \
  --set hostLegacyRouting=false \
  --set ipv4NativeRoutingCIDR="10.0.0.0/8" \
  --set enableIPv6BIGTCP=false \
  --set enableIPv4BIGTCP=false

While we wait for Cilium to be installed, let's explain the pre-requisites settings for BIG TCP:

    eBPF-based kube-proxy replacement (hence set kubeProxyReplacement=strict). KPR significantly improves performances over the iptables-based kube-proxy that comes by default with Kubernetes.
    eBPF Host-Routing (hence set hostLegacyRouting=false ). Host-routing based on eBPF fully bypass iptables and the upper host stack and provides a faster network namespace.
    eBPF-based masquerading (hence set bpf.masquerade=true). Cilium will automatically masquerade the source IP address of all traffic that is leaving the cluster to the IPv4 address of the node as the node’s IP address is already routable on the network.
    Tunnel mode is disabled (hence set tunnel=disabled) and therefore Cilium will be running in native routing mode. In this mode, the network connecting the hosts on which Cilium is running on must be capable of forwarding IP traffic using addresses given to pods or other workloads.
    The Linux kernel on the node must be aware on how to forward packets of Pods or other workloads of all nodes running Cilium. This can be taken care of by setting autoDirectNodeRoutes to true.

The nodes should now be in Ready state. Check with the following command:
root@server:~# kubectl get nodes
NAME                 STATUS   ROLES           AGE     VERSION
kind-control-plane   Ready    control-plane   4m57s   v1.27.3
kind-worker          Ready    <none>          4m34s   v1.27.3
kind-worker2         Ready    <none>          4m33s   v1.27.3

root@server:~# kubectl get pods -n kube-system 
NAME                                         READY   STATUS    RESTARTS   AGE
cilium-4t8k6                                 0/1     Running   0          22s
cilium-envoy-8zzbh                           1/1     Running   0          8m35s
cilium-envoy-d8jsv                           1/1     Running   0          8m35s
cilium-envoy-tqdrv                           1/1     Running   0          8m35s
cilium-ktbsx                                 0/1     Running   0          22s
cilium-m8cjp                                 0/1     Running   0          22s
cilium-operator-7959cd67f7-tv7kk             1/1     Running   0          8m35s
cilium-operator-7959cd67f7-vsdvs             1/1     Running   0          8m35s
coredns-5d78c9869d-ccs4p                     1/1     Running   0          10m
coredns-5d78c9869d-hz999                     1/1     Running   0          10m
etcd-kind-control-plane                      1/1     Running   0          10m
kube-apiserver-kind-control-plane            1/1     Running   0          10m
kube-controller-manager-kind-control-plane   1/1     Running   0          10m
kube-proxy-jmp92                             1/1     Running   0          10m
kube-proxy-ldm4z                             1/1     Running   0          10m
kube-proxy-wzhdq                             1/1     Running   0          10m
kube-scheduler-kind-control-plane            1/1     Running   0          10m

BIG TCP over IPv4

Unusually, BIG TCP was available for IPv6 first, before support for IPv4 was introduced.

As you will see in the next task, IPv6 packets had a convenient field that could be used to specify the larger packet lengths. As this field is not available in IPv4, Linux engineers had to find a different way to increase that limit.

The length of the data payload stored in the socket buffer (referred to skb->len by Linux developers) is used to specify the bigger packet size.

Cilium BIG TCP currently supports a 192K packet size - tripling the previously maximum o64K size.

Let's observe the performances without and with BIG TCP and compare.

Let's verify BIG TCP for IPv4 is not enabled yet:
root@server:~# cilium config view | grep ipv4-big-tcp
enable-ipv4-big-tcp                               false

To run our performance tests, we will be using netperf. Netperf is a benchmark that can be used to measure the performance of many different types of networking. It provides tests for both unidirectional throughput, and end-to-end latency.

Let's deploy a netperf client and a netperf server:
root@server:~# kubectl apply -f https://raw.githubusercontent.com/NikAleksandrov/cilium/42b93676d85783aa167105a91e44078ce6731297/test/bigtcp/netperf.yaml
pod/netperf-server created
pod/netperf-client created
root@server:~# kubectl get pods
NAME             READY   STATUS    RESTARTS   AGE
netperf-client   1/1     Running   0          12s
netperf-server   1/1     Running   0          12s

Let's run a performance test. First, let's get the IPv4 address of the netperf server:
root@server:~# NETPERF_SERVER=$(kubectl get pod netperf-server -o jsonpath='{.status.podIPs}' | jq -r -c '.[].ip | select(contains(":") == false)')
echo $NETPERF_SERVER
10.244.2.77

Let's now start the performance test. That is done by executing a netperf on the client towards the server, using large sized packets (80,000 bytes) and setting the testing output with -O to show the statistics on the latency in microseconds and the throughput in the number of packets per seconds.
root@server:~# kubectl exec netperf-client -- \
  netperf -t TCP_RR -H ${NETPERF_SERVER} -- \
  -r80000:80000 -O MIN_LATENCY,P90_LATENCY,P99_LATENCY,THROUGHPUT
MIGRATED TCP REQUEST/RESPONSE TEST from 0.0.0.0 (0.0.0.0) port 0 AF_INET to 10.244.2.77 (10.244.) port 0 AF_INET : first burst 0
Minimum      90th         99th         Throughput 
Latency      Percentile   Percentile              
Microseconds Latency      Latency                 
             Microseconds Microseconds            
46           95           158          12186.42  

root@server:~# kubectl exec netperf-client -- \
  netperf -t TCP_RR -H ${NETPERF_SERVER} -- \
  -r80000:80000 -O MIN_LATENCY,P90_LATENCY,P99_LATENCY,THROUGHPUT
MIGRATED TCP REQUEST/RESPONSE TEST from 0.0.0.0 (0.0.0.0) port 0 AF_INET to 10.244.2.77 (10.244.) port 0 AF_INET : first burst 0
Minimum      90th         99th         Throughput 
Latency      Percentile   Percentile              
Microseconds Latency      Latency                 
             Microseconds Microseconds            
44           94           153          12196.51   

Once enabled in Cilium, all nodes will be automatically configured with BIG TCP. There is no cluster downtime when enabling this feature, albeit the Kubernetes Pods must be restarted for the changes to take effect.

Take a note of the performance results. They will vary every time but expect the throughput to be between 4,000 and 8,000 packets per seconds.

Feel free to run the command above several times to validate the test.

Let's now compare when we enable BIG TCP.

root@server:~# cilium config set enable-ipv4-big-tcp true
✨ Patching ConfigMap cilium-config with enable-ipv4-big-tcp=true...
♻️  Restarted Cilium pods

The Cilium agents will be restarted. Wait until Cilium is ready.
root@server:~# cilium status --wait
    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    OK
 \__/¯¯\__/    Hubble Relay:       disabled
    \__/       ClusterMesh:        disabled

DaemonSet              cilium-envoy       Desired: 3, Ready: 3/3, Available: 3/3
Deployment             cilium-operator    Desired: 2, Ready: 2/2, Available: 2/2
DaemonSet              cilium             Desired: 3, Ready: 3/3, Available: 3/3
Containers:            cilium             Running: 3
                       cilium-envoy       Running: 3
                       cilium-operator    Running: 2
Cluster Pods:          5/5 managed by Cilium
Helm chart version:    1.16.0
Image versions         cilium             quay.io/cilium/cilium:v1.16.0@sha256:46ffa4ef3cf6d8885dcc4af5963b0683f7d59daa90d49ed9fb68d3b1627fe058: 3
                       cilium-envoy       quay.io/cilium/cilium-envoy:v1.29.7-39a2a56bbd5b3a591f69dbca51d3e30ef97e0e51@sha256:bd5ff8c66716080028f414ec1cb4f7dc66f40d2fb5a009fff187f4a9b90b566b: 3
                       cilium-operator    quay.io/cilium/operator-generic:v1.16.0@sha256:d6621c11c4e4943bf2998af7febe05be5ed6fdcf812b27ad4388f47022190316: 2

Let’s double-check it’s enabled:
root@server:~# cilium config view | grep ipv4-big-tcp
enable-ipv4-big-tcp                               true

Let's redeploy the Pods for the BIG TCP changes to be reflected:
root@server:~# kubectl delete -f https://raw.githubusercontent.com/NikAleksandrov/cilium/42b93676d85783aa167105a91e44078ce6731297/test/bigtcp/netperf.yaml
kubectl apply -f https://raw.githubusercontent.com/NikAleksandrov/cilium/42b93676d85783aa167105a91e44078ce6731297/test/bigtcp/netperf.yaml
pod "netperf-server" deleted
pod "netperf-client" deleted
pod/netperf-server created
pod/netperf-client created

Let’s run another netperf test. Let's get the IP address of the server first:
root@server:~# NETPERF_SERVER=$(kubectl get pod netperf-server -o jsonpath='{.status.podIPs}' | jq -r -c '.[].ip | select(contains(":") == false)')
echo $NETPERF_SERVER
kubectl exec netperf-client -- \
  netperf -t TCP_RR -H ${NETPERF_SERVER} -- \
  -r80000:80000 -O MIN_LATENCY,P90_LATENCY,P99_LATENCY,THROUGHPUT
10.244.2.145
MIGRATED TCP REQUEST/RESPONSE TEST from 0.0.0.0 (0.0.0.0) port 0 AF_INET to 10.244.2.145 (10.244.) port 0 AF_INET : first burst 0
Minimum      90th         99th         Throughput 
Latency      Percentile   Percentile              
Microseconds Latency      Latency                 
             Microseconds Microseconds            
35           67           105          18065.42   
root@server:~# NETPERF_SERVER=$(kubectl get pod netperf-server -o jsonpath='{.status.podIPs}' | jq -r -c '.[].ip | select(contains(":") == false)')
echo $NETPERF_SERVER
kubectl exec netperf-client -- \
  netperf -t TCP_RR -H ${NETPERF_SERVER} -- \
  -r80000:80000 -O MIN_LATENCY,P90_LATENCY,P99_LATENCY,THROUGHPUT
10.244.2.145
MIGRATED TCP REQUEST/RESPONSE TEST from 0.0.0.0 (0.0.0.0) port 0 AF_INET to 10.244.2.145 (10.244.) port 0 AF_INET : first burst 0
Minimum      90th         99th         Throughput 
Latency      Percentile   Percentile              
Microseconds Latency      Latency                 
             Microseconds Microseconds            
35           68           106          17902.51   
root@server:~# NETPERF_SERVER=$(kubectl get pod netperf-server -o jsonpath='{.status.podIPs}' | jq -r -c '.[].ip | select(contains(":") == false)')
echo $NETPERF_SERVER
kubectl exec netperf-client -- \
  netperf -t TCP_RR -H ${NETPERF_SERVER} -- \
  -r80000:80000 -O MIN_LATENCY,P90_LATENCY,P99_LATENCY,THROUGHPUT
10.244.2.145
MIGRATED TCP REQUEST/RESPONSE TEST from 0.0.0.0 (0.0.0.0) port 0 AF_INET to 10.244.2.145 (10.244.) port 0 AF_INET : first burst 0
Minimum      90th         99th         Throughput 
Latency      Percentile   Percentile              
Microseconds Latency      Latency                 
             Microseconds Microseconds            
35           67           100          18437.22   

Again, expect the results to fluctuate but if you compare the results, you will see that the latency has reduced across the board.

Expect to see a significant improvement in throughput in packets per second (8,000 to 12,000) - it's a significant performance improvement when enabling BIG TCP !

Let's continue with BIG TCP over IPv6.

BIG TCP for IPv6

Unusually, BIG TCP support was first introduced for IPv6 before IPv4. It was easier to introduce it in IPv6 through the use of a 22-year-old RFC (RFC2675) that describes IPv6 jumbograms (packets bigger than 64KB).

IPv6 supports a Hop-by-Hop header that can be inserted into the packet.

By specifying the payload length in the Hop-by-hop extension header (and setting the Payload Length field in the IPv6 header to 0 to ignore it), we can work around the 64K packet size limitations described earlier.

Hop-by-hop

The Hop-by-Hop extension header is using a 32-bit field for the payload length, which would (in theory) let us have 4GB-sized packets!

But for now, Cilium BIG TCP is currently using 192KB - which is still 3x compared to the previous 64K limit.

Let's verify BIG TCP for IPv6 is not enabled yet:

root@server:~# cilium config view | grep ipv6-big-tcp
enable-ipv6-big-tcp                               false

Let's first check the GSO on the node. You will see a value of 65536 – the 64K limit described earlier in the lab.
root@server:~# docker exec kind-worker ip -d -j link show dev eth0 | jq -c '.[0].gso_max_size'
65536

Let's deploy a netperf client and a netperf server:
root@server:~# kubectl apply -f https://raw.githubusercontent.com/NikAleksandrov/cilium/42b93676d85783aa167105a91e44078ce6731297/test/bigtcp/netperf.yaml
pod/netperf-server created
pod/netperf-client created
root@server:~# kubectl get pods
NAME             READY   STATUS    RESTARTS   AGE
netperf-client   1/1     Running   0          27s
netperf-server   1/1     Running   0          27s

Let's check the GSO for the netperf-server Pods. Again, expect to see 64K:
root@server:~# kubectl exec netperf-server -- \
  ip -d -j link show dev eth0 | \
  jq -c '.[0].gso_max_size'
65536

Finally, let's run a performance test. First, let's get the IPv6 address of the netperf server:
root@server:~# NETPERF_SERVER=$(kubectl get pod netperf-server -o jsonpath='{.status.podIPs}' | jq -r -c '.[].ip | select(contains(":") == true)')
echo $NETPERF_SERVER
fd00:10:244:2::e47

Let's now start the performance test:
root@server:~# kubectl exec netperf-client -- \
  netperf -t TCP_RR -H ${NETPERF_SERVER} -- \
  -r80000:80000 -O MIN_LATENCY,P90_LATENCY,P99_LATENCY,THROUGHPUT
MIGRATED TCP REQUEST/RESPONSE TEST from ::0 (::) port 0 AF_INET6 to fd00:10:244:2::e47 () port 0 AF_INET6 : first burst 0
Minimum      90th         99th         Throughput 
Latency      Percentile   Percentile              
Microseconds Latency      Latency                 
             Microseconds Microseconds            
43           88           129          12977.76   
root@server:~# kubectl exec netperf-client -- \
  netperf -t TCP_RR -H ${NETPERF_SERVER} -- \
  -r80000:80000 -O MIN_LATENCY,P90_LATENCY,P99_LATENCY,THROUGHPUT
MIGRATED TCP REQUEST/RESPONSE TEST from ::0 (::) port 0 AF_INET6 to fd00:10:244:2::e47 () port 0 AF_INET6 : first burst 0
Minimum      90th         99th         Throughput 
Latency      Percentile   Percentile              
Microseconds Latency      Latency                 
             Microseconds Microseconds            
43           89           145          13029.20   
root@server:~# kubectl exec netperf-client -- \
  netperf -t TCP_RR -H ${NETPERF_SERVER} -- \
  -r80000:80000 -O MIN_LATENCY,P90_LATENCY,P99_LATENCY,THROUGHPUT
MIGRATED TCP REQUEST/RESPONSE TEST from ::0 (::) port 0 AF_INET6 to fd00:10:244:2::e47 () port 0 AF_INET6 : first burst 0
Minimum      90th         99th         Throughput 
Latency      Percentile   Percentile              
Microseconds Latency      Latency                 
             Microseconds Microseconds            
42           89           144          13118.93   

Run the tests several times. Take a note of the latency and throughput results.

While they may fluctuate, the throughput tends to be between 4,000 and 8,000 packets per seconds.

Let's now compare when we enable BIG TCP.

Once enabled in Cilium, all nodes will be automatically configured with BIG TCP. There is no cluster downtime when enabling this feature, albeit the Kubernetes Pods must be restarted for the changes to take effect.
root@server:~# cilium config set enable-ipv6-big-tcp true
✨ Patching ConfigMap cilium-config with enable-ipv6-big-tcp=true...
♻️  Restarted Cilium pods

Let’s double-check it’s enabled:
root@server:~# cilium config view | grep ipv6-big-tcp
enable-ipv6-big-tcp                               true

root@server:~# cilium status --wait
    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    OK
 \__/¯¯\__/    Hubble Relay:       disabled
    \__/       ClusterMesh:        disabled

Deployment             cilium-operator    Desired: 2, Ready: 2/2, Available: 2/2
DaemonSet              cilium             Desired: 3, Ready: 3/3, Available: 3/3
DaemonSet              cilium-envoy       Desired: 3, Ready: 3/3, Available: 3/3
Containers:            cilium             Running: 3
                       cilium-operator    Running: 2
                       cilium-envoy       Running: 3
Cluster Pods:          5/5 managed by Cilium
Helm chart version:    1.16.0
Image versions         cilium             quay.io/cilium/cilium:v1.16.0@sha256:46ffa4ef3cf6d8885dcc4af5963b0683f7d59daa90d49ed9fb68d3b1627fe058: 3
                       cilium-operator    quay.io/cilium/operator-generic:v1.16.0@sha256:d6621c11c4e4943bf2998af7febe05be5ed6fdcf812b27ad4388f47022190316: 2
                       cilium-envoy       quay.io/cilium/cilium-envoy:v1.29.7-39a2a56bbd5b3a591f69dbca51d3e30ef97e0e51@sha256:bd5ff8c66716080028f414ec1cb4f7dc66f40d2fb5a009fff187f4a9b90b566b: 3

Let’s now verify the GSO settings on the node:
root@server:~# docker exec kind-worker ip -d -j link show dev eth0 | \
  jq -c '.[0].gso_max_size'
196608

Expect to see a reply of 196608. 196608 bytes is 192KB: the current optimal GRO/GSO value with Cilium is 192K but it can eventually be raised to 512K if additional performance benefits are observed.

As you will shortly see, the performance results with 192K were impressive, even for small-sized request/response-type workloads.

Let's redeploy the Pods for the GSO to be reflected:
root@server:~# kubectl delete -f https://raw.githubusercontent.com/NikAleksandrov/cilium/42b93676d85783aa167105a91e44078ce6731297/test/bigtcp/netperf.yaml
root@server:~# kubectl apply -f https://raw.githubusercontent.com/NikAleksandrov/cilium/42b93676d85783aa167105a91e44078ce6731297/test/bigtcp/netperf.yaml
pod "netperf-server" deleted
pod "netperf-client" deleted
pod/netperf-server created
pod/netperf-client created

Let's check the GSO on our netperf Pods to see if they've been adjusted:
root@server:~# kubectl exec netperf-server -- ip -d -j link show dev eth0 | jq -c '.[0].gso_max_size'
root@server:~# kubectl exec netperf-client -- ip -d -j link show dev eth0 | jq -c '.[0].gso_max_size'
196608
196608

Again, expect 196608 for both Pods.

Let’s run another netperf test. First, let's get the IPv6 address of the re-deployed netperf server:

root@server:~# NETPERF_SERVER=$(kubectl get pod netperf-server -o jsonpath='{.status.podIPs}' | jq -r -c '.[].ip | select(contains(":") == true)')
echo $NETPERF_SERVER
fd00:10:244:2::5089

root@server:~# kubectl exec netperf-client -- \
  netperf -t TCP_RR -H ${NETPERF_SERVER} -- \
  -r80000:80000 -O MIN_LATENCY,P90_LATENCY,P99_LATENCY,THROUGHPUT
MIGRATED TCP REQUEST/RESPONSE TEST from ::0 (::) port 0 AF_INET6 to fd00:10:244:2::5089 () port 0 AF_INET6 : first burst 0
Minimum      90th         99th         Throughput 
Latency      Percentile   Percentile              
Microseconds Latency      Latency                 
             Microseconds Microseconds            
32           66           99           18167.64   
root@server:~# kubectl exec netperf-client -- \
  netperf -t TCP_RR -H ${NETPERF_SERVER} -- \
  -r80000:80000 -O MIN_LATENCY,P90_LATENCY,P99_LATENCY,THROUGHPUT
MIGRATED TCP REQUEST/RESPONSE TEST from ::0 (::) port 0 AF_INET6 to fd00:10:244:2::5089 () port 0 AF_INET6 : first burst 0
Minimum      90th         99th         Throughput 
Latency      Percentile   Percentile              
Microseconds Latency      Latency                 
             Microseconds Microseconds            
33           66           100          18164.48   
root@server:~# kubectl exec netperf-client -- \
  netperf -t TCP_RR -H ${NETPERF_SERVER} -- \
  -r80000:80000 -O MIN_LATENCY,P90_LATENCY,P99_LATENCY,THROUGHPUT
MIGRATED TCP REQUEST/RESPONSE TEST from ::0 (::) port 0 AF_INET6 to fd00:10:244:2::5089 () port 0 AF_INET6 : first burst 0
Minimum      90th         99th         Throughput 
Latency      Percentile   Percentile              
Microseconds Latency      Latency                 
             Microseconds Microseconds            
33           65           96           18317.65 


Compare with the tests you did previously.

Expect the latency to have gone down and the throughput to have increased (typically, 8,000 to 10,000 packets per second).

As you can see, for both IPv4 and IPv6, we are seeing a 40% boost in throughput! 🚀
