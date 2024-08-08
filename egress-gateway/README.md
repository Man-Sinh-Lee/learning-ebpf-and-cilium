Cilium Egress Gateway
A Kubernetes and Cilium hands-on lab by Isovalent

Kubernetes Networking

Kubernetes changes the way we think about networking. In an ideal Kubernetes world, the network would be entirely flat and all routing and security between the applications would be controlled by the Pod network, using Network Policies.

Reaching out

In many Enterprise environments, though, the applications hosted on Kubernetes need to communicate with workloads living outside the Kubernetes cluster, which are subject to connectivity constraints and security enforcement. Because of the nature of these networks, traditional firewalling usually relies on static IP addresses (or at least IP ranges). This can make it difficult to integrate a Kubernetes cluster, which has a varying —and at times dynamic— number of nodes into such a network.

Cilium Egress Gateway

Cilium’s Egress Gateway feature changes this, by allowing you to specify which nodes should be used by a pod in order to reach the outside world. Traffic from these Pods will be Source NATed to the IP address of the node and will reach the external firewall with a predictable IP, enabling the firewall to enforce the right policy on the pod.

Start by checking that the Kind cluster is up, with nodes marked as NotReady, since no default CNI was deployed, and Cilium hasn't been installed yet:
root@server:~# kubectl get nodes
NAME                 STATUS     ROLES           AGE     VERSION
kind-control-plane   NotReady   control-plane   3m1s    v1.29.2
kind-worker          NotReady   <none>          2m39s   v1.29.2
kind-worker2         NotReady   <none>          2m42s   v1.29.2
kind-worker3         NotReady   <none>          2m37s   v1.29.2
kind-worker4         NotReady   <none>          2m38s   v1.29.2

In this lab, we will dedicate two nodes in our cluster to be used as egress nodes: kind-worker3 and kind-worker4.

They will be used as egress nodes to source NAT traffic.

While not technically necessary, we will prevent workload from being scheduled on these nodes, so we can see the traffic going out through egress nodes.

In order to ensure that we don't deploy any of our test pods to the egress nodes, let's taint them (any taint key will do, we're choosing egress-gw here):

kubectl taint node kind-worker3 egress-gw:NoSchedule
kubectl taint node kind-worker4 egress-gw:NoSchedule

Let's also label the nodes. These labels will be used later on in our Gateway policy:
kubectl label nodes kind-worker3 egress-gw=true
kubectl label nodes kind-worker4 egress-gw=true

All the Kind nodes are attached to a Docker network called kind, which uses the 172.18.0.0/16 IPv4 CIDR. Verify this:
docker network inspect -f '{{range.IPAM.Config}}{{.Subnet}}, {{end}}' kind

Let's add a new dummy interface called net0 to both kind-worker3 and kind-worker4, with a new address in the 172.18.0.0/16 network.

First, add 172.18.0.42/16 to kind-worker3:
docker exec kind-worker3 ip link add net0 type dummy
docker exec kind-worker3 ip a add 172.18.0.42/16 dev net0

Next, do the same with 172.18.0.43/16 for kind-worker4:
docker exec kind-worker4 ip link add net0 type dummy
docker exec kind-worker4 ip a add 172.18.0.43/16 dev net0
These IP addresses will be used as egress IPs by Cilium.

Install Cilium to the cluster:
cilium install \
  --set kubeProxyReplacement=strict \
  --set egressGateway.enabled=true \
  --set bpf.masquerade=true \
  --set l7Proxy=false \
  --set devices="{eth+,net+}"

Let's explain these flags:

    BPF masquerading and kube-proxy replacement are requirements for the Egress Gateway feature.
    The L7 proxy is incompatible with Egress Gateway so we're disabling it.
    We are attaching two network interfaces to the egress nodes, called eth0 and net0.

Verify that Cilium is running fine:
cilium status --wait

Verify also that Cilium was started with the Egress Gateway feature:
cilium config view | grep egress-gateway
egress-gateway-reconciliation-trigger-interval    1s
enable-ipv4-egress-gateway 

On worker3 and worker4, we expect that Cilium has detected both eth0 and net0 interfaces and set them up for masquerading.

Verify this on worker3:
CILIUM3_POD=$(kubectl -n kube-system get po -l k8s-app=cilium --field-selector spec.nodeName=kind-worker3 -o name)
kubectl -n kube-system exec -ti $CILIUM3_POD -- cilium status
KubeProxyReplacement:                  Strict   [eth0    172.18.0.4 fc00:f853:ccd:e793::4 fe80::42:acff:fe12:4 (Direct Routing)]
Masquerading:                          BPF   [eth0]   10.244.4.0/24 [IPv4: Enabled, IPv6: Disabled]

CILIUM4_POD=$(kubectl -n kube-system get po -l k8s-app=cilium --field-selector spec.nodeName=kind-worker4 -o name)
kubectl -n kube-system exec -ti $CILIUM4_POD -- cilium status
KubeProxyReplacement:     Strict   [eth0    172.18.0.3 fc00:f853:ccd:e793::3 fe80::42:acff:fe12:3 (Direct Routing)]
Masquerading:             BPF   [eth0]   10.244.3.0/24 [IPv4: Enabled, IPv6: Disabled]


An External Outpost

The rebel Alliance is trying hard to hide from the Empire.

They want to deploy a secret outpost that is only accessible to rebel ships, and not to imperial ones.

The outpost will be a simple HTTP application running on the kind Docker network, and replying to requests with the caller's IP address.

We will then attempt to access this outpost server from within the Kubernetes cluster.

An Identification Issue

Since the outpost is outside of the Kubernetes cluster, workload metadata cannot be used to identify the source of the traffic.

For this reason, the application must rely on source IP addresses to filter the traffic. The security team has decided to only allow traffic coming from 172.18.0.42 and 172.18.0.43.

Let's deploy the outpost application.

It needs to be attached to the kind network, and we will pass the allowed source IP addresses as environment variables:
docker run -d \
  --name remote-outpost \
  --network kind \
  -e ALLOWED_IP=172.18.0.42,172.18.0.43 \
   quay.io/isovalent-dev/egressgw-whatismyip:latest

Retrieve the container's IP in a variable:
OUTPOST=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' remote-outpost)
echo $OUTPOST
curl http://$OUTPOST:8000
Access denied. Your source IP (172.18.0.1) doesn't match the allowed IPs (172.18.0.42,172.18.0.43)
This shows that the outpost service was accessed from the host bridge IP for the kind Docker network, which is 172.18.0.1. The application is refusing to answer because it only accepts requests coming from 172.18.0.42 or 172.18.0.43 as we previously configured it.

In this scenario, we use an "Outpost server" to demonstrate the Egress Gateway feature.

The general use case is to access resources whose ingress is filtered by source IP, such as firewalls or databases.

Let's deploy two starships in the default namespace: an imperial Tie Fighter and a rebel X-Wing. We'll adjust the labels to reflect their loyalty:

kubectl run tiefighter \
  --labels "org=empire,class=tiefighter" \
  --image docker.io/tgraf/netperf
kubectl run xwing \
  --labels "org=alliance,class=xwing" \
  --image docker.io/tgraf/netperf

kubectl get pod --show-labels

kubectl exec -ti tiefighter -- curl --max-time 2 http://$OUTPOST:8000
The source IP is the internal IP of the node where the Tie Fighter pod is running. Since we use tunneling (VXLAN), traffic is source NAT'ed with the node's IP address.

You will get a similar result with the X-Wing (the source IP might be different if the pod runs on a different node):
kubectl exec -ti xwing -- curl --max-time 2 http://$OUTPOST:8000
Access denied. Your source IP (172.18.0.2) doesn't match the allowed IPs (172.18.0.42,172.18.0.43)

The source IP is the internal IP of the node where the Tie Fighter pod is running. Since we use tunneling (VXLAN), traffic is source NAT'ed with the node's IP address.

You will get a similar result with the X-Wing (the source IP might be different if the pod runs on a different node):
kubectl exec -ti xwing -- curl --max-time 2 http://$OUTPOST:8000
Access denied. Your source IP (172.18.0.2) doesn't match the allowed IPs (172.18.0.42,172.18.0.43)

Add an Egress Gateway Policy

Now that we have an echo server and two pollers, let's configure Cilium so that it knows how to route the traffic from the pollers to the echo server.

We will use a CiliumEgressGatewayPolicy resource type to let Cilium know which egress needs to be used for this traffic.

This will allow traffic to flow out the Kubernetes cluster through one of the two egress nodes.

Let's create an Egress Gateway Policy to route traffic from Alliance starships to the kind Docker network (172.18.0.0/16) through an egress nodes.

With this policy, traffic coming from pods labeled as org=alliance will be source NAT'ed through one of the two egress nodes (kind-worker3 and kind-worker4), using their extra IP (172.18.0.42 and 172.18.0.43 respectively).

kubectl apply -f egress-gw-policy.yaml

Try to access the outpost server again from the X-Wing pod:
kubectl exec -ti xwing -- \
  curl --max-time 2 http://172.18.0.7:8000
Access granted. Your source IP (172.18.0.42) matches an allowed IP.

The connection is now accepted, as the traffic exits the cluster through one of the two allowed IP addresses.

Now check again with the Tie Fighter:
. Your source IP (172.18.0.42) matches an allowed IP.
root@server:~# kubectl exec -ti tiefighter -- \
  curl --max-time 2 http://172.18.0.7:8000
Access denied. Your source IP (172.18.0.2) doesn't match the allowed IPs (172.18.0.42,172.18.0.43)

Since the Tie Fighter pod doesn't match the policy's selector, it still accesses the outpost through its node's IP address, which is not valid.

To be sure, let's deploy another alliance starship, a Y-Wing:
kubectl run ywing \
  --labels "org=alliance,class=ywing" \
  --image docker.io/tgraf/netperf

kubectl get po ywing

kubectl exec -ti ywing -- \
  curl --max-time 2 http://172.18.0.7:8000
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
It works, because the policy uses org=alliance, which matches the Y-Wing pod!

Let's dive a little bit into the routing mechanism for the Egress Gateway.

First, get the node on which the xwing pod is running:
kubectl get po xwing -o wide
Now, find the Cilium pod running on that node:
kubectl -n kube-system get po -l k8s-app=cilium \
  --field-selector spec.nodeName=kind-worker
NAME           READY   STATUS    RESTARTS   AGE
cilium-2rh79   1/1     Running   0          20m

Inspect the Egress data for that Cilium pod:
kubectl -n kube-system exec -ti pod/cilium-2rh79 -c cilium-agent -- \
  cilium bpf egress list
Source IP      Destination CIDR   Egress IP   Gateway IP
10.244.1.254   172.18.0.0/16      0.0.0.0     172.18.0.4
10.244.2.68    172.18.0.0/16      0.0.0.0     172.18.0.4


    The source IP field is the IP of the source Pod, which in our case are the X-Wing and Y-Wing pods.
    The destination CIDR is the one specified in our Egress Gateway Policy (the kind Docker network).
    the egress IP field is set to 0.0.0.0 because that node is not configured as a gateway.
    the gateway IP is the IP of the next hop for a packet matching the source and destination, which is the IP of one of the egress nodes.

Let's figure out which node has this IP.

Get the IP value from the Cilium output:

GATEWAY_IP=$(kubectl -n kube-system exec -ti pod/cilium-2rh79 -c cilium-agent -- cilium bpf egress list -o json | jq -r '.[0].GatewayIP')
echo $GATEWAY_IP
Then find out which nodes it is attached to:
EGRESS_NODE=$(kubectl get no  -o json | jq -r ".items[] | select(.status.addresses[].address==\"$GATEWAY_IP\").metadata.name")
echo $EGRESS_NODE

Now inspect the Egress Policy on this node:
CILIUM_POD=$(kubectl -n kube-system get po -l k8s-app=cilium --field-selector spec.nodeName=$EGRESS_NODE -o name)
kubectl -n kube-system exec -ti $CILIUM_POD -c cilium-agent -- \
  cilium bpf egress list
Source IP      Destination CIDR   Egress IP     Gateway IP
10.244.1.254   172.18.0.0/16      172.18.0.42   172.18.0.4
10.244.2.68    172.18.0.0/16      172.18.0.42   172.18.0.4

This egress IP should match the reply you got from the echo server earlier, as it is the IP used to masquerade traffic for that Egress Gateway Policy.

Access the outpost from the X-Wing a few times in a loop:
root@server:~# for i in $(seq 1 10); do
  kubectl exec -ti xwing -- \
    curl --max-time 2 http://172.18.0.7:8000
done
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.

Note that traffic always exits the cluster from the same IP address, which means it always uses the same exit node.

In Cilium OSS, Egress Gateway Policies are used to select a node for a traffic, and that node will always be used for that given traffic.

In the next challenge, we will see how multiple nodes can be used to load-balance outgoing traffic using Egress Gateway HA!


High Availability Wanted

The Rebel Security Team of the outpost is satisfied: they can now filter starship traffic based on the org=alliance label in the cluster. This is a great improvement!

However, they are worried about what could happen if one of the egress nodes were to fail, as the nodes are statically assigned to pods.

They want a highly available solution.

Egress Gateway HA

Isovalent Enterprise for Cilium is a hardened distribution of Cilium made by the creators of Cilium and eBPF.

Among many other features, it provides an HA version of the Egress Gateway functionality, allowing load-balancing of the exit nodes for scalability and resilience.
Note that Cilium is using Isovalent Enterprise images (with a -cee suffix).

Verify that Egress Gateway is still functioning as previously:
for i in $(seq 1 10); do
  kubectl exec -ti xwing -- \
    curl --max-time 2 http://172.18.0.7:8000
done
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.

The Egress Gateway HA feature uses a different Kubernetes CRD called IsovalentEgressGatewayPolicy.

Let's remove the previous gateway policy:
kubectl delete ciliumegressgatewaypolicies outpost

Comparing with the previous policy's spec, you can note that the gateway policy has been moved to an egressGroups section, which can be used to assign multiple egress interfaces to a single policy.

In the case of this lab, we have kept the same rule, as it matches both kind-worker3 and kind-worker4 nodes. If you wanted to be more specific, you could set the node and exit IP address with a section such as:
omparing with the previous policy's spec, you can note that the gateway policy has been moved to an egressGroups section, which can be used to assign multiple egress interfaces to a single policy.

In the case of this lab, we have kept the same rule, as it matches both kind-worker3 and kind-worker4 nodes. If you wanted to be more specific, you could set the node and exit IP address with a section such as:

egressGroups:
  - nodeSelector:
      matchLabels:
        kubernetes.io/hostname: kind-worker3
    egressIP: 172.18.0.42
  - nodeSelector:
      matchLabels:
        kubernetes.io/hostname: kind-worker4
    egressIP: 172.18.0.43

kubectl apply -f egress-gw-policy-ha.yaml

root@server:~# for i in $(seq 1 10); do
  kubectl exec -ti xwing -- \
    curl --max-time 2 http://172.18.0.7:8000
done
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.43) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.43) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.43) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.

Let's remove one of the egress nodes from the pool:
kubectl label node kind-worker3 egress-gw-
root@server:~# kubectl label node kind-worker3 egress-gw-
node/kind-worker3 unlabeled
root@server:~# for i in $(seq 1 10); do
  kubectl exec -ti xwing -- \
    curl --max-time 2 http://172.18.0.7:8000
done
Access granted. Your source IP (172.18.0.43) matches an allowed IP.
Access granted. Your source IP (172.18.0.43) matches an allowed IP.
Access granted. Your source IP (172.18.0.43) matches an allowed IP.
Access granted. Your source IP (172.18.0.43) matches an allowed IP.
Access granted. Your source IP (172.18.0.43) matches an allowed IP.
Access granted. Your source IP (172.18.0.43) matches an allowed IP.
Access granted. Your source IP (172.18.0.43) matches an allowed IP.
Access granted. Your source IP (172.18.0.43) matches an allowed IP.
Access granted. Your source IP (172.18.0.43) matches an allowed IP.
Access granted. Your source IP (172.18.0.43) matches an allowed IP.

Traffic continues to flow through kind-worker4 with IP 172.18.0.43. You can set up more egress nodes to increase resilience.

Add the label again:
root@server:~# kubectl label node kind-worker3 egress-gw=true
node/kind-worker3 labeled
root@server:~# for i in $(seq 1 10); do
  kubectl exec -ti xwing -- \
    curl --max-time 2 http://172.18.0.7:8000
done
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.43) matches an allowed IP.
Access granted. Your source IP (172.18.0.43) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.43) matches an allowed IP.
Access granted. Your source IP (172.18.0.43) matches an allowed IP.

Topology-aware Egress Routing

What about latency? With multiple egress nodes in multiple availability zones, you probably want to avoid bouncing between zones when exiting the cluster!

Another feature included in the Isovalent Enterprise for Cilium adds physical topology awareness to the egress gateway selection process.

Users can now rely on the well-known Node label topology.kubernetes.io/zone to augment the default traffic distribution in a group of HA egress gateways. This help with optimising latency and reducing cross-zone traffic costs.

At this point, we have two gateway nodes in an egressGroups and egress traffic is load-balanced across both of them. In some scenarios, it may be desired to prefer forwarding traffic to some of the gateway nodes in a group, depending on their physical location.

To simulate this scenario, let's split all 4 Kubernetes nodes into two groups, using the well-known Kubernetes topology label.
Node	Role	Availability Zone
kind-worker	compute	east
kind-worker3	egress	east
kind-worker2	compute	west
kind-worker4	egress	west

kubectl label node kind-worker topology.kubernetes.io/zone=east
kubectl label node kind-worker3 topology.kubernetes.io/zone=east

kubectl label node kind-worker2 topology.kubernetes.io/zone=west
kubectl label node kind-worker4 topology.kubernetes.io/zone=west

kubectl get no --show-labels | \
  grep --color topology.kubernetes.io/zone=

Inspect the possible values for azAffinity value in the IsovalentEgressGatewayPolicy CRD:
root@server:~# kubectl explain isovalentegressgatewaypolicies.spec.azAffinity
GROUP:      isovalent.com
KIND:       IsovalentEgressGatewayPolicy
VERSION:    v1

FIELD: azAffinity <string>

DESCRIPTION:
    AZAffinity controls the AZ affinity of the gateway nodes to the source pods
    and allows to select or prefer local (i.e. gateways in the same AZ of a
    given pod) gateways. 
     4 modes are supported: - disabled: no AZ affinity - localOnly: only local
    gateway nodes will be selected - localOnlyFirst: only local gateways nodes
    will be selected until at least one gateway is available in the AZ. When no
    more local gateways are available, gateways from different AZs will be used
    - localPriority: local gateways will be picked up first to build the list of
    active gateways. This mode is supposed to be used in combination with
    maxGatewayNodes


Edit the egress-gw-policy-ha.yaml file in the </> Editor tab. Add an azAffinity parameter to the spec to select local gateways first and fall back to gateways in other zones only once all local gateways become unavailable:
azAffinity: localOnlyFirst

root@server:~# kubectl apply -f egress-gw-policy-ha.yaml
isovalentegressgatewaypolicy.isovalent.com/outpost-ha configured

Inspect the resulting Egress Gateway Policy:
root@server:~# kubectl get isovalentegressgatewaypolicies outpost-ha -o yaml | yq
apiVersion: isovalent.com/v1
kind: IsovalentEgressGatewayPolicy
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"isovalent.com/v1","kind":"IsovalentEgressGatewayPolicy","metadata":{"annotations":{},"name":"outpost-ha"},"spec":{"azAffinity":"localOnlyFirst","destinationCIDRs":["172.18.0.0/16"],"egressGroups":[{"interface":"net0","nodeSelector":{"matchLabels":{"egress-gw":"true"}}}],"selectors":[{"podSelector":{"matchLabels":{"org":"alliance"}}}]}}
  creationTimestamp: "2024-08-07T01:52:51Z"
  generation: 2
  name: outpost-ha
  resourceVersion: "7541"
  uid: 4b96b6ef-7cb5-4305-811f-9bdfb24fd8c0
spec:
  azAffinity: localOnlyFirst
  destinationCIDRs:
    - 172.18.0.0/16
  egressGroups:
    - interface: net0
      nodeSelector:
        matchLabels:
          egress-gw: "true"
  selectors:
    - podSelector:
        matchLabels:
          org: alliance
status:
  groupStatuses:
    - activeGatewayIPs:
        - 172.18.0.4
        - 172.18.0.3
      activeGatewayIPsByAZ:
        east:
          - 172.18.0.4
        west:
          - 172.18.0.3
      healthyGatewayIPs:
        - 172.18.0.4
        - 172.18.0.3
  observedGeneration: 2

Let's find in which zone the X-Wing pod is running. First, identify the node it is running on:
root@server:~# kubectl get po xwing -o wide
NAME    READY   STATUS    RESTARTS   AGE   IP            NODE          NOMINATED NODE   READINESS GATES
xwing   1/1     Running   0          33m   10.244.2.68   kind-worker   <none>           <none>
root@server:~# kubectl get no kind-worker --show-labels | \
  grep --color topology.kubernetes.io/zone=
kind-worker   Ready    <none>   50m   v1.29.2   beta.kubernetes.io/arch=amd64,beta.kubernetes.io/os=linux,kubernetes.io/arch=amd64,kubernetes.io/hostname=kind-worker,kubernetes.io/os=linux,topology.kubernetes.io/zone=east

Find the egress IP associated with the egress node in that zone:
root@server:~# docker exec kind-worker3 ip -br add show dev net0
net0             DOWN           172.18.0.42/16 

Verify that egress traffic from the X-Wing leaves via that local gateway. The result of the following commands should return the IP you just retrieved:
root@server:~# for i in $(seq 1 10); do
  kubectl exec -ti xwing -- \
    curl --max-time 2 http://172.18.0.7:8000
done
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.

Local gateway (or gateways) will continue to be used until it becomes unavailable, in which case all traffic fails over to gateways in other availability zones. This can be simulated by temporarily suspending of the egress gateway node:
docker pause kind-worker3
root@server:~# for i in $(seq 1 10); do
  kubectl exec -ti xwing -- \
    curl --max-time 2 http://172.18.0.7:8000
done
Access granted. Your source IP (172.18.0.43) matches an allowed IP.
Access granted. Your source IP (172.18.0.43) matches an allowed IP.
Access granted. Your source IP (172.18.0.43) matches an allowed IP.
Access granted. Your source IP (172.18.0.43) matches an allowed IP.
Access granted. Your source IP (172.18.0.43) matches an allowed IP.
Access granted. Your source IP (172.18.0.43) matches an allowed IP.
Access granted. Your source IP (172.18.0.43) matches an allowed IP.
Access granted. Your source IP (172.18.0.43) matches an allowed IP.
Access granted. Your source IP (172.18.0.43) matches an allowed IP.
Access granted. Your source IP (172.18.0.43) matches an allowed IP.

unpause and Test again: traffic should flow again through the local gateway:
root@server:~# docker unpause kind-worker3
kind-worker3
root@server:~# for i in $(seq 1 10); do
  kubectl exec -ti xwing -- \
    curl --max-time 2 http://172.18.0.7:8000
done
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
Access granted. Your source IP (172.18.0.42) matches an allowed IP.
