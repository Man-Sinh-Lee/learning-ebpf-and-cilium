Welcome to the Cloud Network Engineer Discovery Lab!
This short lab will introduce you to the features presented in the Cloud Network Engineer journey of the Isovalent Cilium labs.

In particular, you will learn about:

    BGP with Cilium
    IPv6 networking
    Load-Balancer Service IP Address Management (LB-IPAM)
    BGP Service Announcement
    L2 Service Announcement
    Egress Gateway

IPv6 on Kubernetes

Kubernetes is not only IPv6-ready but it also provides a transitional pathway from IPv4 to IPv6.

With Dual Stack, each pod is allocated both an IPv4 and an IPv6 address, so it can communicate both with IPv6 systems and the legacy apps and cloud services that use IPv4.

In order to run Dual Stack on Kubernetes, you need a CNI that supports it: of course, Cilium does.

In this lab, you will be using a Dual Stack IPv4/IPv6 cluster and learn not just how Cilium can support dual stack but also advertise both routes over BGP.

Connecting the Kubernetes Island

From a networking perspective, a Kubernetes cluster is akin to an island.

Within the island, there are roads connecting all the Pods and they can communicate freely.

To connect the rest of the island (our cluster) to the mainland (our data center), we are going to need a bridge (BGP).

In this lab, you will get a taster of how Cilium natively supports BGP and how you can use it to connect your cluster to your DC network!

In this lab, a Kind Kubernetes cluster has been deployed, with Cilium to provide various network functions. The cluster was deployed in Dual Stack IPv4/IPv6 mode.

In order to verify that Cilium is properly installed and functioning, enter the following in the >_ Terminal tab:

root@server:~# cilium status --wait
    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    OK
 \__/¯¯\__/    Hubble Relay:       OK
    \__/       ClusterMesh:        disabled

Deployment             cilium-operator    Desired: 2, Ready: 2/2, Available: 2/2
Deployment             hubble-ui          Desired: 1, Ready: 1/1, Available: 1/1
Deployment             hubble-relay       Desired: 1, Ready: 1/1, Available: 1/1
DaemonSet              cilium-envoy       Desired: 3, Ready: 3/3, Available: 3/3
DaemonSet              cilium             Desired: 3, Ready: 3/3, Available: 3/3
Containers:            cilium             Running: 3
                       cilium-operator    Running: 2
                       hubble-ui          Running: 1
                       hubble-relay       Running: 1
                       cilium-envoy       Running: 3
Cluster Pods:          5/5 managed by Cilium
Helm chart version:    1.16.0
Image versions         cilium             quay.io/cilium/cilium:v1.16.0@sha256:46ffa4ef3cf6d8885dcc4af5963b0683f7d59daa90d49ed9fb68d3b1627fe058: 3
                       cilium-operator    quay.io/cilium/operator-generic:v1.16.0@sha256:d6621c11c4e4943bf2998af7febe05be5ed6fdcf812b27ad4388f47022190316: 2
                       hubble-ui          quay.io/cilium/hubble-ui:v0.13.1@sha256:e2e9313eb7caf64b0061d9da0efbdad59c6c461f6ca1752768942bfeda0796c6: 1
                       hubble-ui          quay.io/cilium/hubble-ui-backend:v0.13.1@sha256:0e0eed917653441fded4e7cdb096b7be6a3bddded5a2dd10812a27b1fc6ed95b: 1
                       hubble-relay       quay.io/cilium/hubble-relay:v1.16.0@sha256:33fca7776fc3d7b2abe08873319353806dc1c5e07e12011d7da4da05f836ce8d: 1
                       cilium-envoy       quay.io/cilium/cilium-envoy:v1.29.7-39a2a56bbd5b3a591f69dbca51d3e30ef97e0e51@sha256:bd5ff8c66716080028f414ec1cb4f7dc66f40d2fb5a009fff187f4a9b90b566b: 3


Cilium and Operator should be marked OK while some features will be marked as disabled (that's expected).

Now that we know that the Kubernetes cluster is ready, let's pretend for the duration of this lab that your cluster is located on the other side of the galaxy 💫, on a planet called Batuu 🪐, in the Trilon sector.

Your task, as an Imperial officer specialized in inter-galactic telecommunications, is to set up communications between the remote outpost on Batuu and the central base.

Note

Yes, the Cilium folks tend to overdo the Star Wars references. We hope you are familiar with Star Wars. If not, don't worry, you don't need to know any of the Star Wars trivia to enjoy this lab.

OVERLAY VS DIRECT ROUTING
Cilium allows to configure Kubernetes clusters either using an overlay network (VXLAN of Geneve) or direct routing.

This lab is configured with direct routing, and the pod CIDRs are propagated using BGP, taking advantage of an existing BGP infrastructure.

In this lab, our remote BGP peer is using FRR (Free Range Routing) and a virtual networking platform called containerlab.

Switch to the 🔗 🗺️ Network Topology tab to observe the various pieces of the infrastructure:

    router0 is the Top of Rack router
    srv-control-plane, srv-worker, and srv-worker2 are the Kubernetes nodes
    srv-client is a separate node, which hosts an Imperial outpost

Cilium natively supports BGP and enables you to set up BGP peering with network devices such as Top of Rack devices and advertise Kubernetes IP ranges (Pod CIDRs and Service IPs) to the broader data center network.

Cilium is configured to peer with the BGP Top of Rack router using CiliumBGPPeeringPolicy resources. Three of them have been deployed, one per node.

In the >_ Terminal tab, list them with:
kubectl get ciliumbgppeeringpolicy
kubectl get ciliumbgppeeringpolicy control-plane -o yaml | yq '.spec'

The key aspects of the policy are:

    the remote peer IP address (peerAddress) and AS Number (peerASN)
    your own local AS Number (localASN)

And that's it!

In this lab, we peer with the IPv6 address of the Top of Rack router (fd00:10:0:1::1).

The Autonomous System (AS) number for the control-plane node is 65001 and our remote peer's ASN is 65000: the BGP session will be an eBGP (external BGP) session as our AS numbers are different.

With the BGP peering set, the peering sessions between the Cilium nodes and the Top of Rack routers should be established successfully.

Let's verify that the sessions have been established and that routes are learned successfully (it might take a few seconds for the sessions to come up).

Run this command again:
root@server:~# cilium bgp peers
Node                 Local AS   Peer AS   Peer Address     Session State   Uptime      Family         Received   Advertised
kind-control-plane   65001      65000     fd00:10:0:1::1   established     10h55m23s   ipv4/unicast   3          1    
                                                                                       ipv6/unicast   3          1    
kind-worker          65002      65000     fd00:10:0:2::1   established     10h55m22s   ipv4/unicast   3          1    
                                                                                       ipv6/unicast   3          1    
kind-worker2         65003      65000     fd00:10:0:3::1   established     10h55m19s   ipv4/unicast   3          1    
                                                                                       ipv6/unicast   3          1    

The BGP sessions have been established!

Log on to the central base's router clab-bgp-cplane-dev-dual-router0 and check if the central base has received the routes over BGP:
root@server:~# docker exec -it clab-bgp-cplane-dev-dual-router0 \
  vtysh -c 'show bgp ipv6 '
BGP table version is 3, local router ID is 10.0.0.1, vrf id 0
Default local pref 100, local AS 65000
Status codes:  s suppressed, d damped, h history, * valid, > best, = multipath,
               i internal, r RIB-failure, S Stale, R Removed
Nexthop codes: @NNN nexthop's vrf id, < announce-nh-self
Origin codes:  i - IGP, e - EGP, ? - incomplete
RPKI validation codes: V valid, I invalid, N Not found

   Network          Next Hop            Metric LocPrf Weight Path
*> fd00:10:1::/64   fd00:10:0:1::2                         0 65001 i
*> fd00:10:1:1::/64 fd00:10:0:3::2                         0 65003 i
*> fd00:10:1:2::/64 fd00:10:0:2::2                         0 65002 i

Displayed  3 routes and 3 total paths

Given the size of the Empire and the millions of ships under imperial control, all communications have to be executed over IPv6. As some of the ships only support IPv4, the cluster was deployed in Dual Stack IPv4/IPv6 mode.

Verify that both IPv4 and IPv6 have been activated in the cluster:
root@server:~# cilium config view | grep -i 'enable-ipv. '
enable-ipv4                                       true
enable-ipv6                                       true

The remote outpost on Batuu includes a new Deathstar (the previous one has had an unfortunate accident 💥).

The batuu.yaml manifest will deploy a Star Wars-inspired demo application which consists of:

    a batuu Namespace, containing
    a deathstar Deployment with 2 replicas
    a Kubernetes Service to access the Death Star pods using either IPv4 or IPv6
    a tiefighter Deployment with 1 replica
    a tiefighter-4 Deployment with 1 replica, using IPv4 to access the Death Star
    an xwing Deployment with 1 replica

Deploy the manifest with:
kubectl apply -f batuu.yaml

kubectl -n batuu rollout status deployment deathstar
root@server:~# kubectl get -f batuu.yaml
NAME              STATUS   AGE
namespace/batuu   Active   93s

NAME                TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
service/deathstar   LoadBalancer   10.2.253.250   <pending>     80:32204/TCP   93s

NAME                           READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/deathstar      2/2     2            2           93s
deployment.apps/tiefighter     1/1     1            1           93s
deployment.apps/tiefighter-4   1/1     1            1           93s
deployment.apps/xwing          1/1     1            1           93s

Execute the command a few times until the deployment is marked as fully ready (e.g. 2/2).

Verify that the Deathstar Pods have picked up both an IPv4 and IPv6 address:
root@server:~# kubectl -n batuu describe pods -l class=deathstar | grep -A 2 IPs
IPs:
  IP:           10.1.1.25
  IP:           fd00:10:1:1::fb28
--
IPs:
  IP:           10.1.2.250
  IP:           fd00:10:1:2::c969

root@server:~# DS1_IP6=$(kubectl -n batuu get po -l class=deathstar -o jsonpath='{.items[0].status.podIPs[1].ip}')
echo $DS1_IP6
fd00:10:1:1::fb28

Test that you can access one of the Death Star pods via their IP address from the srv-client container in the BGP network:
root@server:~# docker exec -ti clab-bgp-cplane-dev-dual-srv-client curl http://[$DS1_IP6]/v1/
{
        "name": "Death Star",
        "hostname": "deathstar-7848d6c4d5-498jp",
        "model": "DS-1 Orbital Battle Station",
        "manufacturer": "Imperial Department of Military Research, Sienar Fleet Systems",
        "cost_in_credits": "1000000000000",
        "length": "120000",
        "crew": "342953",
        "passengers": "843342",
        "cargo_capacity": "1000000000000",
        "hyperdrive_rating": "4.0",
        "starship_class": "Deep Space Mobile Battlestation",
        "api": [
                "GET   /v1",
                "GET   /v1/healthz",
                "POST  /v1/request-landing",
                "PUT   /v1/cargobay",
                "GET   /v1/hyper-matter-reactor/status",
                "PUT   /v1/exhaust-port"
        ]
}

Switch to the 🔗 🛰️ Hubble UI tab, a project that is part of the Cilium realm, which lets you visualize traffic in a Kubernetes cluster as a service map.

At the moment, you are seeing four pod identities in the batuu namespace:

    xwing is for pods from the xwing deployment
    tiefighter represents pods from the tiefighter deployment
    tiefighter-4 represents pods from the tiefighter-4 deployment
    deathstar represents the various pods deployed by the deathstar deployment


The tiefighter, tiefighter-4, and xwing pods make requests to:

    the deathstar service (HTTP)
    an outpost outside of the cluster (with IP address 10.0.4.2)

In the >_ Terminal tab, observe traffic from the tiefighter to the deathstar, displaying the IP addresses with:
root@server:~# hubble observe \
  --from-pod batuu/tiefighter \
  --to-pod batuu/deathstar \
  --ip-translation=false
Aug  7 22:26:01.772 [hubble-relay-6644b65844-rv584]: 2 nodes are unavailable: kind-worker2, kind-control-plane
Aug  7 22:25:57.313: 10.1.1.205:43908 (ID:36334) -> 10.1.2.250:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: ACK)
Aug  7 22:26:00.332: 10.1.1.205:43916 (ID:36334) -> 10.1.2.250:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: SYN)
Aug  7 22:26:00.333: 10.1.1.205:43916 (ID:36334) -> 10.1.2.250:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: ACK)
Aug  7 22:26:00.333: 10.1.1.205:43916 (ID:36334) <> fd00:10:1:2::c969 (ID:39448) pre-xlate-rev TRACED (TCP)
Aug  7 22:26:00.333: 10.1.1.205:43916 (ID:36334) <> 10.1.2.250 (ID:39448) pre-xlate-rev TRACED (TCP)
Aug  7 22:26:00.333: 10.1.1.205:43916 (ID:36334) -> 10.1.2.250:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: ACK, PSH)
Aug  7 22:26:00.333: 10.1.1.205:43916 (ID:36334) -> 10.1.2.250:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: ACK, FIN)
Aug  7 22:26:00.333: 10.1.1.205:43916 (ID:36334) -> 10.1.2.250:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: ACK)
Aug  7 22:26:00.686: [fd00:10:1:1::304f]:47060 (ID:21565) -> [fd00:10:1:2::c969]:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: SYN)
Aug  7 22:26:00.687: [fd00:10:1:1::304f]:47060 (ID:21565) -> [fd00:10:1:2::c969]:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: ACK)
Aug  7 22:26:00.687: [fd00:10:1:1::304f]:47060 (ID:21565) <> fd00:10:1:2::c969 (ID:39448) pre-xlate-rev TRACED (TCP)
Aug  7 22:26:00.687: [fd00:10:1:1::304f]:47060 (ID:21565) -> [fd00:10:1:2::c969]:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: ACK, PSH)
Aug  7 22:26:00.687: [fd00:10:1:1::304f]:47060 (ID:21565) -> [fd00:10:1:2::c969]:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: ACK, FIN)
Aug  7 22:26:00.687: [fd00:10:1:1::304f]:47060 (ID:21565) -> [fd00:10:1:2::c969]:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: ACK)
Aug  7 22:26:01.693: [fd00:10:1:1::304f]:48024 (ID:21565) -> [fd00:10:1:2::c969]:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: SYN)
Aug  7 22:26:01.694: [fd00:10:1:1::304f]:48024 (ID:21565) -> [fd00:10:1:2::c969]:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: ACK)
Aug  7 22:26:01.694: [fd00:10:1:1::304f]:48024 (ID:21565) <> fd00:10:1:2::c969 (ID:39448) pre-xlate-rev TRACED (TCP)
Aug  7 22:26:01.694: [fd00:10:1:1::304f]:48024 (ID:21565) -> [fd00:10:1:2::c969]:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: ACK, PSH)
Aug  7 22:26:01.694: [fd00:10:1:1::304f]:48024 (ID:21565) -> [fd00:10:1:2::c969]:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: ACK, FIN)
Aug  7 22:26:01.694: [fd00:10:1:1::304f]:48024 (ID:21565) -> [fd00:10:1:2::c969]:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: ACK)

root@server:~# hubble observe \
  --from-pod batuu/tiefighter-4 \
  --to-pod batuu/deathstar \
  --ip-translation=false
Aug  7 22:26:36.462 [hubble-relay-6644b65844-rv584]: 2 nodes are unavailable: kind-control-plane, kind-worker2
Aug  7 22:26:32.552: 10.1.1.205:38556 (ID:36334) -> 10.1.2.250:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: ACK)
Aug  7 22:26:32.552: 10.1.1.205:38556 (ID:36334) <> fd00:10:1:2::c969 (ID:39448) pre-xlate-rev TRACED (TCP)
Aug  7 22:26:32.552: 10.1.1.205:38556 (ID:36334) <> 10.1.2.250 (ID:39448) pre-xlate-rev TRACED (TCP)
Aug  7 22:26:32.552: 10.1.1.205:38556 (ID:36334) -> 10.1.2.250:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: ACK, PSH)
Aug  7 22:26:32.552: 10.1.1.205:38556 (ID:36334) -> 10.1.2.250:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: ACK)
Aug  7 22:26:32.552: 10.1.1.205:38556 (ID:36334) -> 10.1.2.250:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: ACK, FIN)
Aug  7 22:26:34.566: 10.1.1.205:38568 (ID:36334) -> 10.1.2.250:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: SYN)
Aug  7 22:26:34.566: 10.1.1.205:38568 (ID:36334) -> 10.1.2.250:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: ACK)
Aug  7 22:26:34.566: 10.1.1.205:38568 (ID:36334) -> 10.1.2.250:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: ACK, PSH)
Aug  7 22:26:34.566: 10.1.1.205:38568 (ID:36334) <> fd00:10:1:2::c969 (ID:39448) pre-xlate-rev TRACED (TCP)
Aug  7 22:26:34.566: 10.1.1.205:38568 (ID:36334) <> 10.1.2.250 (ID:39448) pre-xlate-rev TRACED (TCP)
Aug  7 22:26:34.567: 10.1.1.205:38568 (ID:36334) -> 10.1.2.250:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: ACK, FIN)
Aug  7 22:26:34.567: 10.1.1.205:38568 (ID:36334) -> 10.1.2.250:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: ACK)
Aug  7 22:26:35.573: 10.1.1.205:38580 (ID:36334) -> 10.1.2.250:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: SYN)
Aug  7 22:26:35.573: 10.1.1.205:38580 (ID:36334) -> 10.1.2.250:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: ACK)
Aug  7 22:26:35.573: 10.1.1.205:38580 (ID:36334) <> fd00:10:1:2::c969 (ID:39448) pre-xlate-rev TRACED (TCP)
Aug  7 22:26:35.573: 10.1.1.205:38580 (ID:36334) <> 10.1.2.250 (ID:39448) pre-xlate-rev TRACED (TCP)
Aug  7 22:26:35.573: 10.1.1.205:38580 (ID:36334) -> 10.1.2.250:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: ACK, PSH)
Aug  7 22:26:35.574: 10.1.1.205:38580 (ID:36334) -> 10.1.2.250:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: ACK, FIN)
Aug  7 22:26:35.574: 10.1.1.205:38580 (ID:36334) -> 10.1.2.250:80 (ID:39448) to-endpoint FORWARDED (TCP Flags: ACK)

As you can see, with the Hubble CLI or UI, you can observe network flows in your cluster, whether they are IPv4 or IPv6!


LoadBalancer IP Address Management (LB-IPAM)

LoadBalancer IP Address Management (LB-IPAM) is a new elegant feature that lets Cilium provision IP addresses for Kubernetes LoadBalancer Services.

To allocate IP addresses for Kubernetes Services that are exposed outside of a cluster, you need a resource of the type LoadBalancer. When you use Kubernetes on a cloud provider, these resources are automatically managed for you, and their IP and/or DNS are automatically allocated. However, if you run on a bare-metal cluster, in the past, you would have needed another tool like MetalLB to allocate that address.

But maintaining yet another networking tool can be cumbersome and in Cilium 1.13, this is no longer needed: Cilium can allocate IP Addresses to Kubernetes LoadBalancer Services.

L2 IP Announcements

Since version 1.13, Cilium has provided a way to create North-South Load Balancer services in the cluster and announce them to the underlying networking using BGP.

However, not everyone with an on-premise Kubernetes cluster has a BGP-compatible infrastructure.

For this reason, Cilium now allows to use ARP in order to announce service IP addresses on Layer 2.

The Deathstar needs to be accessed over HTTP from the outpost station.

In order for this Imperial base to access the Death Star, you will need to:

    Create a Kubernetes Service of the type LoadBalancer to expose your application
    Assign an IP address to the Service
    Advertise the Service over BGP

There are several ways you can expose Kubernetes applications outside of your cluster. One common method is to use Kubernetes Services of the type LoadBalancer.

Check the Death Star service:
root@server:~# kubectl -n batuu get svc deathstar --show-labels
NAME        TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE     LABELS
deathstar   LoadBalancer   10.2.253.250   <pending>     80:32204/TCP   7m55s   org=empire

It is already set as a service of type LoadBalancer, but it doesn't have an external IP. The allocation of this IP address is typically done by a cloud provider or by a tool such as MetalLB. Cilium now natively supports this feature, with the use of the Load Balancer IP Address Management (LB-IPAM) feature.

To allocate an IP address, you will need to configure a Cilium LB IP Pool, using the CiliumLoadBalancerIPPool CRD. Inspect the provided manifest:
yq lb-pool.yaml
As you can see, this IP Pool applies to services with an org label set to empire (which the deathstar service has), and it includes both an IPv4 and an IPv6 range.

Deploy the pool with the following command:
kubectl apply -f lb-pool.yaml
kubectl get ciliumloadbalancerippools.cilium.io empire-ip-pool

root@server:~# kubectl get ciliumloadbalancerippools.cilium.io empire-ip-pool
NAME             DISABLED   CONFLICTING   IPS AVAILABLE          AGE
empire-ip-pool   false      False         18446744073709551622   22s

Verify that the Service has received both an IPv4 and an IPv6 external IPs:
root@server:~# kubectl -n batuu get svc deathstar
NAME        TYPE           CLUSTER-IP     EXTERNAL-IP                           PORT(S)        AGE
deathstar   LoadBalancer   10.2.253.250   172.18.255.200,2001:db8:dead:beef::   80:32204/TCP   11m

Retrieve the external IPs for the service:
root@server:~# SERVICE_IP4=$(kubectl -n batuu get svc deathstar -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo $SERVICE_IP4

SERVICE_IP6=$(kubectl -n batuu get svc deathstar -o jsonpath='{.status.loadBalancer.ingress[1].ip}')
echo $SERVICE_IP6
172.18.255.200
2001:db8:dead:beef::

docker exec -ti clab-bgp-cplane-dev-dual-srv-client \
  curl -s --max-time 2 http://[$SERVICE_IP6]/v1/


The request times out, because the service IP is not propagated to the BGP network.

Check the BGP Peering Policies, e.g.:

root@server:~# kubectl get ciliumbgppeeringpolicies.cilium.io control-plane -o yaml | yq '.spec.virtualRouters'
- exportPodCIDR: true
  localASN: 65001
  neighbors:
    - connectRetryTimeSeconds: 120
      eBGPMultihopTTL: 1
      holdTimeSeconds: 90
      keepAliveTimeSeconds: 30
      peerASN: 65000
      peerAddress: fd00:10:0:1::1/128
      peerPort: 179
  serviceAdvertisements:
    - LoadBalancerIP
  serviceSelector:
    matchLabels:
      announced: bgp

This means service IPs are announced by this policy, but only for services whose announced has a value of bgp.

Let's patch the deathstar service with this label:
kubectl -n batuu label service/deathstar announced=bgp

root@server:~# docker exec -ti clab-bgp-cplane-dev-dual-srv-client \
  curl -s --max-time 2 http://[$SERVICE_IP6]/v1/
{
        "name": "Death Star",
        "hostname": "deathstar-7848d6c4d5-qsqqq",
        "model": "DS-1 Orbital Battle Station",
        "manufacturer": "Imperial Department of Military Research, Sienar Fleet Systems",
        "cost_in_credits": "1000000000000",
        "length": "120000",
        "crew": "342953",
        "passengers": "843342",
        "cargo_capacity": "1000000000000",
        "hyperdrive_rating": "4.0",
        "starship_class": "Deep Space Mobile Battlestation",
        "api": [
                "GET   /v1",
                "GET   /v1/healthz",
                "POST  /v1/request-landing",
                "PUT   /v1/cargobay",
                "GET   /v1/hyper-matter-reactor/status",
                "PUT   /v1/exhaust-port"
        ]
}

As an officer, you also want to be able to check the Death Star service from the host terminal. We'll use IPv4 for this request.

curl -s --max-time 2 http://$SERVICE_IP4/v1/
It doesn't work, because the host is not part of the BGP peering network!

However, the host happens to be in the same L2 network as the rest of the containers, so let's use the L2 Load Balancer announcement!

Apply the provided CiliumL2AnnouncementPolicy manifest:
root@server:~# kubectl apply -f layer2-policy.yaml
ciliuml2announcementpolicy.cilium.io/l2announcement-policy created

root@server:~# curl -s --max-time 2 http://$SERVICE_IP4/v1/
{
        "name": "Death Star",
        "hostname": "deathstar-7848d6c4d5-qsqqq",
        "model": "DS-1 Orbital Battle Station",
        "manufacturer": "Imperial Department of Military Research, Sienar Fleet Systems",
        "cost_in_credits": "1000000000000",
        "length": "120000",
        "crew": "342953",
        "passengers": "843342",
        "cargo_capacity": "1000000000000",
        "hyperdrive_rating": "4.0",
        "starship_class": "Deep Space Mobile Battlestation",
        "api": [
                "GET   /v1",
                "GET   /v1/healthz",
                "POST  /v1/request-landing",
                "PUT   /v1/cargobay",
                "GET   /v1/hyper-matter-reactor/status",
                "PUT   /v1/exhaust-port"
        ]
}

Cilium is now announcing the service IP via ARP, so the host learned how to route it!'



Egress Gateway

In many Enterprise environments, the applications hosted on Kubernetes need to communicate with workloads living outside the Kubernetes cluster, which are subject to connectivity constraints and security enforcement. Because of the nature of these networks, traditional firewalling usually relies on static IP addresses (or at least IP ranges). This can make it difficult to integrate a Kubernetes cluster, which has a varying —and at times dynamic— number of nodes into such a network.

Cilium’s Egress Gateway feature changes this, by allowing you to specify which nodes should be used by a pod in order to reach the outside world. Traffic from these Pods will be Source NATed to the IP address of the node and will reach the external firewall with a predictable IP, enabling the firewall to enforce the right policy on the pod

The Empire has a remote outpost hosted in the remote-outpost Docker container.

This container is connected to the BGP peering network, and can be accessed directly from the pods.

For security reasons, the outpost's security team wants to identify incoming traffic, and they only allow traffic coming from the 10.0.3.42 IP address.

Try to access it from the tiefighter pod:

root@server:~# kubectl -n batuu exec -ti deployments/tiefighter -- curl http://10.0.4.2:8000
Access denied. Your source IP (10.1.1.229) doesn't match the allowed IPs (10.0.3.42)

The pod accesses the IP address from its own IPv4 (10.1.1.229), and is denied access.

The same can be seen from the xwing pod (with the 10.1.1.128 IP):
root@server:~# kubectl -n batuu exec -ti deployments/xwing -- curl http://10.0.4.2:8000
Access denied. Your source IP (10.1.1.128) doesn't match the allowed IPs (10.0.3.42)

The outpost's security team is contacting you. Answer the call with:
starcom --interactive

The kind-worker2 node in the cluster has been configured with a label egress-gw=true to distinguish it from other nodes:
root@server:~# kubectl get no kind-worker2 --show-labels
NAME           STATUS   ROLES    AGE   VERSION   LABELS
kind-worker2   Ready    <none>   11h   v1.27.3   beta.kubernetes.io/arch=amd64,beta.kubernetes.io/os=linux,egress-gw=true,kubernetes.io/arch=amd64,kubernetes.io/hostname=kind-worker2,kubernetes.io/os=linux
It has also been assigned the 10.0.3.42 IP address on its net1 interface:

root@server:~# docker exec kind-worker2 ip a show net1
2: net1: <BROADCAST,NOARP> mtu 1500 qdisc noop state DOWN group default qlen 1000
    link/ether 42:1e:36:1f:8e:e9 brd ff:ff:ff:ff:ff:ff
    inet 10.0.3.42/24 scope global net1
       valid_lft forever preferred_lft forever

Let's deploy a Cilium Egress Gateway policy that targets pod labeled org=empire. When these pods try to reach the 10.0.4.0/24 (which includes 10.0.4.2) network, the traffic will leave the Kubernetes cluster through a node labeled egress-gw=true, masquerading the source IP from the net1 interface.

Review the policy:    
root@server:~# yq egress-gw-policy.yaml
apiVersion: cilium.io/v2
kind: CiliumEgressGatewayPolicy
metadata:
  name: remote-outpost
spec:
  destinationCIDRs:
    - "10.0.4.0/24"
  selectors:
    - podSelector:
        matchLabels:
          org: empire
  egressGateway:
    nodeSelector:
      matchLabels:
        egress-gw: 'true'
    interface: net1   

kubectl apply -f egress-gw-policy.yaml

Now try to access the service from the tiefighter pod:
root@server:~# kubectl -n batuu exec -ti deployments/tiefighter -- curl http://10.0.4.2:8000
Access granted. Your source IP (10.0.3.42) matches an allowed IP.

It is authorized as the traffic is now masqueraded with the 10.0.3.42 IP address.

Check that the xwing (an alliance ship) is still denied access:
root@server:~# kubectl -n batuu exec -ti deployments/xwing -- curl http://10.0.4.2:8000
Access denied. Your source IP (10.1.1.128) doesn't match the allowed IPs (10.0.3.42)
