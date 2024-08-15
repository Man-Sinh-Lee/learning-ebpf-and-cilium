New to Cilium and Network Policies?

If you're not familiar with Cilium and Network Policies, we recommend you first take the Getting Started with Cilium lab.

In the Getting Started with Cilium lab, you will implement advanced Layer 3-7 network policies in a Star Wars-inspired scenario. By the end of the lab, you will have enforced strong network policies and protected the Empire with micro-segmentation against attacks from the rebellion.

In this lab, you will re-deploy the Star Wars demo app but in addition to network policies, you will also learn about how to enforce mutual authentication between workloads.

 The Empire needs mutual authentication

Mutual Transport Layer Security (mTLS) is a mechanism that ensures the authenticity, integrity, and confidentiality of data exchanged between two entities over a network.

Unlike traditional TLS, which involves a one-way authentication process where the client verifies the server’s identity, mutual TLS adds an additional layer of security by requiring both the client and the server to authenticate each other.

Mutual TLS aims at providing authentication, confidentiality and integrity to service-to-service communications.

Mutual Authentication in Cilium

Similarly to Google’s Application Layer Transport Security (ALTS), Cilium’s mTLS-based Mutual Authentication splits the handshake protocol and record protocol apart and performs the handshake out of band of the actual packet flow.

The mTLS-based authentication layer of Cilium fulfills the authentication requirement of a connection whereas the existing in-kernel encryption layer provides confidentiality and integrity properties to the connection.

To learn more about Encryption on Cilium, you should take the Transparent Encryption lab.

This lab will focus on Mutual Authentication with Cilium.

Benefits of Cilium's Mutual Authentication Layer:

By separating the authentication handshake from data, several benefits are gained:

    The Implementation of mTLS-based authentication is simplified as it can be rolled out service by service easily.
    Any network protocol that is supported. No limitation to TCP only.
    The secrets used for authentication are safely kept away from any L3-L7 processing. This resolves a significant attack vector found in L7 proxy-based mTLS.
    Key rotation for authentication and encryption can be performed on live connections without disruptions.


Cilium was installed during the lab bootup and was deployed with the following Helm flags:
yaml

authentication:
  mutual:
    spire:
      enabled: true
      install:
        enabled: true


This enabled the mutual authentication feature and automatically deployed a SPIRE server.
If you're not familiar with SPIFFE and SPIRE, don't worry: we will explain the concepts behind SPIFFE and SPIRE (and how they integrate with Cilium) - in a later task.

Just know that SPIFFE is an identity framework for identifying and securing communications between microservices while SPIRE is a production-ready implementation of SPIFFE.

Verify that Mutual Authentication was enabled:
root@server:~# cilium config view | grep mesh-auth
mesh-auth-enabled                                 true
mesh-auth-gc-interval                             5m0s
mesh-auth-mutual-connect-timeout                  5s
mesh-auth-mutual-enabled                          true
mesh-auth-mutual-listener-port                    4250
mesh-auth-queue-size                              1024
mesh-auth-rotated-identities-queue-size           1024
mesh-auth-spiffe-trust-domain                     spiffe.cilium
mesh-auth-spire-admin-socket                      /run/spire/sockets/admin.sock
mesh-auth-spire-agent-socket                      /run/spire/sockets/agent/agent.sock
mesh-auth-spire-server-address                    spire-server.cilium-spire.svc:8081
mesh-auth-spire-server-connection-timeout         30s

You can see above that:

    Mutual Authentication is enabled.
    the port where mutual handshakes between agents will be performed is by default set to 4250.
    the SPIFFE Trust Domain is set to spiffe.cilium by default.
    the SPIRE connection timeout is set to 30s by default.

Note that the default SPIRE settings can be customized at deployment.

    Note that, while Mutual Authentication has been enabled globally, it won't apply to workloads until a network policy applicable to these workloads has the authentication.mode:required setting. You will learn more about this in the upcomign tasks.

Let's also debug log level, as this will be useful to show the actual mutual authentication later on:

root@server:~# cilium config set debug true
✨ Patching ConfigMap cilium-config with debug=true...
♻️  Restarted Cilium pods
root@server:~# cilium status --wait
    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    OK
 \__/¯¯\__/    Hubble Relay:       OK
    \__/       ClusterMesh:        disabled

Deployment             cilium-operator    Desired: 1, Ready: 1/1, Available: 1/1
DaemonSet              cilium-envoy       Desired: 3, Ready: 3/3, Available: 3/3
DaemonSet              cilium             Desired: 3, Ready: 3/3, Available: 3/3
Deployment             hubble-relay       Desired: 1, Ready: 1/1, Available: 1/1
Deployment             hubble-ui          Desired: 1, Ready: 1/1, Available: 1/1
Containers:            cilium             Running: 3
                       hubble-relay       Running: 1
                       hubble-ui          Running: 1
                       cilium-operator    Running: 1
                       cilium-envoy       Running: 3
Cluster Pods:          6/6 managed by Cilium
Helm chart version:    
Image versions         cilium             quay.io/cilium/cilium:v1.16.0@sha256:46ffa4ef3cf6d8885dcc4af5963b0683f7d59daa90d49ed9fb68d3b1627fe058: 3
                       hubble-relay       quay.io/cilium/hubble-relay:v1.16.0@sha256:33fca7776fc3d7b2abe08873319353806dc1c5e07e12011d7da4da05f836ce8d: 1
                       hubble-ui          quay.io/cilium/hubble-ui:v0.13.1@sha256:e2e9313eb7caf64b0061d9da0efbdad59c6c461f6ca1752768942bfeda0796c6: 1
                       hubble-ui          quay.io/cilium/hubble-ui-backend:v0.13.1@sha256:0e0eed917653441fded4e7cdb096b7be6a3bddded5a2dd10812a27b1fc6ed95b: 1
                       cilium-operator    quay.io/cilium/operator-generic:v1.16.0@sha256:d6621c11c4e4943bf2998af7febe05be5ed6fdcf812b27ad4388f47022190316: 1
                       cilium-envoy       quay.io/cilium/cilium-envoy:v1.29.7-39a2a56bbd5b3a591f69dbca51d3e30ef97e0e51@sha256:bd5ff8c66716080028f414ec1cb4f7dc66f40d2fb5a009fff187f4a9b90b566b: 3
root@server:~# kubectl get pods --all-namespaces 
NAMESPACE            NAME                                         READY   STATUS    RESTARTS   AGE
cilium-spire         spire-agent-5xbdx                            1/1     Running   0          7m49s
cilium-spire         spire-agent-dt7ls                            1/1     Running   0          7m49s
cilium-spire         spire-agent-pj9ll                            1/1     Running   0          7m49s
cilium-spire         spire-server-0                               2/2     Running   0          7m49s
kube-system          cilium-4wv8x                                 1/1     Running   0          35s
kube-system          cilium-7889m                                 1/1     Running   0          35s
kube-system          cilium-envoy-28pqp                           1/1     Running   0          7m49s
kube-system          cilium-envoy-j642c                           1/1     Running   0          7m49s
kube-system          cilium-envoy-xwrwn                           1/1     Running   0          7m49s
kube-system          cilium-h82wl                                 1/1     Running   0          35s
kube-system          cilium-operator-7d8974fbc8-qssr7             1/1     Running   0          7m49s
kube-system          coredns-76f75df574-7x2wz                     1/1     Running   0          61m
kube-system          coredns-76f75df574-mbhdg                     1/1     Running   0          61m
kube-system          etcd-kind-control-plane                      1/1     Running   0          61m
kube-system          hubble-relay-5446cbb587-gqtmv                1/1     Running   0          7m49s
kube-system          hubble-ui-647f4487ff-s6jsl                   2/2     Running   0          7m49s
kube-system          kube-apiserver-kind-control-plane            1/1     Running   0          61m
kube-system          kube-controller-manager-kind-control-plane   1/1     Running   0          61m
kube-system          kube-scheduler-kind-control-plane            1/1     Running   0          61m
local-path-storage   local-path-provisioner-7577fdbbfb-bn456      1/1     Running   0          61m

Deploy The Demo App

Let's deploy the Star Wars demo app used in the Getting Started with Cilium lab.

We will build upon this demo app and improve our security posture by enabling mutual authentication.

In this example, we will look at adding mutual authentication to the Star Wars demo deployed in the Getting Started with the Star Wars Demo docs and available in the Getting Started with Cilium lab.

We will assume you are familiar with this demo. If not, check the links above.

Deploy the Star Wars environment and the L3/L4 network policy used in the demo (there's no mutual authentication in the network policy yet).

root@server:~# kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/HEAD/examples/minikube/http-sw-app.yaml
kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/HEAD/examples/minikube/sw_l3_l4_policy.yaml
service/deathstar created
deployment.apps/deathstar created
pod/tiefighter created
pod/xwing created
ciliumnetworkpolicy.cilium.io/rule1 created

root@server:~# kubectl get all
NAME                            READY   STATUS    RESTARTS   AGE
pod/deathstar-b4b8ccfb5-dq75t   1/1     Running   0          16s
pod/deathstar-b4b8ccfb5-p2bhk   1/1     Running   0          16s
pod/tiefighter                  1/1     Running   0          16s
pod/xwing                       1/1     Running   0          16s

NAME                 TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
service/deathstar    ClusterIP   10.96.97.219   <none>        80/TCP    16s
service/kubernetes   ClusterIP   10.96.0.1      <none>        443/TCP   62m

NAME                        READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/deathstar   2/2     2            2           16s

NAME                                  DESIRED   CURRENT   READY   AGE
replicaset.apps/deathstar-b4b8ccfb5   2         2         2       16s

root@server:~# kubectl get cnp rule1 -o yaml | yq .spec
description: L3-L4 policy to restrict deathstar access to empire ships only
endpointSelector:
  matchLabels:
    class: deathstar
    org: empire
ingress:
  - fromEndpoints:
      - matchLabels:
          org: empire
    toPorts:
      - ports:
          - port: "80"
            protocol: TCP


This network policy will only allow traffic from endpoints labeled with org=empire to endpoints with both the class=deathstar and org=empire labels, over TCP port 80.
Let's verify that the connectivity model is the expected one.

First, verify that the Death Star Deployment is ready:
root@server:~# kubectl exec tiefighter -- \
  curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing
Ship landed

This request should be successful (the tiefighter is able to connect to the deathstar over a specific HTTP path): Ship landed

Then verify that the X-Wing ship (belong to the Alliance) is denied access to the Death Star:
root@server:~# kubectl exec xwing -- \
  curl -s --connect-timeout 1 -XPOST deathstar.default.svc.cluster.local/v1/request-landing
command terminated with exit code 28

By this stage, the Empire feels like they have established a strong policy model, which should match the model below.

The xwing cannot connect to the deathstar. And while the Empire security officers are aware, a HTTP call to a particular path might cause the Deathstar to explode, surely no officers would want to cause damage to the Empire


Despite the presence of the L3/L4 network policies, the rebels were somehow able to take control of a tiefighter and cause the Deathstar to explode!
 The Wrath of the Emperor

With no means to verify the identity of the tiefighter pilot, the Imperial fleet was compromised and the rebels managed to blow up the Deathstar.

Again.

The Emperor is pretty annoyed.

But he's brought in a new officer - you - to fix the Empire's security posture.

Protect the Empire

Emperor Palpatine wants you to implement mTLS-based mutual authentication so that the next Death Star is safe.

By using mTLS-based mutual authentication, the Empire can add strong identity authentication using X.509 certificates.

Time to enforce mutual authentication by updating the existing network policy!
Rolling out mutual authentication with Cilium is as simple as adding the following to an existing or new CiliumNetworkPolicy:

spec:
  egress|ingress:
    authentication:
        mode: "required"

Let's do that now. We will be using this policy:

root@server:~# yq sw_l3_l4_l7_mutual_authentication_policy.yaml
---
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: "rule1"
spec:
  description: "Mutual authentication enabled L7 policy"
  endpointSelector:
    matchLabels:
      org: empire
      class: deathstar
  ingress:
    - fromEndpoints:
        - matchLabels:
            org: empire
      authentication:
        mode: "required"
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
          rules:
            http:
              - method: "POST"
                path: "/v1/request-landing"

Review the changes we will be making with the existing network policy:



The notable differences are:

    we are changing the description of the policy
    we are adding L7 filtering (only allowing HTTP POST to the /v1/request-landing)
    we are adding authentication.mode: required to our ingress rules. This will ensure that, in addition to the existing policy requirements, ingress access is only for mutually authenticated workloads.

Let's now apply this policy.
root@server:~# kubectl apply -f sw_l3_l4_l7_mutual_authentication_policy.yaml
ciliumnetworkpolicy.cilium.io/rule1 configured

Re-try the connectivity tests.

Let's start with the tiefighter calling the /request-landing path :

root@server:~# kubectl exec tiefighter -- \
  curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing
Ship landed

Let's then try access from the tiefigher to the /exhaust-port path:
root@server:~# kubectl exec tiefighter -- \
  curl -s -XPUT deathstar.default.svc.cluster.local/v1/exhaust-port
Access denied

This second request should be denied , thanks to the new L7 Network Policy, preventing any tiefighter - compromised or not - from accessing the /exhaust-port.
root@server:~# kubectl exec xwing -- \
  curl -s --connect-timeout 1 -XPOST deathstar.default.svc.cluster.local/v1/request-landing
command terminated with exit code 28

This third one should time out, thanks to the L3/L4 Network Policy.

But has mutual authentication actually happened?

Earn the trust of the Emperor

Palpatine is not convinced the Death Star is entirely secured.

He wants to see an evidence of the mutual handshake.

He needs observability.

Hubble

Hubble is a fully distributed networking and security observability platform.

Hubble now provides logs and insight into mutual authentication.
Let's now observe Mutual Authentication with Hubble.

Run the connectivity checks again:
root@server:~# kubectl exec tiefighter -- curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing
kubectl exec xwing -- curl -s --connect-timeout 1 -XPOST deathstar.default.svc.cluster.local/v1/request-landing
Ship landed
command terminated with exit code 28
root@server:~# 

First, let's look at flows from the xwing to the deathstar.

The network policy should have dropped flows from the xwing as the xwing has not got the right labels.

root@server:~# hubble observe --type drop --from-pod default/xwing
Aug 15 06:04:44.290: default/xwing:60350 (ID:18525) <> default/deathstar-b4b8ccfb5-p2bhk:80 (ID:55431) Policy denied DROPPED (TCP Flags: SYN)
Aug 15 06:09:43.894: default/xwing:51006 (ID:18525) <> default/deathstar-b4b8ccfb5-dq75t:80 (ID:55431) Policy denied DROPPED (TCP Flags: SYN)
Aug 15 06:11:16.116: default/xwing:56996 (ID:18525) <> default/deathstar-b4b8ccfb5-p2bhk:80 (ID:55431) Policy denied DROPPED (TCP Flags: SYN)

The policy verdict for this traffic should be DROPPED by the L3/L4 section of the Network Policy:

The network policy should have dropped the first flow from the tiefighter to the deathstar Service over /request-landing. Why ? Because the first packet to match the mutual authentication-based network policy will kickstart the mutual authentication handshake.
root@server:~# hubble observe --type drop --from-pod default/tiefighter
Aug 15 06:09:05.868: default/tiefighter:52326 (ID:4968) <> default/deathstar-b4b8ccfb5-dq75t:80 (ID:55431) Authentication required DROPPED (TCP Flags: SYN)
Aug 15 06:11:14.959: default/tiefighter:50476 (ID:4968) <> default/deathstar-b4b8ccfb5-p2bhk:80 (ID:55431) Authentication required DROPPED (TCP Flags: SYN)

Again, this is expected: the first packet from tiefighter to deathstar is dropped as this is how Cilium is notified to start the mutual authentication process..

You should see a similar behaviour when looking for flows with the policy-verdict filter:

root@server:~# hubble observe --type policy-verdict --from-pod default/tiefighter
Aug 15 06:09:05.868: default/tiefighter:52326 (ID:4968) <> default/deathstar-b4b8ccfb5-dq75t:80 (ID:55431) policy-verdict:L3-L4 INGRESS DENIED (TCP Flags: SYN; Auth: SPIRE)
Aug 15 06:09:06.929: default/tiefighter:52326 (ID:4968) -> default/deathstar-b4b8ccfb5-dq75t:80 (ID:55431) policy-verdict:L3-L4 INGRESS ALLOWED (TCP Flags: SYN; Auth: SPIRE)
Aug 15 06:09:26.012: default/tiefighter:56790 (ID:4968) -> default/deathstar-b4b8ccfb5-dq75t:80 (ID:55431) policy-verdict:L3-L4 INGRESS ALLOWED (TCP Flags: SYN; Auth: SPIRE)
Aug 15 06:11:14.959: default/tiefighter:50476 (ID:4968) <> default/deathstar-b4b8ccfb5-p2bhk:80 (ID:55431) policy-verdict:L3-L4 INGRESS DENIED (TCP Flags: SYN; Auth: SPIRE)
Aug 15 06:11:16.017: default/tiefighter:50476 (ID:4968) -> default/deathstar-b4b8ccfb5-p2bhk:80 (ID:55431) policy-verdict:L3-L4 INGRESS ALLOWED (TCP Flags: SYN; Auth: SPIRE)
Expect logs such as (yours might be different, depending on how many times you have tried access between the Pods).

Let's explain these 3 lines of logs.
1️⃣ ALLOWED log (no mutual auth)

default/tiefighter:58032 (ID:1985) -> default/deathstar-f694cf746-vdds5:80 (ID:9215) policy-verdict:L3-L4 INGRESS ALLOWED (TCP Flags: SYN)

The first request was allowed as it happened before we applied Mutual Authentication (note that Auth: SPIRE is not in the error message).
2️⃣ DENIED (mutual auth)

default/tiefighter:45302 (ID:24806) <> default/deathstar-f694cf746-28vbm:80 (ID:9076) policy-verdict:L3-L4 INGRESS DENIED (TCP Flags: SYN; Auth: SPIRE)

The second request was denied because the mutual authentication handshake had not completed yet.
3️⃣ ALLOWED (mutual auth)

default/tiefighter:45302 (ID:24806) -> default/deathstar-f694cf746-28vbm:80 (ID:9076) policy-verdict:L3-L4 INGRESS ALLOWED (TCP Flags: SYN; Auth: SPIRE)

The last request was successful, as the handshake was successful.
Hubble CLI provides insight into the mutual authentication process.
Enabling Mutual Authentication between two workloads requires enabling the feature globally
Enabling Mutual Authentication between two workloads requires applying "authentication.mode:required" to a Cilium Network Policy.

A suspicious Emperor

The Emperor's paranoia is getting out of control.

While you impressed him with your knowledge of cloud native security, he wants to know exactly where the identities of the officers are stored and whether certificates are automatically issued and rotated.

It's time for you to explain to the Emperor how Cilium integrates with SPIFFE.

Identity Management

To address the challenges of identity verification in dynamic and heterogeneous environments, we need a framework to secure identity verification for distributed systems.

In Cilium’s current mutual auth support, that is provided through SPIFFE (Secure Production Identity Framework for Everyone).

SPIFFE Benefits

Here are some of the benefits of SPIFFE:
Trustworthy identity issuance:

SPIFFE provides a standardized mechanism for issuing and managing identities. It ensures that each service in a distributed system receives a unique and verifiable identity, even in dynamic environments where services may scale up or down frequently.
Identity attestation:

SPIFFE allows services to prove their identities through attestation. It ensures that services can demonstrate their authenticity and integrity by providing verifiable evidence about their identity, such as digital signatures or cryptographic proofs.
Dynamic and scalable environments:

SPIFFE addresses the challenges of identity management in dynamic environments. It supports automatic identity issuance, rotation, and revocation, which are critical in cloud-native architectures where services may be constantly deployed, updated, or retired.

SPIFFE Benefits

Here are some of the benefits of SPIFFE:
Trustworthy identity issuance:

SPIFFE provides a standardized mechanism for issuing and managing identities. It ensures that each service in a distributed system receives a unique and verifiable identity, even in dynamic environments where services may scale up or down frequently.
Identity attestation:

SPIFFE allows services to prove their identities through attestation. It ensures that services can demonstrate their authenticity and integrity by providing verifiable evidence about their identity, such as digital signatures or cryptographic proofs.
Dynamic and scalable environments:

SPIFFE addresses the challenges of identity management in dynamic environments. It supports automatic identity issuance, rotation, and revocation, which are critical in cloud-native architectures where services may be constantly deployed, updated, or retired.

By combining Cilium mutual authentication with SPIFFE, we establish a robust and scalable security infrastructure that provides strong mutual authentication and verifiable identities in dynamic distributed systems.


 Cilium and SPIFFE

SPIFFE provides an API model that allows workloads to request an identity from a central server. In our case, a workload means the same thing that a Cilium Security Identity does: a set of pods described by a label set.

A SPIFFE identity is a subclass of URI, and looks something like this: spiffe://trust.domain/path/with/encoded/info.

There are two main parts of in a SPIRE setup:

    A central SPIRE server, which forms the root of trust for the trust domain.
    A per-node SPIRE agent, which first gets its own identity from the SPIRE server, then validates the identity requests of workloads running on its node.

SPIFFE and SPIRE workflow

When a workload wants to get its identity, usually at startup, it connects to the local SPIRE agent using the SPIFFE workload API, and describes itself to the agent.

The SPIRE agent then checks that the workload is really who it says it is, and then connects to the SPIRE server and attests that the workload is requesting an identity, and that the request is valid.

The SPIRE agent checks a number of things about the workload, that the pod is actually running on the node it’s coming from, that the labels match, and so on.

Once the SPIRE agent has requested an identity from the SPIRE server, it passes it back to the workload in the SVID (SPIFFE Verified Identity Document) format. This document includes a TLS keypair in the X.509 version.

In the usual flow for SPIRE, the workload requests its own information from the SPIRE server.

In Cilium’s support for SPIFFE, the Cilium agents get a common SPIFFE identity and can themselves ask for identities on behalf of other workloads.

A SPIRE server was automatically deployed when installing Cilium with the mutual authentication feature.

The SPIRE environment will manage the TLS certificates for the workloads managed by Cilium.

Let's first verify that the SPIRE server and agents automatically deployed are working as expected.

The SPIRE server is deployed as a StatefulSet and the SPIRE agents are deployed as a DaemonSet (you should therefore see one SPIRE agent per node). Check them with:
root@server:~# kubectl get all -n cilium-spire
NAME                    READY   STATUS    RESTARTS   AGE
pod/spire-agent-5xbdx   1/1     Running   0          43m
pod/spire-agent-dt7ls   1/1     Running   0          43m
pod/spire-agent-pj9ll   1/1     Running   0          43m
pod/spire-server-0      2/2     Running   0          43m

NAME                   TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
service/spire-server   ClusterIP   10.96.90.152   <none>        8081/TCP   43m

NAME                         DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
daemonset.apps/spire-agent   3         3         3       3            3           <none>          43m

NAME                            READY   AGE
statefulset.apps/spire-server   1/1     43m

The SPIRE server StatefulSet and Spire agent DaemonSet should both be Ready.

Let's run a healthcheck on the SPIRE server.
root@server:~# kubectl exec -n cilium-spire spire-server-0 -c spire-server -- \
  /opt/spire/bin/spire-server healthcheck
Server is healthy.

Let's verify the list of SPIRE agents:
root@server:~# kubectl exec -n cilium-spire spire-server-0 -c spire-server -- \
  /opt/spire/bin/spire-server agent list
Found 3 attested agents:

SPIFFE ID         : spiffe://spiffe.cilium/spire/agent/k8s_psat/kind-kind/d620e2ab-9e6d-450f-ac20-0871af153fed
Attestation type  : k8s_psat
Expiration time   : 2024-08-15 07:09:44 +0000 UTC
Serial number     : 36395842222388412777647018472995718494
Can re-attest     : true

SPIFFE ID         : spiffe://spiffe.cilium/spire/agent/k8s_psat/kind-kind/8bb9760b-dd95-492c-89c6-bc6bf1ca5a8c
Attestation type  : k8s_psat
Expiration time   : 2024-08-15 07:09:23 +0000 UTC
Serial number     : 188539913860656106237223551968475977476
Can re-attest     : true

SPIFFE ID         : spiffe://spiffe.cilium/spire/agent/k8s_psat/kind-kind/784d63d1-e506-4dd1-9bb6-c2d13daeeb8f
Attestation type  : k8s_psat
Expiration time   : 2024-08-15 07:09:31 +0000 UTC
Serial number     : 315446843733603417262399102365270846556
Can re-attest     : true

Note that there are 3 agents, one per node (and we have three nodes in this cluster).

Notice as well that the SPIRE Server uses Kubernetes Projected Service Account Tokens (PSATs) to verify the identity of a SPIRE Agent running on a Kubernetes Cluster.
Now that we know the SPIRE service is healthy, let's verify that the Cilium and SPIRE integration has been successful.

First, verify that the Cilium agent and operator have identities on the SPIRE server:
root@server:~# kubectl exec -n cilium-spire spire-server-0 -c spire-server -- \
  /opt/spire/bin/spire-server entry show -parentID spiffe://spiffe.cilium/ns/cilium-spire/sa/spire-agent
Found 2 entries
Entry ID         : 2a869474-f6d9-4664-ae97-6ed4d30b8492
SPIFFE ID        : spiffe://spiffe.cilium/cilium-agent
Parent ID        : spiffe://spiffe.cilium/ns/cilium-spire/sa/spire-agent
Revision         : 0
X509-SVID TTL    : default
JWT-SVID TTL     : default
Selector         : k8s:ns:kube-system
Selector         : k8s:sa:cilium

Entry ID         : f59eb994-df80-4776-8e1b-2c5fbea7773a
SPIFFE ID        : spiffe://spiffe.cilium/cilium-operator
Parent ID        : spiffe://spiffe.cilium/ns/cilium-spire/sa/spire-agent
Revision         : 0
X509-SVID TTL    : default
JWT-SVID TTL     : default
Selector         : k8s:ns:kube-system
Selector         : k8s:sa:cilium-operator

Note the SPIFFE ID and Selector fields, which point to two workloads: the Cilium agent and the Cilium Operator, showing that the Cilium agent and operator each have a registered delegate identity with the SPIRE Server.

Let's now verify that the Cilium operator has registered identities with the SPIRE server on behalf of the workloads (Kubernetes Pods).

First, get the Cilium Identity of the deathstar Pods:
root@server:~# IDENTITY_ID=$(kubectl get cep -l app.kubernetes.io/name=deathstar -o=jsonpath='{.items[0].status.identity.id}')
echo $IDENTITY_ID
55431

Even though there are two of these Pods, they share the same Cilium Identity, since they use the same set of Kubernetes labels.

The SPIFFE ID —that uniquely identifies a workload— is based on the Cilium identity. It follows the spiffe://spiffe.cilium/identity/$IDENTITY_ID format.

Verify that the Death Star pods have a registered SPIFFE identity on the SPIRE server:
root@server:~# kubectl exec -n cilium-spire spire-server-0 -c spire-server -- \
  /opt/spire/bin/spire-server entry show -spiffeID spiffe://spiffe.cilium/identity/$IDENTITY_ID
Found 1 entry
Entry ID         : 2615cf8f-48ac-4de0-8888-86faf6006eb1
SPIFFE ID        : spiffe://spiffe.cilium/identity/55431
Parent ID        : spiffe://spiffe.cilium/cilium-operator
Revision         : 0
X509-SVID TTL    : default
JWT-SVID TTL     : default
Selector         : cilium:mutual-auth

You can see the that the cilium-operator was listed as the Parent ID. That is because the Cilium operator is responsible for creating SPIRE entries for each Cilium identity.

List all the registration entries with:
root@server:~# kubectl exec -n cilium-spire spire-server-0 -c spire-server -- \
  /opt/spire/bin/spire-server entry show -selector cilium:mutual-auth
Found 9 entries
Entry ID         : 41e98d55-4632-446a-a92f-68bc50755911
SPIFFE ID        : spiffe://spiffe.cilium/identity/11904
Parent ID        : spiffe://spiffe.cilium/cilium-operator
Revision         : 0
X509-SVID TTL    : default
JWT-SVID TTL     : default
Selector         : cilium:mutual-auth

Entry ID         : 5e2d8b49-e6cc-4b21-bf73-1804b1f65bf8
SPIFFE ID        : spiffe://spiffe.cilium/identity/18525
Parent ID        : spiffe://spiffe.cilium/cilium-operator
Revision         : 0
X509-SVID TTL    : default
JWT-SVID TTL     : default
Selector         : cilium:mutual-auth

Entry ID         : ed9a5c20-11f7-4d52-9205-58be9b818dce
SPIFFE ID        : spiffe://spiffe.cilium/identity/22897
Parent ID        : spiffe://spiffe.cilium/cilium-operator
Revision         : 0
X509-SVID TTL    : default
JWT-SVID TTL     : default
Selector         : cilium:mutual-auth

Entry ID         : 28b46513-94c3-4245-9166-dcc799fcdacc
SPIFFE ID        : spiffe://spiffe.cilium/identity/29581
Parent ID        : spiffe://spiffe.cilium/cilium-operator
Revision         : 0
X509-SVID TTL    : default
JWT-SVID TTL     : default
Selector         : cilium:mutual-auth

Entry ID         : 0c38b735-9a18-4af4-b5d8-a68853e849fa
SPIFFE ID        : spiffe://spiffe.cilium/identity/4968
Parent ID        : spiffe://spiffe.cilium/cilium-operator
Revision         : 0
X509-SVID TTL    : default
JWT-SVID TTL     : default
Selector         : cilium:mutual-auth

Entry ID         : 2615cf8f-48ac-4de0-8888-86faf6006eb1
SPIFFE ID        : spiffe://spiffe.cilium/identity/55431
Parent ID        : spiffe://spiffe.cilium/cilium-operator
Revision         : 0
X509-SVID TTL    : default
JWT-SVID TTL     : default
Selector         : cilium:mutual-auth

Entry ID         : dfe305bf-04b3-48f1-8a3d-4eeef537feb8
SPIFFE ID        : spiffe://spiffe.cilium/identity/57709
Parent ID        : spiffe://spiffe.cilium/cilium-operator
Revision         : 0
X509-SVID TTL    : default
JWT-SVID TTL     : default
Selector         : cilium:mutual-auth

Entry ID         : dc0129ae-58f0-410b-bd29-a841b1896d79
SPIFFE ID        : spiffe://spiffe.cilium/identity/7693
Parent ID        : spiffe://spiffe.cilium/cilium-operator
Revision         : 0
X509-SVID TTL    : default
JWT-SVID TTL     : default
Selector         : cilium:mutual-auth

Entry ID         : 44d43c31-0a5c-4e62-bde6-d04cee2b9505
SPIFFE ID        : spiffe://spiffe.cilium/identity/9926
Parent ID        : spiffe://spiffe.cilium/cilium-operator
Revision         : 0
X509-SVID TTL    : default
JWT-SVID TTL     : default
Selector         : cilium:mutual-auth

There are as many entries as there are identities. Verify this these match by listing the Cilium identities in the cluster:
root@server:~# kubectl get ciliumidentities
NAME    NAMESPACE            AGE
11904   local-path-storage   47m
18525   default              39m
22897   kube-system          47m
29581   cilium-spire         47m
4968    default              39m
55431   default              39m
57709   kube-system          47m
7693    local-path-storage   47m
9926    kube-system          47m

The identify ID listed under NAME should match the digits at the end of the SPIFFE ID executed in the previous command.
An SVID is the document with which a workload proves its identity to a resource or caller. An SVID is considered valid if it has been signed by an authority within the SPIFFE ID’s trust domain.

An SVID contains a single SPIFFE ID, which represents the identity of the service presenting it. It encodes the SPIFFE ID in a cryptographically-verifiable document in an X.509 certificate.

One of the reasons for choosing SPIRE for the initial implementation of Cilium Mutual Authentication is that it will automatically rekey SVIDs before their certificate expires, and when this happens, it will notify SVID watchers, which includes the Cilium Agent.

The Cilium operator is responsible for creating SPIRE entries for each Cilium identity.
SPIFFE is a production-ready implementation of SPIRE.
Through SPIRE, TLS certificates are automatically managed and frequently rotated.
SPIFFE stands for Secure Production Identity Framework for Everyone.

One way to review what actually happened during the mutual authentication is to access the logs on the Cilium agents on the worker nodes:
root@server:~# CILIUM_KIND_WORKER=$(kubectl -n kube-system get pods -l k8s-app=cilium -o jsonpath='{.items[?(@.spec.nodeName=="kind-worker")].metadata.name}')
echo $CILIUM_KIND_WORKER
CILIUM_KIND_WORKER2=$(kubectl -n kube-system get pods -l k8s-app=cilium -o jsonpath='{.items[?(@.spec.nodeName=="kind-worker2")].metadata.name}')
echo $CILIUM_KIND_WORKER2
cilium-h82wl
cilium-7889m

Do you remember in the beginning of the lab when we had you turn on Cilium debug logs? Now is the time to take advantage of this!

Search for the specific authentication log messages and filter using grep:
root@server:~# kubectl -n kube-system -c cilium-agent logs $CILIUM_KIND_WORKER --timestamps=true | grep "Policy is requiring authentication\|Validating Server SNI\|Validated certificate\|Successfully authenticated"
kubectl -n kube-system -c cilium-agent logs $CILIUM_KIND_WORKER2 --timestamps=true | grep "Policy is requiring authentication\|Validating Server SNI\|Validated certificate\|Successfully authenticated"
2024-08-15T06:11:14.959994080Z time="2024-08-15T06:11:14Z" level=debug msg="Policy is requiring authentication" key="localIdentity=55431, remoteIdentity=4968, remoteNodeID=22781, authType=spire" subsys=auth
2024-08-15T06:11:14.961854388Z time="2024-08-15T06:11:14Z" level=debug msg="Validating Server SNI" SNI ID=4968 subsys=auth
2024-08-15T06:11:14.961866948Z time="2024-08-15T06:11:14Z" level=debug msg="Validated certificate" subsys=auth uri-san="[spiffe://spiffe.cilium/identity/4968]"
2024-08-15T06:11:14.962262432Z time="2024-08-15T06:11:14Z" level=debug msg="Successfully authenticated" key="localIdentity=55431, remoteIdentity=4968, remoteNodeID=22781, authType=spire" remote_node_ip=10.244.1.149 subsys=auth
2024-08-15T06:17:03.062902292Z time="2024-08-15T06:17:03Z" level=debug msg="Policy is requiring authentication" key="localIdentity=55431, remoteIdentity=4968, remoteNodeID=22781, authType=spire" subsys=auth
2024-08-15T06:17:03.065019273Z time="2024-08-15T06:17:03Z" level=debug msg="Validating Server SNI" SNI ID=4968 subsys=auth
2024-08-15T06:17:03.065033086Z time="2024-08-15T06:17:03Z" level=debug msg="Validated certificate" subsys=auth uri-san="[spiffe://spiffe.cilium/identity/4968]"
2024-08-15T06:17:03.065492372Z time="2024-08-15T06:17:03Z" level=debug msg="Successfully authenticated" key="localIdentity=55431, remoteIdentity=4968, remoteNodeID=22781, authType=spire" remote_node_ip=10.244.1.149 subsys=auth
2024-08-15T06:18:18.584037323Z time="2024-08-15T06:18:18Z" level=debug msg="Policy is requiring authentication" key="localIdentity=55431, remoteIdentity=4968, remoteNodeID=22781, authType=spire" subsys=auth
2024-08-15T06:18:18.585908092Z time="2024-08-15T06:18:18Z" level=debug msg="Validating Server SNI" SNI ID=4968 subsys=auth
2024-08-15T06:18:18.585920304Z time="2024-08-15T06:18:18Z" level=debug msg="Validated certificate" subsys=auth uri-san="[spiffe://spiffe.cilium/identity/4968]"
2024-08-15T06:18:18.586328405Z time="2024-08-15T06:18:18Z" level=debug msg="Successfully authenticated" key="localIdentity=55431, remoteIdentity=4968, remoteNodeID=22781, authType=spire" remote_node_ip=10.244.1.149 subsys=auth
2024-08-15T06:09:05.868396891Z time="2024-08-15T06:09:05Z" level=debug msg="Policy is requiring authentication" key="localIdentity=55431, remoteIdentity=4968, remoteNodeID=0, authType=spire" subsys=auth
2024-08-15T06:09:05.869993615Z time="2024-08-15T06:09:05Z" level=debug msg="Validating Server SNI" SNI ID=4968 subsys=auth
2024-08-15T06:09:05.870004897Z time="2024-08-15T06:09:05Z" level=debug msg="Validated certificate" subsys=auth uri-san="[spiffe://spiffe.cilium/identity/4968]"
2024-08-15T06:09:05.870345448Z time="2024-08-15T06:09:05Z" level=debug msg="Successfully authenticated" key="localIdentity=55431, remoteIdentity=4968, remoteNodeID=0, authType=spire" remote_node_ip=172.18.0.3 subsys=auth
2024-08-15T06:17:05.481732777Z time="2024-08-15T06:17:05Z" level=debug msg="Policy is requiring authentication" key="localIdentity=55431, remoteIdentity=4968, remoteNodeID=0, authType=spire" subsys=auth
2024-08-15T06:17:05.483489067Z time="2024-08-15T06:17:05Z" level=debug msg="Validating Server SNI" SNI ID=4968 subsys=auth
2024-08-15T06:17:05.483503391Z time="2024-08-15T06:17:05Z" level=debug msg="Validated certificate" subsys=auth uri-san="[spiffe://spiffe.cilium/identity/4968]"
2024-08-15T06:17:05.483810564Z time="2024-08-15T06:17:05Z" level=debug msg="Successfully authenticated" key="localIdentity=55431, remoteIdentity=4968, remoteNodeID=0, authType=spire" remote_node_ip=172.18.0.3 subsys=auth
2024-08-15T06:17:39.657465009Z time="2024-08-15T06:17:39Z" level=debug msg="Policy is requiring authentication" key="localIdentity=55431, remoteIdentity=4968, remoteNodeID=0, authType=spire" subsys=auth
2024-08-15T06:17:39.659003804Z time="2024-08-15T06:17:39Z" level=debug msg="Validating Server SNI" SNI ID=4968 subsys=auth
2024-08-15T06:17:39.659018423Z time="2024-08-15T06:17:39Z" level=debug msg="Validated certificate" subsys=auth uri-san="[spiffe://spiffe.cilium/identity/4968]"
2024-08-15T06:17:39.659275100Z time="2024-08-15T06:17:39Z" level=debug msg="Successfully authenticated" key="localIdentity=55431, remoteIdentity=4968, remoteNodeID=0, authType=spire" remote_node_ip=172.18.0.3 subsys=auth


Let's recap what happened:

    A Network Policy with authentication.mode: required was created and will apply to traffic between identity tiefighter and identity deathstar.
    First packet from tiefighter to deathstar is dropped and Cilium is notified to start the mutual authentication process. Further packets will be dropped until mutual auth has completed. (Policy is requiring authentication log)
    The Cilium agent retrieves the identity for tiefighter, connects to the node where the deathstar pod is running and performs a mutual TLS authentication handshake. (Validating Server SNI and Validated certificate logs)
    When the handshake is successful (Successfully authenticated log), mutual authentication is now complete, and packets from tiefighter to deathstar will now flow until the network policy is removed or the entry expires (which is when the certificate does).

For this exam, a client (pod-worker) and a server (echo) have been deployed in the exam namespace, along with an L7 Cilium Network Policy to only alllow the client to connect to the server over a specific HTTP path.

You can find all the manifests in the exam/ directory (the Cilium Network Policy is in exam/echo-cnp.yaml).

You will still be using the previously deployed Cilium environment with the Mutual Authentication feature enabled and the SPIRE server deployed.

Your task is to modify the Network Policy to only allow ingress access to the echo workload from mutually authenticated workloads.

Don't forget to apply the Network Policy to the cluster!

