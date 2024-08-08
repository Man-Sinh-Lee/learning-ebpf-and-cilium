Multicast Support

Multicast support in Kubernetes has finally come to Cilium!

In this lab, you will discover how to set it up, take advantage of it, and observe multicast traffic in Kubernetes, using Cilium and Tetragon in Isovalent Enterprise.

Multicast Support

Multicast support in Kubernetes has finally come to Cilium!

In this lab, you will discover how to set it up, take advantage of it, and observe multicast traffic in Kubernetes, using Cilium and Tetragon in Isovalent Enterprise.

In the networking section of the Kind configuration file, the default CNI has been disabled so the cluster won't have any Pod network when it starts. Instead, Cilium was deployed to the cluster to provide this functionality.

To see if the Kind cluster is ready, verify that the cluster is properly running by listing its nodes:

root@server:~# kubectl get nodes
NAME                 STATUS   ROLES           AGE   VERSION
kind-control-plane   Ready    control-plane   37m   v1.29.2
kind-worker          Ready    <none>          36m   v1.29.2
kind-worker2         Ready    <none>          36m   v1.29.2

root@server:~# cilium status --wait
    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    disabled (using embedded mode)
 \__/¯¯\__/    Hubble Relay:       OK
    \__/       ClusterMesh:        disabled

Deployment             hubble-ui          Desired: 1, Ready: 1/1, Available: 1/1
Deployment             cilium-operator    Desired: 2, Ready: 2/2, Available: 2/2
Deployment             hubble-relay       Desired: 1, Ready: 1/1, Available: 1/1
DaemonSet              cilium             Desired: 3, Ready: 3/3, Available: 3/3
Containers:            cilium             Running: 3
                       hubble-ui          Running: 1
                       cilium-operator    Running: 2
                       hubble-relay       Running: 1
Cluster Pods:          11/11 managed by Cilium
Helm chart version:    
Image versions         cilium             quay.io/isovalent/cilium:v1.15.7-cee.1: 3
                       hubble-ui          quay.io/isovalent/hubble-ui-enterprise:v1.0.3: 1
                       hubble-ui          quay.io/isovalent/hubble-ui-enterprise-backend:v1.0.3: 1
                       cilium-operator    quay.io/isovalent/operator-generic:v1.15.7-cee.1: 2
                       hubble-relay       quay.io/isovalent/hubble-relay:v1.15.7-cee.1: 

Now let's enable the Multicast feature:
root@server:~# cilium config set multicast-enabled true
root@server:~# cilium config view | grep multicast-enabled
multicast-enabled                                    true

Now that we have a working Kubernetes cluster with Isovalent Enterprise for Cilium installed, configured with the multicast feature, let's prepare our multicast setup in the next challenge.


The Scenario

In the following challenges, we will be replaying the Battle of the Yavin, where the Death Star was destroyed by the Rebel Alliance by dropping a bomb in an exhaust port. Multicast will be used for communications between fighters on both sides of the battle.

Multicast Groups

In order to use multicast in Cilium, we first need to setup multicast groups. Isovalent Enterprise provides a CRD for this, called IsovalentMulticastGroup.

Let's start by making Cilium aware of the multicast groups we want to use.

root@server:~# yq multicast-groups.yaml
apiVersion: isovalent.com/v1alpha1
kind: IsovalentMulticastGroup
metadata:
  name: empire
  namespace: default
spec:
  groupAddrs:
    - "225.0.0.10"
    - "225.0.0.11"
    - "225.0.0.12"
---
apiVersion: isovalent.com/v1alpha1
kind: IsovalentMulticastGroup
metadata:
  name: alliance
  namespace: default
spec:
  groupAddrs:
    - "225.0.0.20"
    - "225.0.0.21"
    - "225.0.0.22"
---
apiVersion: isovalent.com/v1alpha1
kind: IsovalentMulticastGroup
metadata:
  name: the-force
  namespace: default
spec:
  groupAddrs:
    - "225.0.0.42"

This configuration file defines 3 multicast groups:

    the empire group uses addresses 225.0.0.10 through 12
    the alliance group uses addresses 225.0.0.20 through 22
    the-force group only uses the 225.0.0.42 address

Apply the manifest:
kubectl apply -f multicast-groups.yaml

Verify the groups in Cilium, using any of the Cilium agent pods:
root@server:~# kubectl exec daemonsets/cilium -n kube-system -c cilium-agent -- \
  cilium bpf multicast group list

This will list all groups created by the manifest, and shows that Cilium is ready to route multicast traffic on these IP addresses:
Group Address
225.0.0.10
225.0.0.11
225.0.0.12
225.0.0.20
225.0.0.21
225.0.0.22
225.0.0.42

Now list the subscribers with:
root@server:~# kubectl exec daemonsets/cilium -n kube-system -c cilium-agent -- \
  cilium bpf multicast subscriber list all

There are currently no subscribers on these addresses:
Group           Subscriber      Type            
225.0.0.10      
225.0.0.11      
225.0.0.12      
225.0.0.20      
225.0.0.21      
225.0.0.22      
225.0.0.42    


Let's create a pod to subscribe to one of the multicast channels. We will use the socat command to make the pod listen to multicast traffic on 225.0.0.11.

In the >_ Terminal 2:
root@server:~# kubectl run -ti --rm sub --image nicolaka/netshoot -- \
  socat UDP4-RECVFROM:6666,reuseaddr,ip-add-membership=225.0.0.11:0.0.0.0,fork -

Switch to the >_ Terminal 1 tab and check that the pod is running (run the command until the pod is running):
root@server:~# kubectl get po sub -o wide
NAME   READY   STATUS    RESTARTS   AGE   IP          NODE           NOMINATED NODE   READINESS GATES
sub    1/1     Running   0          16s   10.0.1.25   kind-worker2   <none>           <none>

Note the node name and the IP address of the pod.

Now let's check the subscriber list on the Cilium agent that hosts this pod.

First, get the name of the node where the pod was scheduled:
root@server:~# NODE=$(kubectl get po sub -o jsonpath='{.spec.nodeName}')
echo $NODE
kind-worker2

Next, get the name of the Cilium agent pod running on that node:
root@server:~# CILIUM_POD=$(kubectl -n kube-system get po -l k8s-app=cilium --field-selector spec.nodeName=$NODE -o name)
echo $CILIUM_POD
pod/cilium-zp4f8

Finally, check the subscriber list in Cilium agent pod:
root@server:~# kubectl exec $CILIUM_POD -n kube-system -c cilium-agent -- \
  cilium bpf multicast subscriber list all
Group           Subscriber      Type            
225.0.0.10      
225.0.0.11      10.0.1.25       Local Endpoint  
225.0.0.12      
225.0.0.20      
225.0.0.21      
225.0.0.22      
225.0.0.42    
You will see one subscriber listed for the 225.0.0.11 address.

Since you launched this command on the Cilium agent running on the node where the pod is running, you will see the pod's own IP address (in the 10.0.0.0/8 range) listed. The IP address is also marked as a Local Endpoint.

Let's check on a different Cilium agent.
root@server:~# OTHER_CILIUM_POD=$(kubectl -n kube-system get po -l k8s-app=cilium -o json | jq -r ".items[] | select(.spec.nodeName!=\"$NODE\").metadata.name" | head -n1)
echo $OTHER_CILIUM_POD
cilium-6nvq4
root@server:~# kubectl exec $OTHER_CILIUM_POD -n kube-system -c cilium-agent -- \
  cilium bpf multicast subscriber list all
Group           Subscriber      Type            
225.0.0.10      
225.0.0.11      172.18.0.3      Remote Node     
225.0.0.12      
225.0.0.20      
225.0.0.21      
225.0.0.22      
225.0.0.42      

You will see the subscriber listed with its node IP address (in the 172.18.0.0/24 range) this time, since this Cilium agent is running on a different node than the pod's node. The IP address is also marked as a Remote Node.

In the next challenge, we will start sending messages to subscribers using multicast!

Let's deploy the Rebel Base and the Death Star:
kubectl apply -f bases.yaml

They will be used to send messages to various ships:

    the Rebel Base will send to the Alliance ships, using the 225.0.0.21 multicast address on port 8888
    the Death Star will send to Darth Vader, using the 225.0.0.11 multicast address on port 6666

Wait until the bases are deployed:
kubectl rollout status -f bases.yaml

Now let's deploy ships on both sides:

    red-leader (X-Wing, Alliance)
    millenium-falcon (YT-1300F, Alliance)
    luke (X-Wing, Alliance)
    obi-wan (Ghost, Alliance)
    darth-vader (Tie Fighter, Empire)

root@server:~# kubectl apply -f ships.yaml
pod/red-leader created
pod/millenium-falcon created
pod/luke created
pod/darth-vader created
pod/obi-wan created
root@server:~# kubectl get -f ships.yaml -o wide --show-labels
NAME               READY   STATUS    RESTARTS   AGE   IP           NODE           NOMINATED NODE   READINESS GATES   LABELS
red-leader         1/1     Running   0          15s   10.0.1.208   kind-worker2   <none>           <none>            class=x-wing,org=alliance
millenium-falcon   1/1     Running   0          15s   10.0.1.77    kind-worker2   <none>           <none>            class=yt-1300f,org=alliance
luke               1/1     Running   0          15s   10.0.1.200   kind-worker2   <none>           <none>            class=x-wing,org=alliance
darth-vader        1/1     Running   0          15s   10.0.1.11    kind-worker2   <none>           <none>            class=tiefighter,org=empire
obi-wan            1/1     Running   0          15s   10.0.2.216   kind-worker    <none>           <none>            class=ghost,org=alliance

In order to watch communications, we'll split the screen in 4 using Tmux. The scenario.sh script does just that:
./scenario.sh

This will use the tmux utility to split the screen into 4 panes. In each pane, a ship will be listening to a multicast stream.

Notice the commands launched for each of the ships:

    red-leader is listening on 225.0.0.21:8888
    millenium-falcon is listening on 225.0.0.22:8888
    luke is listening on both 225.0.0.23:8888 and 225.0.0.42:7777
    darth-vader is listening on 225.0.0.11:6666

In the >_ Terminal 2 tab, verify the subscriptions.

Let's check all Cilium agents so we better understand the topology:
root@server:~# for pod in $(kubectl -n kube-system get po -l k8s-app=cilium -o name); do
  echo "== $pod =="
  kubectl -n kube-system exec -ti $pod -c cilium-agent -- \
    cilium bpf multicast subscriber list all
done
== pod/cilium-6nvq4 ==
Group           Subscriber      Type            
225.0.0.10      
225.0.0.11      172.18.0.3      Remote Node     
225.0.0.12      
225.0.0.20      
225.0.0.21      172.18.0.3      Remote Node     
225.0.0.22      
225.0.0.42      172.18.0.3      Remote Node     
== pod/cilium-bpfjl ==
Group           Subscriber      Type            
225.0.0.10      
225.0.0.11      172.18.0.3      Remote Node     
225.0.0.12      
225.0.0.20      
225.0.0.21      172.18.0.3      Remote Node     
225.0.0.22      
225.0.0.42      172.18.0.3      Remote Node     
== pod/cilium-zp4f8 ==
Group           Subscriber      Type            
225.0.0.10      
225.0.0.11      10.0.1.11       Local Endpoint  
225.0.0.12      
225.0.0.20      
225.0.0.21      10.0.1.77       Local Endpoint  
                10.0.1.200      Local Endpoint  
                10.0.1.208      Local Endpoint  
225.0.0.22      
225.0.0.42      10.0.1.200      Local Endpoint  

This will show:

    1 subscriber on 225.0.0.11 (Darth Vader)
    3 subscribers on 225.0.0.21 (the 3 X-Wings)
    1 subscriber on 225.0.0.42 (Luke)

Depending on which Cilium agent you are checking, the pods will be marked as either Local Endpoints or Remote Nodes.
Now, play the messages with:
root@server:~# ./messages.sh
Sending msg to 225.0.0.11:6666 from deploy/deathstar: 🌐 Rebel base, thirty seconds and closing.
Sending msg to 225.0.0.11:6666 from darth-vader: ⬛ I'm on the leader.
Sending msg to 225.0.0.42:7777 from obi-wan: 👻 Use the force, Luke.
Sending msg to 225.0.0.42:7777 from obi-wan: 👻 Let go, Luke.
Sending msg to 225.0.0.11:6666 from darth-vader: ⬛ The force is strong with this one.
Sending msg to 225.0.0.42:7777 from obi-wan: 👻 Luke, trust me.
Sending msg to 225.0.0.21:8888 from deploy/rebel-base: 👹 His computer's off. Luke, you switched off your targeting computer. What's wrong?
Sending msg to 225.0.0.21:8888 from luke: 🧑 Nothing. I'm all right.
Sending msg to 225.0.0.21:8888 from luke: 🧑 I've lost Artoo!
Sending msg to 225.0.0.21:8888 from deploy/rebel-base: 👹 The Death Star has cleared the planet. The Death Star has cleared the planet.
Sending msg to 225.0.0.11:6666 from deploy/deathstar: 🌐 Rebel base, in range.
Sending msg to 225.0.0.11:6666 from deploy/deathstar: 🌐 You may fire when ready.
Sending msg to 225.0.0.11:6666 from deploy/deathstar: 🌐 Commence primary ignition.
Sending msg to 225.0.0.11:6666 from darth-vader: ⬛ I have you now.
Sending msg to 225.0.0.11:6666 from darth-vader: ⬛ What?
Sending msg to 225.0.0.21:8888 from millenium-falcon: 🦅 Yahoo!
Sending msg to 225.0.0.21:8888 from millenium-falcon: 🦅 You're all clear, kid.
Sending msg to 225.0.0.21:8888 from millenium-falcon: 🦅 Now let's blow this thing and go home!
Sending msg to 225.0.0.11:6666 from deploy/deathstar: 🌐 Stand by to fire at Rebel base.
Sending msg to 225.0.0.11:6666 from deploy/deathstar: 🌐 Standing by.
Sending msg to 225.0.0.11:6666 from deploy/deathstar: 💥 THE DEATH STAR EXPLODES
Sending msg to 225.0.0.21:8888 from millenium-falcon: 🦅 Great shot, kid. That was one in a million.
Sending msg to 225.0.0.42:7777 from obi-wan: 👻 Remember, the Force will be with you... always.
deployment.apps/deathstar scaled

and switch back to the >_ Terminal 1 tab to observe the traffic. Messages will start appearing after 5 seconds.

After you see the Death Star explode, verify that it is gone in >_ Terminal 2:
root@server:~# kubectl get pods
NAME                         READY   STATUS    RESTARTS   AGE
darth-vader                  1/1     Running   0          6m46s
luke                         1/1     Running   0          6m46s
millenium-falcon             1/1     Running   0          6m46s
obi-wan                      1/1     Running   0          6m46s
rebel-base-7d9dd5446-7rqcl   1/1     Running   0          10m
red-leader                   1/1     Running   0          6m46s


Observing Multicast

In Isovalent Enterprise for Cilium, you can use Tetragon to observe multicast traffic.

Tetragon will provide Prometheus metrics for UDP and Multicast streams.

In this challenge, you will see how to take advantage of these metrics using Grafana dashboards.


Two Tetragon TracingPolicy manifests were applied before playing the Battle of Yavin scenario.

Let's review the first one:
root@server:~# yq tracingpol_interface.yaml
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata:
  name: interface-parser
spec:
  parser:
    interface:
      enable: true
      packet: true


It allows Tetragon to create metrics based on network interface events.

The second one makes Tetragon aware of UDP traffic, in particular multicast:
root@server:~# yq tracingpol_udp.yaml
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata:
  name: udp-parser
spec:
  parser:
    udp:
      #  burst:
      #    enable: true
      #    triggerPercent: 50
      #    windowSize: 1000
      cgroup: true
      enable: true
      statsInterval: 20

Grafana has been deployed in this lab environment.

Navigate to the 🔗 📈 Grafana UDP tab. This shows UDP metrics recorded by Tetragon.

In the pod selector, choose darth-vader to only show traffic relating to this pod. Play around with other pods to compare UDP traffic.
While this is generally useful, it doesn't tell us much about the specific multicast traffic we witnessed in the previous challenge.

Move to the 🔗 📈 Grafana - Multicast tab. You will see graphs representing multicast traffic per source and destination.

In the dstmcast menu, select 225.0.0.42, which is an IP associated with the Force.

You can see that only obi-wan transmitted to this IP, and only luke listened on it, which reflects the communication we saw during the battle.


Similarly, select 225.0.0.11 as the dstmcast value to observe the Empire's communication, and see who transmitted and who received the messages.

The next challenge will be a quiz on multicast with Cilium.

Multicast is a feature specific to Isovalent Enterprise
Tetragon can provide UDP metrics
Tetragon can provide multicast metrics
Multicast groups need to be created in Kubernetes for pods to use multica

In this exam, you will need to deploy a new multicast group for the 225.0.0.50 IP address (choose a name you like).

Then, start a multicast listener on that IP address, on port 1234 so you're ready to receive a message on that channel.

Once you have done so, press the Check button a first time. This will deliver a message on 225.0.0.50:1234, which you will see appear in your listener.

Finally, using the </> Editor tab, fill in the answers.yaml file with the required information:

    the content of the secret message
    the sender of the message

    ⓘ Notes:

        You have access to the Editor.
        All files and resources used earlier in the lab are still available. Don't hesitate to check them!
        You can also use the history command to check the commands you run previously.
        Use the Grafana dashboards to find out the required information.
        You will need to refresh the Grafana Multicast window to be able to see the new traffic.
        Kubernetes secrets are encoded in base64. You can use the base64 -d command to decode them.
        You can use socat in a Pod to subscribe to a multicast channel, e.g.:

    shell

socat UDP4-RECVFROM:6666,reuseaddr,ip-add-membership=225.0.0.11:0.0.0.0 -
