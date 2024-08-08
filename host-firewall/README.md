Cilium Host Firewall requires to use CiliumClusterwideNetworkPolicy resources and run Cilium in Kube Proxy replacement mode
Cilium Network Policies

Ever since its inception, Cilium has supported Kubernetes Network Policies to enforce traffic control to and from pods at L3/L4.

But Cilium Network Policies even go even further: by leveraging eBPF, it can provide greater visibility into packets and enforce traffic policies at L7 and can filter traffic based on criteria such as FQDN, protocol (such as kafka, grpc), etc...

Policy Manifests

Creating and manipulating these Network Policies is done declaratively using YAML manifests.

What if we could apply the Kubernetes Network Policy operating model to our hosts? Wouldn't it be nice to have a consistent security model across not just our pods, but also the hosts running the pods? Let's look at how the Cilium Host Firewall can achieve this.

Lab Setup

In this lab, we will install SSH on the nodes of a Kind cluster, then create Cluster-wide Network Policies to regulate how the nodes can be accessed using SSH.

The Control Plane node will be used as a bastion to access the other nodes in the cluster.

Create kind cluster:
kind create cluster --config kind-config.yaml

Install cilium and enable host firewall
cilium install \
  --set hostFirewall.enabled=true \
  --set kubeProxyReplacement=strict \
  --set bpf.monitorAggregation=none

Enable hubble:
cilium hubble enable

Check hostfirewall is activated:
cilium config view | grep host-firewall

Observe traffic with hubble(Terminal 2):
hubble observe --to-identity 1 --port 22 -f

for node in $(docker ps --format '{{.Names}}'); do
  echo "==== Testing connection to node $node ===="
  IP=$(docker inspect $node -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
  nc -vz -w2 $IP 22
done

Check in terminal 2 to see TCP/22 requests to all nodes forwarded.

Host policies:

Identity pods are running on control plane node:
kubectl get pods -n kube-system -l k8s-app=cilium

Access pod and list endpoints:
kubectl exec -it -n kube-system cilium-6jqcb -- cilium endpoint list

Defaulted container "cilium-agent" out of: cilium-agent, config (init), mount-cgroup (init), apply-sysctl-overwrites (init), mount-bpf-fs (init), clean-cilium-state (init), install-cni-binaries (init)
ENDPOINT   POLICY (ingress)   POLICY (egress)   IDENTITY   LABELS (source:key[=value])                                   IPv6   IPv4          STATUS   
           ENFORCEMENT        ENFORCEMENT                                                                                                     
3434       Disabled           Disabled          4          reserved:health                                                      10.244.0.13   ready   
3835       Disabled           Disabled          1          k8s:node-role.kubernetes.io/control-plane                                          ready   
                                                           k8s:node.kubernetes.io/exclude-from-external-load-balancers                                
                                                           reserved:host 

Inspect the Control Plane node's labels with:
kubectl get no kind-control-plane -o yaml | yq .metadata.labels

Apply ccnp-control-plane-apiserver.yaml policy to control plane:
kubectl apply -f ccnp-control-plane-apiserver.yaml

Apply policy to all nodes:
kubectl apply -f ccnp-default-deny.yaml

List all ccnp policy:
kubectl get ccnp

Access Hubble in terminal 2
hubble observe --identity 1 --port 22 -f

SSH to all nodes on terminal 1:
for node in $(docker ps --format '{{.Names}}'); do
  echo "==== Testing connection to node $node ===="
  IP=$(docker inspect $node -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
  nc -vz -w2 $IP 22
done

root@server:~# hubble observe --identity 1 --port 22 -f
Aug  5 00:25:47.091: 172.18.0.1:48038 (world) <> 172.18.0.2:22 (host) from-network FORWARDED (TCP Flags: SYN)
Aug  5 00:25:47.091: 172.18.0.1:48038 (world) <> 172.18.0.2:22 (host) policy-verdict:none INGRESS DENIED (TCP Flags: SYN)
Aug  5 00:25:47.091: 172.18.0.1:48038 (world) <> 172.18.0.2:22 (host) Policy denied DROPPED (TCP Flags: SYN)
Aug  5 00:25:48.141: 172.18.0.1:48038 (world) <> 172.18.0.2:22 (host) from-network FORWARDED (TCP Flags: SYN)
Aug  5 00:25:48.141: 172.18.0.1:48038 (world) <> 172.18.0.2:22 (host) policy-verdict:none INGRESS DENIED (TCP Flags: SYN)
Aug  5 00:25:48.141: 172.18.0.1:48038 (world) <> 172.18.0.2:22 (host) Policy denied DROPPED (TCP Flags: SYN)
Aug  5 00:25:49.107: 172.18.0.1:35344 (world) <> 172.18.0.4:22 (host) from-network FORWARDED (TCP Flags: SYN)
Aug  5 00:25:49.107: 172.18.0.1:35344 (world) <> 172.18.0.4:22 (host) policy-verdict:none INGRESS DENIED (TCP Flags: SYN)
Aug  5 00:25:49.107: 172.18.0.1:35344 (world) <> 172.18.0.4:22 (host) Policy denied DROPPED (TCP Flags: SYN)
Aug  5 00:25:50.125: 172.18.0.1:35344 (world) <> 172.18.0.4:22 (host) from-network FORWARDED (TCP Flags: SYN)
Aug  5 00:25:50.125: 172.18.0.1:35344 (world) <> 172.18.0.4:22 (host) policy-verdict:none INGRESS DENIED (TCP Flags: SYN)
Aug  5 00:25:50.125: 172.18.0.1:35344 (world) <> 172.18.0.4:22 (host) Policy denied DROPPED (TCP Flags: SYN)
Aug  5 00:25:51.123: 172.18.0.1:35134 (world) <> 172.18.0.3:22 (host) from-network FORWARDED (TCP Flags: SYN)
Aug  5 00:25:51.124: 172.18.0.1:35134 (world) <> 172.18.0.3:22 (host) policy-verdict:none INGRESS DENIED (TCP Flags: SYN)
Aug  5 00:25:51.124: 172.18.0.1:35134 (world) <> 172.18.0.3:22 (host) Policy denied DROPPED (TCP Flags: SYN)
Aug  5 00:25:52.174: 172.18.0.1:35134 (world) <> 172.18.0.3:22 (host) from-network FORWARDED (TCP Flags: SYN)
Aug  5 00:25:52.174: 172.18.0.1:35134 (world) <> 172.18.0.3:22 (host) policy-verdict:none INGRESS DENIED (TCP Flags: SYN)
Aug  5 00:25:52.174: 172.18.0.1:35134 (world) <> 172.18.0.3:22 (host) Policy denied DROPPED (TCP Flags: SYN)


Network Policy to use the Control Plane node as a bastion host:
kubectl apply -f ccnp-control-plane-ssh.yaml

Test SSH connections to all nodes(Only control plane node able to access):
for node in $(docker ps --format '{{.Names}}'); do
  echo "==== Testing connection to node $node ===="
  IP=$(docker inspect $node -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
  nc -vz -w2 $IP 22
done

Access from control plane as bastion:
docker exec -ti kind-control-plane bash

From control plane access to worker nodes:
for node in $(kubectl get node -o name); do
  echo "==== Testing connection to node $node ===="
  IP=$(kubectl get $node -o jsonpath='{.status.addresses[0].address}');
  nc -vz -w2 $IP 22;
done

Check on terminal 2 all ssh connections forwarded.