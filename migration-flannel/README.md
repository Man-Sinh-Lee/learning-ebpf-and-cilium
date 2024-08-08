Migrating to Cilium

Migrating to Cilium from another CNI is a very common task. But how do we minimize the impact during the migration? How do we ensure pods on the legacy CNI can still communicate to Cilium-managed during pods during the migration? How do we execute the migration safely, while avoiding a overly complex approach or using a separate tool such as Multus?

With the use of the new Cilium CRD CiliumNodeConfig, running clusters can be migrated on a node-by-node basis, without disrupting existing traffic or requiring a complete cluster outage or rebuild.

root@server:~# kubectl get nodes
NAME                 STATUS   ROLES           AGE   VERSION
kind-control-plane   Ready    control-plane   84s   v1.29.2
kind-worker          Ready    <none>          61s   v1.29.2
kind-worker2         Ready    <none>          60s   v1.29.2
root@server:~# kubectl get ds/kube-flannel-ds -n kube-flannel
NAME              DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
kube-flannel-ds   3         3         3       3            3           <none>          74s

kubectl get node -o jsonpath="{range .items[*]}{.metadata.name} {.spec.podCIDR}{'\n'}{end}" | column -t

Deploy nginx:
kubectl create deployment nginx --image nginx --port 80 --replicas 10

When the kubelet creates a Pod’s Sandbox, the CNI (specified in the /etc/cni/net.d/ directory) is called. The CNI will handle the networking for a Pod - including allocating an IP address, creating & configuring a network interface, and (potentially) establishing an overlay network. The Pod’s network configuration shares the same life cycle as the PodSandbox.

When migrating CNIs, there are several approaches with pros and cons.

Migration Approaches

    The ideal scenario is to build a brand new cluster and to migrate workloads using a GitOps approach. But this can involve a lot of prep work and potential disruptions.
    Another method consists in reconfiguring /etc/cni/net.d/ to point to Cilium. However, any existing Pods will still have been configured by the old network plugin and any new Pods will be configured by the newer CNI. To complete the migration, all Pods on the cluster that are configured by the old CNI must be recycled in order to be a member of the new CNI.
    A naive approach to migrating a CNI would be to reconfigure all nodes with a new CNI and then gradually restart each node in the cluster, thus replacing the CNI when the node is brought back up and ensuring that all pods are part of the new CNI. This simple migration, while effective, comes at the cost of disrupting cluster connectivity during the rollout. Unmigrated and migrated nodes would be split in to two “islands” of connectivity, and pods would be randomly unable to reach one-another until the migration is complete.

Migration via dual overlays

Cilium supports a hybrid mode, where two separate overlays are established across the cluster. While Pods on a given node can only be attached to one network, they have access to both Cilium and non-Cilium pods while the migration is taking place. As long as Cilium and the existing networking provider use a separate IP range, the Linux routing table takes care of separating traffic.

In this lab, we will use a model for live migrating between two deployed CNI implementations. This will have the benefit of reducing downtime of nodes and workloads and ensuring that workloads on both configured CNIs can communicate during migration.

For live migration to work, Cilium will be installed with a separate CIDR range and encapsulation port than that of the currently installed CNI. As long as Cilium and the existing CNI use a separate IP range, the Linux routing table takes care of separating traffic.

Requirements

Live migration requires the following:

    A new, distinct Cluster CIDR for Cilium to use
    Use of the Cluster Pool IPAM mode
    A distinct overlay, either protocol or port
    An existing network plugin that uses the Linux routing stack, such as Flannel, Calico, or AWS-CNI


Migration Overview

The migration process utilizes the per-node configuration feature to selectively enable Cilium CNI. This allows for a controlled rollout of Cilium without disrupting existing workloads.

Cilium will be installed, first, in a mode where it establishes an overlay but does not provide CNI networking for any pods. Then, individual nodes will be migrated.

In summary, the process looks like:

    Prepare the cluster and install Cilium in “secondary” mode.
    Cordon, drain, migrate, and reboot each node
    Remove the existing network provider
    (Optional) Reboot each node again

In the next task, you will prepare the cluster and install Cilium in "secondary" mode.

For Kind clusters, the default is 10.244.0.0/16. So, for this example, we will use 10.245.0.0/16.

The second step is to select a different encapsulation protocol (Geneve instead of VXLAN for example) or a distinct encapsulation port.

For this example, we will use VXLAN with a non-default port of 8473 (the default is 8472).

Generate cilium values:
cilium install --helm-values values-migration.yaml --dry-run-helm-values >> values-initial.yaml

Install cilium using helm:
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium --namespace kube-system --values values-initial.yaml


The Cilium agent process supports setting configuration on a per-node basis instead of constant configuration across the cluster. This allows overriding the global Cilium config for a node or set of nodes. It is managed by CiliumNodeConfig objects. Note the Cilium CiliumNodeConfig CRD was added in Cilium 1.13.

A CiliumNodeConfig object consists of a set of fields and a label selector. The label selector defines to which nodes the configuration applies.

Let's now create a per-node config that will instruct Cilium to “take over” CNI networking on the node.

cat <<EOF | kubectl apply --server-side -f -
apiVersion: cilium.io/v2alpha1
kind: CiliumNodeConfig
metadata:
  namespace: kube-system
  name: cilium-default
spec:
  nodeSelector:
    matchLabels:
      io.cilium.migration/cilium-default: "true"
  defaults:
    write-cni-conf-when-ready: /host/etc/cni/net.d/05-cilium.conflist
    custom-cni-conf: "false"
    cni-chaining-mode: "none"
    cni-exclusive: "true"
EOF

kubectl -n kube-system get ciliumnodeconfigs.cilium.io cilium-default -o yaml
 CiliumNodeConfig only applies to nodes with the io.cilium.migration/cilium-default: "true" label. We will gradually migrate nodes by applying the label to each node, one by one.

Once the node is reloaded, the custom Cilium configuration will be applied, the CNI configuration will be written and the CNI functionality will be enabled.

Migration

We are now ready to begin the migration process. We will do it a node at a time.

We will cordon, drain, migrate, and reboot each node.


Cordon a node will prevent new pods from being scheduled on the node.
NODE="kind-worker"
kubectl cordon $NODE
kubectl scale deployment nginx-deployment --replicas=12

Drain a node will gracefully evict all the running pods from the node. 
This ensures that the pods are not abruptly terminated and that their workload is gracefully handled by other available nodes.
kubectl drain $NODE --ignore-daemonsets
kubectl get pods -o wide

We can now label the node: this causes the CiliumNodeConfig to apply to this node:
kubectl label node $NODE --overwrite "io.cilium.migration/cilium-default=true"

Let's restart Cilium on the node. That will trigger the creation of CNI configuration file.
kubectl -n kube-system delete pod --field-selector spec.nodeName=$NODE -l k8s-app=cilium
kubectl -n kube-system rollout status ds/cilium -w

Restart docker node:
docker restart $NODE

Check cilium status:
cilium status --wait

We are going to deploy a pod shortly. We will verify that Cilium attributes the IP to the pod.

Remember that we rolled out Cilium in cluster-scope IPAM mode where Cilium assigns per-node PodCIDRs to each node and allocates IPs using a host-scope allocator on each node. The Cilium operator will manage the per-node PodCIDRs via the CiliumNode resource.

The following command will check the CiliumNode resource and will show us the Pod CIDRs used to allocate IP addresses to the pods:
kubectl get cn kind-worker -o jsonpath='{.spec.ipam.podCIDRs[0]}'

Let's verify that, when we deploy a pod on the migrated node, that the pod picks an IP from the Cilium CIDR. The command below deploys a temporary pod on the node and outputs the pod's IP details (filtering on the Cilium Pod CIDR 10.245). Note we use the toleration to override the cordon.
kubectl run --attach --rm --restart=Never verify  --overrides='{"spec": {"nodeName": "'$NODE'", "tolerations": [{"operator": "Exists"}]}}'   --image alpine -- /bin/sh -c 'ip addr' | grep 10.245 -B 2

Test connectivity between pods on the existing overlay and the new Cilium-overlay. Let's first get the IP of one of the NGINX pod that was initially deployed. This pod should still be on the legacy CNI network.
NGINX=($(kubectl get pods -l app=nginx -o=jsonpath='{.items[0].status.podIP}'))
echo $NGINX

kubectl run --attach --rm --restart=Never verify  --overrides='{"spec": {"nodeName": "'$NODE'", "tolerations": [{"operator": "Exists"}]}}'   --image alpine/curl --env NGINX=$NGINX -- /bin/sh -c 'curl -s $NGINX '

kubectl uncordon $NODE

Repeat worker2
NODE="kind-worker2"
kubectl cordon $NODE

kubectl drain $NODE --ignore-daemonsets
kubectl label node $NODE --overwrite "io.cilium.migration/cilium-default=true"

Restart cilium daemonset
kubectl -n kube-system delete pod --field-selector spec.nodeName=$NODE -l k8s-app=cilium
kubectl -n kube-system rollout status ds/cilium -w
docker restart $NODE
kubectl uncordon $NODE

Repeat control plane
NODE="kind-control-plane"
kubectl cordon $NODE
kubectl drain $NODE --ignore-daemonsets
kubectl get pods -o wide
kubectl label node $NODE --overwrite "io.cilium.migration/cilium-default=true"

kubectl -n kube-system delete pod --field-selector spec.nodeName=$NODE -l k8s-app=cilium
kubectl -n kube-system rollout status ds/cilium -w
docker restart $NODE
kubectl uncordon $NODE
cilium status --wait

Now that Cilium is healthy, let's update the Cilium configuration. First, let's create the right configuration file.
cilium install --helm-values values-initial.yaml --helm-set operator.unmanagedPodWatcher.restart=true --helm-set cni.customConf=false --helm-set policyEnforcementMode=default --dry-run-helm-values >> values-final.yaml

diff values-initial.yaml values-final.yaml

We are:

    Enabling Cilium to write the CNI configuration file.
    Enabling Cilium to restart unmanaged pods.
    Enabling Network Policy Enforcement.

helm upgrade --namespace kube-system cilium cilium/cilium --values values-final.yaml
kubectl -n kube-system rollout restart daemonset cilium
cilium status --wait

Delete flannel CNI
kubectl delete -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
