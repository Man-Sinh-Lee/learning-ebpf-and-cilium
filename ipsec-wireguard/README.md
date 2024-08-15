Encryption in Cloud Native Applications

Encryption is required for many compliance frameworks.

Kubernetes doesn't natively offer encryption of data in transit.

To offer encryption capabilities, it's often required to implement it directly into your applications or deploy a Service Mesh.

Both options add complexity and operational headaches.

 Encryption in Cilium

Cilium actually provides two options to encrypt traffic between Cilium-managed endpoints: IPsec and WireGuard.

root@server:~# yq cluster.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
  - role: worker
  - role: worker
networking:
  disableDefaultCNI: true

root@server:~# kubectl get nodes
NAME                 STATUS     ROLES           AGE    VERSION
kind-control-plane   NotReady   control-plane   2m4s   v1.29.2
kind-worker          NotReady   <none>          101s   v1.29.2
kind-worker2         NotReady   <none>          102s   v1.29.2
kind-worker3         NotReady   <none>          102s   v1.29.2

Encrypt Key Management

One of the common challenges with cryptography is the management of keys. Users have to take into consideration aspects such as generation, rotation and distribution of keys.

We'll look at all these aspects in this lab and see the differences between using IPsec and WireGuard as they both have pros and cons. The way it is addressed in Cilium is elegant - the IPsec configuration and associated key are stored as a Kubernetes secret. All secrets are automatically shared across all nodes and therefore all endpoints are aware of the keys.

First, let's create a Kubernetes secret for the IPsec configuration to be stored.

The format for such IPsec Configuration and key is the following: key-id encryption-algorithms PSK-in-hex-format key-size.

Let's start by generating a random pre-shared key (PSK). We're going to create a random string of 20 characters (using dd with /dev/urandom as a source), then encode it as a hexdump with the xxd command.

Run the following command:
root@server:~# PSK=($(dd if=/dev/urandom count=20 bs=1 2> /dev/null | xxd -p -c 64))
echo $PSK
7d24d20a5c80804b79cbb344cef317809f14f7c0

The $PSK variable now contains our hexdumped PSK.

In order to configure IPsec, you will need to pass this PSK along with a key ID (we'll choose 3 here), and a specification of the algorithm to be used with IPsec (we'll use GCM-128-AES, so we'll specify rfc4106(gcm(aes))). We'll specify the block size accordingly to 128.

As a result, the Kubernetes secret will contain the value 3 rfc4106(gcm(aes)) $PSK 128.

Create a Kubernetes secret called cilium-ipsec-keys, and use this newly created PSK:
root@server:~# kubectl create -n kube-system secret generic cilium-ipsec-keys \
    --from-literal=keys="3 rfc4106(gcm(aes)) $PSK 128"
secret/cilium-ipsec-keys created

This command might look confusing at first, but essentially a Kubernetes secret is a key-value pair, with the key being the name of the file to be mounted as a volume in the cilium-agent Pods while the value is the IPsec configuration in the format described earlier.

Decoding the secret created earlier is simple:
root@server:~# SECRET="$(kubectl get secrets cilium-ipsec-keys -o jsonpath='{.data}' -n kube-system | jq -r ".keys")"
echo $SECRET | base64 --decode
3 rfc4106(gcm(aes)) 7d24d20a5c80804b79cbb344cef317809f14f7c0 128

This maps to the following Cilium IPsec configuration :

    key-id (an identifier of the key): arbitrarily set to 3
    encryption-algorithms: AES-GCM GCM
    PSK: da630c6acdbef2757ab7f5215b8b1811420e3f61
    key-size: 128

Now that the IPSec configuration has been generated, let's install Cilium and IPsec.

The cilium CLI tool will be used to install and check the status of Cilium in the cluster.

Let's start by installing Cilium on the Kind cluster, with IPsec enabled.
cilium install --version v1.16.0 \
  --set encryption.enabled=true \
  --set encryption.type=ipsec

Let's verify that IPsec was enabled by checking that the enable-ipsec key is set to true.
root@server:~# cilium config view | grep enable-ipsec
enable-ipsec                                      true
enable-ipsec-encrypted-overlay                    false
enable-ipsec-key-watcher                          true

Verification

IPsec encryption was easy to install but we need to verify that traffic has been encrypted.

We will be using the tcpdump packet capture tool for this purpose.

Day 2 Operations

Additionally, there will come a point where users will want to rotate keys.

Periodically and automatically rotating keys is a recommended security practice. Cilium currently uses 32-bit keys that can become exhausted depending on the amount of traffic in the cluster. This makes key rotation even more critical.

Some industry standards, such as Payment Card Industry Data Security Standard (PCI DSS), require the regular rotation of keys.

We will see how this can be achieved.

The endor.yaml manifest will deploy a Star Wars-inspired demo application which consists of:

    an endor Namespace, containing
    a deathstar Deployment with 1 replicas.
    a Kubernetes Service to access the Death Star pods
    a tiefighter Deployment with 1 replica
    an xwing Deployment with 1 replica

Deploy it:

root@server:~# kubectl apply -f endor.yaml
namespace/endor created
service/deathstar created
deployment.apps/deathstar created
deployment.apps/tiefighter created
deployment.apps/xwing created

root@server:~# kubectl get -f endor.yaml
NAME              STATUS   AGE
namespace/endor   Active   13s

NAME                TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
service/deathstar   LoadBalancer   10.96.49.121   <pending>     80:32486/TCP   13s

NAME                         READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/deathstar    1/1     1            1           13s
deployment.apps/tiefighter   1/1     1            1           13s
deployment.apps/xwing        1/1     1            1           13s

Now that applications are deployed in the cluster, let's verify the traffic between the components is encrypted and encapsulated in IPsec tunnels.

First, let's run a shell in one of the Cilium agents:
root@server:~# kubectl -n kube-system exec -ti ds/cilium -- bash
Defaulted container "cilium-agent" out of: cilium-agent, config (init), mount-cgroup (init), apply-sysctl-overwrites (init), mount-bpf-fs (init), clean-cilium-state (init), install-cni-binaries (init)
root@kind-control-plane:/home/cilium# apt-get update && apt-get -y install tcpdump

Let's then install the packet analyzer tcpdump to inspect some of the traffic (you may not want to run these in production environments.

Let's now run tcpdump. We are filtering based on traffic on the cilium_vxlan interface.

When using Kind, Cilium is deployed by default in vxlan tunnel mode - meaning we set VXLAN tunnels between our nodes.

In Cilium's IPsec implementation, we use Encapsulating Security Payload (ESP) as the protocol to provide confidentiality and integrity.

Let's now run tcpdump and filter based on this protocol to show IPsec traffic:
root@kind-control-plane:/home/cilium# tcpdump -n -i cilium_vxlan esp
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on cilium_vxlan, link-type EN10MB (Ethernet), snapshot length 262144 bytes
08:57:55.720756 IP 10.244.3.112 > 10.244.0.74: ESP(spi=0x00000003,seq=0xc5), length 80
08:57:55.721022 IP 10.244.0.74 > 10.244.3.112: ESP(spi=0x00000003,seq=0xc5), length 192
08:57:55.721350 IP 10.244.3.112 > 10.244.0.74: ESP(spi=0x00000003,seq=0xc6), length 164
08:57:55.721530 IP 10.244.0.74 > 10.244.3.112: ESP(spi=0x00000003,seq=0xc6), length 88
08:57:56.978819 IP 10.244.1.155 > 10.244.3.112: ESP(spi=0x00000003,seq=0xc4), length 192
08:57:56.979216 IP 10.244.3.112 > 10.244.1.155: ESP(spi=0x00000003,seq=0xc5), length 164
08:57:56.979390 IP 10.244.1.155 > 10.244.3.112: ESP(spi=0x00000003,seq=0xc5), length 88
08:57:56.981314 IP 10.244.1.155 > 10.244.3.112: ESP(spi=0x00000003,seq=0xc6), length 80
08:57:56.981440 IP 10.244.3.112 > 10.244.1.155: ESP(spi=0x00000003,seq=0xc6), length 80


In the example above, there are three IPs (10.244.1.155, 10.244.3.112, 10.244.0.74); yours are likely to be different). These are the IP addresses of Cilium agents and what we are seeing in the logs is a mesh of IPsec tunnels established between our agents. Notice all these tunnels were automatically provisioned by Cilium.

Every 15 seconds or so, you should see some new traffic, corresponding to the heartbeats between the Cilium agents.

Exit the tcpdump stream with Ctrl+c.


As we have seen earlier, the Cilium IPsec configuration and associated key are stored as a Kubernetes secret.

To rotate the key, you will therefore need to patch the previously created cilium-ipsec-keys Kubernetes secret, with kubectl patch secret. During the transition, the new and old keys will be used.

Let's try this now.

Exit the Cilium agent shell (with a prompt similar to root@kind-worker2:/home/cilium#):
root@server:~# read KEYID ALGO PSK KEYSIZE < <(kubectl get secret -n kube-system cilium-ipsec-keys -o go-template='{{.data.keys | base64decode}}{{printf "\n"}}')
echo $KEYID
echo $PSK
3
422587678457b6973e81210218406ca45d760fae

When you run echo $KEYID, it should return 3. We could have guessed this, since we used 3 as the key ID when we initially generated the Kubernetes secret.

Notice the value of the existing PSK by running echo $PSK.

Let's rotate the key. We'll increment the Key ID by 1 and generate a new PSK. We'll use the same key size and encryption algorithm.
root@server:~# 
NEW_PSK=($(dd if=/dev/urandom count=20 bs=1 2> /dev/null | xxd -p -c 64))
echo $NEW_PSK
patch='{"stringData":{"keys":"'$((($KEYID+1)))' rfc4106(gcm(aes)) '$NEW_PSK' 128"}}'
kubectl patch secret -n kube-system cilium-ipsec-keys -p="${patch}" -v=1
d27182087dc59e05d03a0d46000a0b8cefb4e6ff
secret/cilium-ipsec-keys patched

Check the IPsec configuration again:
root@server:~# read NEWKEYID ALGO NEWPSK KEYSIZE < <(kubectl get secret -n kube-system cilium-ipsec-keys -o go-template='{{.data.keys | base64decode}}{{printf "\n"}}')
echo $NEWKEYID
echo $NEWPSK
4
d27182087dc59e05d03a0d46000a0b8cefb4e6ff

You can see that the key ID was incremented to 4 and that the PSK value has changed. This example illustrates simple key management with IPsec with Cilium. Production use would probably be more sophisticated.

A Kubernetes secret must be provided with the IPsec key
IPsec keys need to be rotated on a regular basis
When rotating an IPsec key, the key ID must be incremented

WireGuard

As we saw in the previous task, IPsec encryption provided a great method to achieve confidentiality and integrity.

In addition to IPsec support, Cilium 1.10 also introduced an alternative technology to provide pod-to-pod encryption: WireGuard.
Wireguard

WireGuard, as described on its official website, is "an extremely simple yet fast and modern VPN that utilizes state-of-the-art cryptography".

Compared to IPsec, "it aims to be faster, simpler, leaner, and more useful, while avoiding the massive headache."

Encryption Options

Both solutions are well adopted and have their own pros and cons. In this next task, we will explain when and why you might want to choose WireGuard instead of IPsec.

Note that Cilium was uninstalled prior to this new task so that you can install it with WireGuard from scratch.

One of the appeals of WireGuard is that it is very opinionated: it leverages very robust cryptography and does not let the user choose ciphers and protocols, like we did for IPsec. It is also very simple to use.

From a Cilium user perspective, the experience is very similar to the IPsec deployment, albeit operationally even simpler. Indeed, the encryption key pair for each node is automatically generated by Cilium and key rotation is performed transparently by the WireGuard kernel module.

Again, we are using the cilium CLI tool to install Cilium, with WireGuard this time.

Before we start though, we should check that the kernel we are using has support for WireGuard:
root@server:~# uname -ar
Linux server 6.8.0-1010-gcp #11-Ubuntu SMP Fri Jun 14 16:56:45 UTC 2024 x86_64 x86_64 x86_64 GNU/Linux
WireGuard was integrated into the Linux kernel from 5.6, so our kernel is recent enough to support it. Note that WireGuard was backported to some older Kernels, such as the currently 5.4-based Ubuntu 20.04 LTS.

Cilium was automatically uninstalled before this challenge, so we can go ahead and install Cilium again, this time with WireGuard:

cilium install --version v1.16.0 \
  --set encryption.enabled=true \
  --set encryption.type=wireguard

root@server:~# kubectl get pods -n kube-system 
NAME                                         READY   STATUS    RESTARTS   AGE
cilium-84vwv                                 1/1     Running   0          45s
cilium-envoy-6jtp8                           1/1     Running   0          45s
cilium-envoy-c6j7v                           1/1     Running   0          45s
cilium-envoy-rvlc2                           1/1     Running   0          45s
cilium-envoy-zpfgd                           1/1     Running   0          45s
cilium-fxqlq                                 1/1     Running   0          45s
cilium-mfpqw                                 1/1     Running   0          45s
cilium-operator-676d46f99b-knxqg             1/1     Running   0          45s
cilium-zdfqs                                 1/1     Running   0          45s
coredns-76f75df574-9sspd                     1/1     Running   0          28m
coredns-76f75df574-bhd5x                     1/1     Running   0          28m
etcd-kind-control-plane                      1/1     Running   0          28m
kube-apiserver-kind-control-plane            1/1     Running   0          28m
kube-controller-manager-kind-control-plane   1/1     Running   0          28m
kube-proxy-2nlht                             1/1     Running   0          28m
kube-proxy-bsrcf                             1/1     Running   0          28m
kube-proxy-mc7gs                             1/1     Running   0          28m
kube-proxy-mlwm6                             1/1     Running   0          28m
kube-scheduler-kind-control-plane            1/1     Running   0          28m

You might have noticed that, unlike with IPsec, we didn't have to manually create an encryption key.

One advantage of WireGuard over IPsec is the fact that each node automatically creates its own encryption key-pair and distributes its public key via the network.cilium.io/wg-pub-key annotation in the Kubernetes CiliumNode custom resource object.

Each node's public key is then used by other nodes to decrypt and encrypt traffic from and to Cilium-managed endpoints running on that node.

You can verify this by checking the annotation on the Cilium node kind-worker2, which contains its public key:

root@server:~# kubectl get ciliumnode kind-worker2 \
  -o jsonpath='{.metadata.annotations.network\.cilium\.io/wg-pub-key}'
CNCG0M1g2QOvZRtzVVysSVHg1w/nvoi8SQtmCsBijzQ=

Let's now run a shell in one of the Cilium agents on the kind-worker2 node.

First, let's get the name of the Cilium agent.
root@server:~# CILIUM_POD=$(kubectl -n kube-system get po -l k8s-app=cilium --field-selector spec.nodeName=kind-worker2 -o name)
echo $CILIUM_POD
pod/cilium-fxqlq

Let's now run a shell on the agent.
root@server:~# kubectl -n kube-system exec -ti $CILIUM_POD -- bash
Defaulted container "cilium-agent" out of: cilium-agent, config (init), mount-cgroup (init), apply-sysctl-overwrites (init), mount-bpf-fs (init), clean-cilium-state (init), install-cni-binaries (init)
root@kind-worker2:/home/cilium# 
The prompt should be root@kind-worker2:/home/cilium#.

Let's verify that WireGuard was installed:
root@kind-worker2:/home/cilium# cilium status | grep Encryption
Encryption:                      Wireguard       [NodeEncryption: Disabled, cilium_wg0 (Pubkey: CNCG0M1g2QOvZRtzVVysSVHg1w/nvoi8SQtmCsBijzQ=, Port: 51871, Peers: 3)]

Let's explain this briefly, going backwards from the last entry:

    We have 3 peers: the agent running on each cluster node has established a secure WireGuard tunnel between itself and all other known nodes in the cluster. The WireGuard tunnel interface is named cilium_wg0.
    The WireGuard tunnel endpoints are exposed on UDP port 51871.
    Notice the public key's value is the same one you previously saw in the node's annotation.
    NodeEncryption (the ability to encrypt the traffic between Kubernetes nodes) is disabled. We will enable it on the next task.

Let's explain this briefly, going backwards from the last entry:

    We have 3 peers: the agent running on each cluster node has established a secure WireGuard tunnel between itself and all other known nodes in the cluster. The WireGuard tunnel interface is named cilium_wg0.
    The WireGuard tunnel endpoints are exposed on UDP port 51871.
    Notice the public key's value is the same one you previously saw in the node's annotation.
    NodeEncryption (the ability to encrypt the traffic between Kubernetes nodes) is disabled. We will enable it on the next task.

Let's now install the packet analyzer tcpdump to inspect some of the traffic (it may already be on the agent, from the previous task).
root@kind-worker2:/home/cilium# apt-get update && apt-get -y install tcpdump

Let's now run tcpdump. Instead of capturing traffic on the VXLAN tunnel interface, we are going to capture traffic on the WireGuard tunnel interface itself, cilium_wg0.

root@kind-worker2:/home/cilium# tcpdump -n -i cilium_wg0
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on cilium_wg0, link-type RAW (Raw IP), snapshot length 262144 bytes
09:36:30.579971 IP 172.18.0.4.38346 > 172.18.0.5.8472: OTV, flags [I] (0x08), overlay 0, instance 31059
IP 10.244.2.127.50297 > 10.244.1.228.53: 41142+ A? swapi.dev. (27)
09:36:30.580001 IP 172.18.0.4.38346 > 172.18.0.5.8472: OTV, flags [I] (0x08), overlay 0, instance 31059
IP 10.244.2.127.50297 > 10.244.1.228.53: 41293+ AAAA? swapi.dev. (27)
09:36:33.583414 IP 172.18.0.4.51181 > 172.18.0.5.8472: OTV, flags [I] (0x08), overlay 0, instance 31059
IP 10.244.2.127.44157 > 10.244.1.228.53: 5044+ A? deathstar.endor.svc.cluster.local. (51)
09:36:33.583441 IP 172.18.0.4.51181 > 172.18.0.5.8472: OTV, flags [I] (0x08), overlay 0, instance 31059
IP 10.244.2.127.44157 > 10.244.1.228.53: 5208+ AAAA? deathstar.endor.svc.cluster.local. (51)
09:36:35.586846 IP 172.18.0.4.48241 > 172.18.0.5.8472: OTV, flags [I] (0x08), overlay 0, instance 31059
IP 10.244.2.127.45400 > 10.244.1.201.53: 30670+ A? deathstar.endor.svc.cluster.local. (51)
09:36:35.586874 IP 172.18.0.4.48241 > 172.18.0.5.8472: OTV, flags [I] (0x08), overlay 0, instance 31059
IP 10.244.2.127.45400 > 10.244.1.201.53: 30864+ AAAA? deathstar.endor.svc.cluster.local. (51)
09:36:37.589652 IP 172.18.0.4.49704 > 172.18.0.5.8472: OTV, flags [I] (0x08), overlay 0, instance 31059
IP 10.244.2.127.34354 > 10.244.1.228.53: 29737+ A? disney.com. (28)
09:36:37.589679 IP 172.18.0.4.49704 > 172.18.0.5.8472: OTV, flags [I] (0x08), overlay 0, instance 31059
IP 10.244.2.127.34354 > 10.244.1.228.53: 29929+ AAAA? disney.com. (28)

Note there should be no output as we've not deployed any Pods yet.

Go to the >_ Terminal 2 tab and deploy a couple of Pods:
kubectl apply -f pod1.yaml -f pod2.yaml -o yaml

We will use these two Pods to run some pings between them and verify that traffic is being encrypted and sent through the WireGuard tunnel.

View the manifests for the two Pods, and notice that we are pinning the pods to different nodes (nodeName: kind-worker and nodeName: kind-worker2) for the purpose of the demo (it's not necessarily a good practice in production).

Verify that both pods are running (launch the command until they are):
root@server:~# kubectl get pods -owide
NAME          READY   STATUS    RESTARTS   AGE    IP             NODE           NOMINATED NODE   READINESS GATES
pod-worker    1/1     Running   0          110s   10.244.3.109   kind-worker    <none>           <none>
pod-worker2   1/1     Running   0          110s   10.244.2.100   kind-worker2   <none>           <none>
Let's get the IP address from our Pod on kind-worker2.
root@server:~# POD2=$(kubectl get pod pod-worker2 --template '{{.status.podIP}}')
echo $POD2
10.244.2.100

Let's now run a simple ping from the Pod on the kind-worker node:
root@server:~# kubectl exec -ti pod-worker -- ping $POD2
PING 10.244.2.100 (10.244.2.100) 56(84) bytes of data.

root@kind-worker2:/home/cilium# tcpdump -n -i cilium_wg0
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on cilium_wg0, link-type RAW (Raw IP), snapshot length 262144 bytes
09:40:00.862512 IP 172.18.0.4.59867 > 172.18.0.5.8472: OTV, flags [I] (0x08), overlay 0, instance 31059
IP 10.244.2.127.44994 > 10.244.1.201.53: 49644+ A? deathstar.endor.svc.cluster.local. (51)
09:40:00.862544 IP 172.18.0.4.59867 > 172.18.0.5.8472: OTV, flags [I] (0x08), overlay 0, instance 31059
IP 10.244.2.127.44994 > 10.244.1.201.53: 49870+ AAAA? deathstar.endor.svc.cluster.local. (51)
09:40:02.865287 IP 172.18.0.4.35224 > 172.18.0.5.8472: OTV, flags [I] (0x08), overlay 0, instance 31059
IP 10.244.2.127.35452 > 10.244.1.228.53: 17272+ A? deathstar.endor.svc.cluster.local. (51)
09:40:02.865317 IP 172.18.0.4.35224 > 172.18.0.5.8472: OTV, flags [I] (0x08), overlay 0, instance 31059
IP 10.244.2.127.35452 > 10.244.1.228.53: 17474+ AAAA? deathstar.endor.svc.cluster.local. (51)
09:40:04.868110 IP 172.18.0.4.47213 > 172.18.0.5.8472: OTV, flags [I] (0x08), overlay 0, instance 31059
IP 10.244.2.127.34520 > 10.244.1.201.53: 1087+ A? disney.com. (28)
09:40:04.868140 IP 172.18.0.4.47213 > 172.18.0.5.8472: OTV, flags [I] (0x08), overlay 0, instance 31059
IP 10.244.2.127.34520 > 10.244.1.201.53: 1242+ AAAA? disney.com. (28)
09:40:06.870968 IP 172.18.0.4.35528 > 172.18.0.5.8472: OTV, flags [I] (0x08), overlay 0, instance 31059
IP 10.244.2.127.40487 > 10.244.1.228.53: 41442+ A? swapi.dev. (27)
09:40:06.871001 IP 172.18.0.4.35528 > 172.18.0.5.8472: OTV, flags [I] (0x08), overlay 0, instance 31059
IP 10.244.2.127.40487 > 10.244.1.228.53: 41597+ AAAA? swapi.dev. (27)

Traffic between pods on different nodes has been sent across the WireGuard tunnels and is therefore encrypted.

That's how simple Transparent Encryption is, using WireGuard with Cilium.


WireGuard Improvements

Cilium 1.14 introduces two major improvements in WireGuard:

    Layer 7 Network Policies are now supported (it wasn't the case in 1.13).
    Node-to-node Encryption is now possible (in 1.13, only Pod-to-Pod traffic was encrypted).

Cilium was automatically uninstalled before this challenge (alongside the test Pods), so we can go ahead and install Cilium again, this time with Node-to-Node Encryption:

cilium install --version v1.16.0 \
  --set encryption.enabled=true \
  --set encryption.type=wireguard \
  --set encryption.nodeEncryption=true


Cilium is now functional on our cluster.

Let's now run a shell in one of the Cilium agents on the kind-worker2 node.

First, let's get the name of the Cilium agent.
root@server:~# CILIUM_POD=$(kubectl -n kube-system get po -l k8s-app=cilium --field-selector spec.nodeName=kind-worker2 -o name)
echo $CILIUM_POD
pod/cilium-j75wp

Let's now run a shell on the agent.
root@server:~# kubectl -n kube-system exec -ti $CILIUM_POD -- bash
Defaulted container "cilium-agent" out of: cilium-agent, config (init), mount-cgroup (init), apply-sysctl-overwrites (init), mount-bpf-fs (init), clean-cilium-state (init), install-cni-binaries (init)
root@kind-worker2:/home/cilium# 

Let's verify that WireGuard was installed:
root@kind-worker2:/home/cilium# cilium status | grep Encryption
Encryption:              Wireguard   [NodeEncryption: Enabled, cilium_wg0 (Pubkey: CNCG0M1g2QOvZRtzVVysSVHg1w/nvoi8SQtmCsBijzQ=, Port: 51871, Peers: 3)]
root@kind-worker2:/home/cilium# 
Traffic between Nodes should be encrypted by WireGuard.
First, move to >_ Terminal 2 and check the IP addresses of the nodes:
root@server:~# kubectl get nodes -o wide
NAME                 STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                         KERNEL-VERSION   CONTAINER-RUNTIME
kind-control-plane   Ready    control-plane   42m   v1.29.2   172.18.0.2    <none>        Debian GNU/Linux 12 (bookworm)   6.8.0-1010-gcp   containerd://1.7.13
kind-worker          Ready    <none>          42m   v1.29.2   172.18.0.3    <none>        Debian GNU/Linux 12 (bookworm)   6.8.0-1010-gcp   containerd://1.7.13
kind-worker2         Ready    <none>          42m   v1.29.2   172.18.0.4    <none>        Debian GNU/Linux 12 (bookworm)   6.8.0-1010-gcp   containerd://1.7.13
kind-worker3         Ready    <none>          42m   v1.29.2   172.18.0.5    <none>        Debian GNU/Linux 12 (bookworm)   6.8.0-1010-gcp   containerd://1.7.13

The nodes should have IP addresses such as 172.18.0.2, 172.18.0.3, 172.18.0.4 and 172.18.0.5.

In >_ Terminal 1, let's install and run tcpdump on the WireGuard interface cilium_wg0 once more.

Let's now install the packet analyzer tcpdump to inspect some of the traffic (it may already be on the agent, from the previous task).
apt-get update && apt-get -y install tcpdump

Find one of the node's IP address, for example for interface eth0:
root@kind-worker2:/home/cilium# ETH0_IP=$(ip a show eth0 | sed -ne '/inet 172\.18\.0/ s/.*inet \(172\.18\.0\.[0-9]\+\).*/\1/p')
echo $ETH0_IP
172.18.0.4

Run tcpdump on the WireGuard interface, focusing on the traffic coming from this IP:
root@kind-worker2:/home/cilium# tcpdump -n -i cilium_wg0 src $ETH0_IP and dst port 4240
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on cilium_wg0, link-type RAW (Raw IP), snapshot length 262144 bytes
09:45:11.122973 IP 172.18.0.4.59244 > 172.18.0.3.4240: Flags [S], seq 2877843829, win 32120, options [mss 1460,sackOK,TS val 1746424236 ecr 0,nop,wscale 7], length 0
09:45:12.155099 IP 172.18.0.4.59244 > 172.18.0.3.4240: Flags [S], seq 2877843829, win 32120, options [mss 1460,sackOK,TS val 1746425269 ecr 0,nop,wscale 7], length 0
09:45:13.180104 IP 172.18.0.4.59244 > 172.18.0.3.4240: Flags [S], seq 2877843829, win 32120, options [mss 1460,sackOK,TS val 1746426294 ecr 0,nop,wscale 7], length 0
09:45:14.204098 IP 172.18.0.4.59244 > 172.18.0.3.4240: Flags [S], seq 2877843829, win 32120, options [mss 1460,sackOK,TS val 1746427318 ecr 0,nop,wscale 7], length 0

You should see traffic from this IP (in the form 172.0.18.X) to other nodes.
This is traffic from a node to another node over port 4240, which is the port used for Healthchecks.

Traffic between nodes has been sent across the WireGuard tunnels and is therefore encrypted.

Well done for completing this task! Before we conclude, let's verify the knowledge learned with a short quiz.
WireGuard does not let the user select the encryption ciphers.
The WireGuard public keys for each node are stored as annotations in the corresponding CiliumNode resources
WireGuard provides node-to-node encryption in Cilium 1.14

In this exam, Cilium has been reinstalled and configured to use IPsec.

You task is to rotate the IPsec key.

Remember to:

    increment the key ID (be sure to check the current value)
    generate a new PSK (you have access to shell history)
    update the Kubernetes secret (you can either use the kubectl patch command, or manually base64 the value and edit the secret with kubectl edit) You can click on the top button to go back to the earlier "Managing Transparent Encryption with IPsec on Cilium" task or you can simply consult your CLI history with history 50 to remind yourselves of the commands to execute. Good luck!

