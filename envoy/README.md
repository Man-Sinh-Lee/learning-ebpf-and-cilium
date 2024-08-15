The Envoy L7 Proxy

Envoy is a powerful and flexible layer 7 open-source proxy.

It is a graduated CNCF project and is used in variety of service mesh solutions. In particular, Envoy powers the Istio Service Mesh.

Embedded Envoy Proxy

Cilium already uses Envoy for L7 policy and observability for some protocols, and this same component is used as the sidecar proxy in many popular Service Mesh implementations.

The Cilium Service Mesh also leverages Envoy, in a sidecar-less configuration.

A Separate DaemonSet for Envoy

In Cilium 1.14, we are introducing support for Envoy as a DaemonSet. This provides a number of potential benefits, such as:

    Cilium Agent restarts (for example, for upgrades) do not impact the live traffic proxied via Envoy.
    Envoy patch release upgrades do not impact the Cilium Agent.
    Reduced blast radius in the (unlikely) event of a compromise
    Envoy application log isn’t mixed with the log of the Cilium Agent.
    Dedicated health probes for the Envoy proxy.


Observing HTTP Traffic

A great benefit of using L7 Cilium Network Policies is the gain in observability.


Advanced Envoy Use Cases

Cilium uses Envoy for multiple functionalities, and a good number has been added for Ingress and Gateway API support (see the Ingress Controller and Gateway API labs).

However, Envoy is a very feature-rich software, and while Cilium provides several abstractions for Envoy configurations, it only covers some of the conceivable scenarios.

For this reason, Cilium provides a Cilium Envoy Config CRDs, which lets users configure Envoy themselves to implement the features they want.

Let's have a look at our lab environment and see if Cilium has been installed correctly. The following command will wait for Cilium to be up and running and report its status:

helm upgrade --install cilium cilium/cilium -n kube-system --set kubeProxyReplacement=true --set loadBalancer.l7.backend=envoy --set-string extraConfig.

KubeProxyReplacement (KPR) is a requirement for some of the features in this lab.

Verify that Cilium was enabled and deployed with KPR:

root@server:~# cilium config view | grep -w "kube-proxy"
kube-proxy-replacement                            true
kube-proxy-replacement-healthz-bind-address       
root@server:~# cilium status --wait

 Securing Traffic at L7

Standard Kubernetes Network Policies allow to filter traffic at layer 3 and layer 4:

    Layer 3 allows identities (typically IP addresses) to communicate regardless of the ports they use and the content they exchange.
    Layer 4 adds filtering on port (e.g. TCP/80) but still doesn't filter the content.

Cilium leverages the Envoy L7 proxy to allow filtering traffic at layer 7. This means you can filter the type of information applications are sharing, such as the HTTP path, headers, etc.

Star Wars Demo
To learn how to use and enforce policies with Cilium, we have prepared a demo example.
In the following Star Wars-inspired example, there are three microservice applications: deathstar, tiefighter, and xwing.

The deathstar service
The deathstar runs an HTTP webservice on port 80, which is exposed as a Kubernetes Service to load-balance requests to deathstar across two pod replicas.
The deathstar service provides landing services to the empire’s spaceships so that they can request a landing port.

Allowing ship access
The tiefighter pod represents a landing-request client service on a typical empire ship and xwing represents a similar service on an alliance ship.
With this setup, we can test different security policies for access control to deathstar landing services.
root@server:~# yq sw-pods.yaml 
root@server:~# kubectl apply -f sw-pods.yaml
service/deathstar created
deployment.apps/deathstar created
pod/tiefighter created
pod/xwing created
root@server:~# kubectl rollout status deployment/deathstar
deployment "deathstar" successfully rolled out
root@server:~# kubectl get all
NAME                            READY   STATUS    RESTARTS   AGE
pod/deathstar-b4b8ccfb5-lvbnx   1/1     Running   0          21s
pod/deathstar-b4b8ccfb5-wc4vr   1/1     Running   0          21s
pod/tiefighter                  1/1     Running   0          21s
pod/xwing                       1/1     Running   0          21s

NAME                 TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/deathstar    ClusterIP   10.96.246.139   <none>        80/TCP    21s
service/kubernetes   ClusterIP   10.96.0.1       <none>        443/TCP   73m

NAME                        READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/deathstar   2/2     2            2           21s

NAME                                  DESIRED   CURRENT   READY   AGE
replicaset.apps/deathstar-b4b8ccfb5   2         2         2       21s

Then test access to the Death Star from the X-Wing pod:
root@server:~# kubectl get pod xwing
NAME    READY   STATUS    RESTARTS   AGE
xwing   1/1     Running   0          45s
root@server:~# kubectl exec xwing -- \
  curl --max-time 1 -s -X POST deathstar.default.svc.cluster.local/v1/request-landing
Ship landed
The Death Star service will respond with Ship landed.
Using the Hubble CLI, check the traffic that results from this request:
root@server:~# hubble observe --to-pod default/deathstar
Aug 12 06:08:59.855: default/xwing (ID:10135) <> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) post-xlate-fwd TRANSLATED (TCP)
Aug 12 06:08:59.855: default/xwing:43966 (ID:10135) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-overlay FORWARDED (TCP Flags: SYN)
Aug 12 06:08:59.855: default/xwing:43966 (ID:10135) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-endpoint FORWARDED (TCP Flags: SYN)
Aug 12 06:08:59.855: default/xwing:43966 (ID:10135) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-overlay FORWARDED (TCP Flags: ACK)
Aug 12 06:08:59.855: default/xwing:43966 (ID:10135) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-endpoint FORWARDED (TCP Flags: ACK)
Aug 12 06:08:59.855: default/xwing:43966 (ID:10135) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-overlay FORWARDED (TCP Flags: ACK, PSH)
Aug 12 06:08:59.855: default/xwing:43966 (ID:10135) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-endpoint FORWARDED (TCP Flags: ACK, PSH)
Aug 12 06:08:59.855: default/xwing:43966 (ID:10135) <> default/deathstar-b4b8ccfb5-wc4vr (ID:58295) pre-xlate-rev TRACED (TCP)
Aug 12 06:08:59.856: default/xwing:43966 (ID:10135) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-overlay FORWARDED (TCP Flags: ACK, FIN)
Aug 12 06:08:59.856: default/xwing:43966 (ID:10135) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-endpoint FORWARDED (TCP Flags: ACK, FIN)
Aug 12 06:08:59.856: default/xwing:43966 (ID:10135) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-overlay FORWARDED (TCP Flags: ACK)
Aug 12 06:08:59.856: default/xwing:43966 (ID:10135) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-endpoint FORWARDED (TCP Flags: ACK)

You can also check this in the 🔗 Hubble UI tab, by selecting the default namespace
The X-Wing has access to the Death Star, which is problematic for the Death Star security team: You wouldn't want the Rebels to get too close to the Death Star, they might blow it up!

In order to fix this, deploy a L3/L4 Network Policy to protect the Death Star by only allowing vessels labeled with org=empire to access it (which is not the case of the xwing pod).
root@server:~# kubectl apply -f l4-policy.yaml
ciliumnetworkpolicy.cilium.io/rule1 created
root@server:~# kubectl get ciliumnetworkpolicy rule1 -o yaml | yq .spec
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

The endpointSelector field show that the network policy allows ingress traffic to pods labeled org=empire and class=deathstar, which matches the Death Star pods:

    from pods labeled org=empire (fromEndpoints.matchLabels field) for L3 filtering
    to port 80/TCP (toPorts field) for L4 filtering

This level of security is ensured by eBPF, directly in the kernel. This means even when the Cilium agent is not running, these rules are guaranteed to be applied (but not necessarily kept up-to-date).

Try again to access the Death Star from the X-Wing pod:
root@server:~# kubectl exec xwing -- \
  curl --max-time 1 -s -X POST deathstar.default.svc.cluster.local/v1/request-landing
command terminated with exit code 28
root@server:~# hubble observe --to-pod default/deathstar
Aug 12 06:15:36.447: default/xwing (ID:10135) <> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) post-xlate-fwd TRANSLATED (TCP)
Aug 12 06:15:36.447: default/xwing:49694 (ID:10135) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-overlay FORWARDED (TCP Flags: SYN)
Aug 12 06:15:36.447: default/xwing:49694 (ID:10135) <> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) policy-verdict:none INGRESS DENIED (TCP Flags: SYN)
Aug 12 06:15:36.447: default/xwing:49694 (ID:10135) <> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) Policy denied DROPPED (TCP Flags: SYN)

The requests are now blocked by the L4 Network Policy, and the packets are dropped directly by the kernel, causing a timeout.

It is however still possible to access from the Tie Fighter pod, since it is labeled as org=empire:

root@server:~# kubectl exec tiefighter -- \
  curl --max-time 1 -s -X POST deathstar.default.svc.cluster.local/v1/request-landing
Ship landed

Hubble sees the traffic from the X-Wing pod dropped, and forwarded from the Tie Fighter. It still indicates that the traffic is going to-endpoint:
root@server:~# hubble observe --to-pod default/deathstar
Aug 12 06:17:23.977: default/tiefighter (ID:1623) <> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) post-xlate-fwd TRANSLATED (TCP)
Aug 12 06:17:23.977: default/tiefighter:48018 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-overlay FORWARDED (TCP Flags: SYN)
Aug 12 06:17:23.977: default/tiefighter:48018 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) policy-verdict:L3-L4 INGRESS ALLOWED (TCP Flags: SYN)
Aug 12 06:17:23.977: default/tiefighter:48018 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-endpoint FORWARDED (TCP Flags: SYN)
Aug 12 06:17:23.977: default/tiefighter:48018 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-overlay FORWARDED (TCP Flags: ACK)
Aug 12 06:17:23.977: default/tiefighter:48018 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-endpoint FORWARDED (TCP Flags: ACK)
Aug 12 06:17:23.977: default/tiefighter:48018 (ID:1623) <> default/deathstar-b4b8ccfb5-wc4vr (ID:58295) pre-xlate-rev TRACED (TCP)
Aug 12 06:17:23.977: default/tiefighter:48018 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-endpoint FORWARDED (TCP Flags: ACK, PSH)
Aug 12 06:17:23.978: default/tiefighter:48018 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-overlay FORWARDED (TCP Flags: ACK, PSH)
Aug 12 06:17:23.978: default/tiefighter:48018 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-overlay FORWARDED (TCP Flags: ACK, FIN)
Aug 12 06:17:23.978: default/tiefighter:48018 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-endpoint FORWARDED (TCP Flags: ACK, FIN)
Aug 12 06:17:23.978: default/tiefighter:48018 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-endpoint FORWARDED (TCP Flags: ACK)
Aug 12 06:17:23.978: default/tiefighter:48018 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-overlay FORWARDED (TCP Flags: ACK)

You can also verify this in the 🔗 Hubble UI tab, where the link between the X-Wing and Death Star identities is now red (or possibly dotted if there is still some forwarded traffic is the Hubble logs buffer):


While the L4 Network Policy prevents Rebel ships from accessing the Death Star, it leaves complete access to Imperial ships.

What would happen if a Rebel managed to get access to an imperial ship. They could take advantage of their access rights to the Death Star to blow it up!

Let's try this from a Tie Fighter pod. In the >_ Terminal tab:

root@server:~# kubectl exec tiefighter -- \
  curl -s -X PUT deathstar.default.svc.cluster.local/v1/exhaust-port
Panic: deathstar exploded

goroutine 1 [running]:
main.HandleGarbage(0x2080c3f50, 0x2, 0x4, 0x425c0, 0x5, 0xa)
        /code/src/github.com/empire/deathstar/
        temp/main.go:9 +0x64
main.main()
        /code/src/github.com/empire/deathstar/
        temp/main.go:5 +0x85

The Death Star exploded!

We need a more fine-grained Network Policy, only allowing a POST request to /v1/request-landing and nothing else.

This can be achieved with L7 Network Policies, by leveraging Envoy integration in Cilium.

Let's modify the Network Policy to add a L7 rule:

root@server:~# kubectl apply -f l7-policy.yaml
ciliumnetworkpolicy.cilium.io/rule1 configured
root@server:~# kubectl get cnp rule1 -o yaml | yq .spec
description: L7 policy to restrict access to specific HTTP call
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
        rules:
          http:
            - method: POST
              path: /v1/request-landing

Compared with the previous version, a rules field was added to the L4 section of the policy:
rules:
  http:
  - method: "POST"
    path: "/v1/request-landing"                

It states that only HTTP traffic is allowed, and only if the request uses the POST method and targets the /v1/request-landing path.

Layer 7 network policies are implemented using Envoy as a L7 proxy. Cilium dynamically programs Envoy to apply these security rules.

If a network request matches the L3/L4 section of the policy, the eBPF programs in the kernel will allow it and send the traffic to the Envoy proxy, targetting a listener that is generated specifically for the L7 rule in the policy.

Envoy is then responsible for replying to the request.

Try again to explode the Death Star from the Tie Fighter pod:
root@server:~# kubectl exec tiefighter -- \
  curl -s -X PUT deathstar.default.svc.cluster.local/v1/exhaust-port
Access denied

You will see Access denied, which corresponds to a 403 response from Envoy.

root@server:~# hubble observe \
  --from-pod default/tiefighter \
  --to-pod default/deathstar
Aug 12 06:22:39.783: default/tiefighter (ID:1623) <> default/deathstar-b4b8ccfb5-lvbnx:80 (ID:58295) post-xlate-fwd TRANSLATED (TCP)
Aug 12 06:22:39.783: default/tiefighter:56152 (ID:1623) -> default/deathstar-b4b8ccfb5-lvbnx:80 (ID:58295) policy-verdict:L3-L4 INGRESS ALLOWED (TCP Flags: SYN)
Aug 12 06:22:39.783: default/tiefighter:56152 (ID:1623) -> default/deathstar-b4b8ccfb5-lvbnx:80 (ID:58295) to-proxy FORWARDED (TCP Flags: SYN)
Aug 12 06:22:39.783: default/tiefighter:56152 (ID:1623) -> default/deathstar-b4b8ccfb5-lvbnx:80 (ID:58295) to-proxy FORWARDED (TCP Flags: ACK)
Aug 12 06:22:39.784: default/tiefighter:56152 (ID:1623) -> default/deathstar-b4b8ccfb5-lvbnx:80 (ID:58295) to-proxy FORWARDED (TCP Flags: ACK, PSH)
Aug 12 06:22:39.784: default/tiefighter:56152 (ID:1623) -> default/deathstar-b4b8ccfb5-lvbnx:80 (ID:58295) to-proxy FORWARDED (TCP Flags: ACK, FIN)
Aug 12 06:22:39.785: default/tiefighter:56152 (ID:1623) -> default/deathstar-b4b8ccfb5-lvbnx:80 (ID:58295) http-request DROPPED (HTTP/1.1 PUT http://deathstar.default.svc.cluster.local/v1/exhaust-port)

Observe the various steps of the connection between the Tie Fighter and the Death Star:

    a policy-verdict:L3-L4 trace marked as INGRESS ALLOWED when the in-kernel eBPF program allows the connection based on the L3/L4 Network Policy rule
    to-proxy traces marked as FORWARDED, which correspond to the traffic sent to the Envoy proxy (with SYN, ACK, and ACK, PSH traces)
    an http-request trace marked as DROPPED when Envoy responds to the request with an Access denied response, with details of the HTTP request that was blocked.
    finally, another to-proxy trace for the ACK, FIN step terminating the TCP connection

Now verify that the policy still allows the Tie Fighter to land on the Death Star:
root@server:~# kubectl exec tiefighter -- \
  curl -s -X POST deathstar.default.svc.cluster.local/v1/request-landing
Ship landed
root@server:~# hubble observe \
  --from-pod default/tiefighter \
  --to-pod default/deathstar

Aug 12 06:24:47.872: default/tiefighter (ID:1623) <> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) post-xlate-fwd TRANSLATED (TCP)
Aug 12 06:24:47.872: default/tiefighter:51454 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-overlay FORWARDED (TCP Flags: SYN)
Aug 12 06:24:47.872: default/tiefighter:51454 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) policy-verdict:L3-L4 INGRESS ALLOWED (TCP Flags: SYN)
Aug 12 06:24:47.872: default/tiefighter:51454 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-overlay FORWARDED (TCP Flags: ACK)
Aug 12 06:24:47.872: default/tiefighter:51454 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-proxy FORWARDED (TCP Flags: SYN)
Aug 12 06:24:47.872: default/tiefighter:51454 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-proxy FORWARDED (TCP Flags: ACK)
Aug 12 06:24:47.872: default/tiefighter:51454 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-overlay FORWARDED (TCP Flags: ACK, PSH)
Aug 12 06:24:47.872: default/tiefighter:51454 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-proxy FORWARDED (TCP Flags: ACK, PSH)
Aug 12 06:24:47.873: default/tiefighter:51454 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) http-request FORWARDED (HTTP/1.1 POST http://deathstar.default.svc.cluster.local/v1/request-landing)
Aug 12 06:24:47.877: default/tiefighter:51454 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-overlay FORWARDED (TCP Flags: ACK, FIN)
Aug 12 06:24:47.877: default/tiefighter:51454 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-proxy FORWARDED (TCP Flags: ACK, FIN)
Aug 12 06:24:47.877: default/tiefighter:51454 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-overlay FORWARDED (TCP Flags: ACK)

Again, you can see:

    the policy-verdict:L3-L4 trace allowing traffic to be forwarded to Envoy
    the various to-proxy flows tracing the traffic to the Envoy proxy
    the http-request trace which validates the traffic to be forwarded this time

We can see that L7 network policies result in slightly different behavior than the L3/L4 policies:

    Traffic dropped by a L7 Network Policy return an authorization denied (403) code instead of dropping;
    If the agent is not running, the L7 rules won't be applied!

In the next challenge, we will see how to address this problem.

 Envoy as a process in the Cilium Agent

Up until Cilium 1.16, the Envoy process was started by default within each Cilium pod in a ad-hoc manner, whenever Cilium requires it (for example, if there are L7 Network Policies that need to be enforced for a workload on that node).

This means both the Cilium agent and the Envoy proxy not only shared the same lifecycle but also the same blast radius in the event of a compromise.

A Separate DaemonSet for Envoy

In Cilium 1.14, we have introduced support for Envoy as a DaemonSet. This provides a number of potential benefits, such as:

    Cilium Agent restarts (for example, for upgrades) do not impact the live traffic proxied via Envoy.
    Envoy patch release upgrades do not impact the Cilium Agent.
    Reduced blast radius in the (unlikely) event of a compromise
    Envoy application log isn’t mixed with the log of the Cilium Agent.
    Dedicated health probes for the Envoy proxy.

The Future

Starting with Cilium 1.16, the DaemonSet option has now become the default configuration to deploy Envoy on nodes.

In >_ Terminal 1, check Cilium status:
root@server:~# cilium status
    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    OK
 \__/¯¯\__/    Hubble Relay:       OK

The status should indicate "Envoy DaemonSet: OK".

In >_ Terminal 1, make the Tie Fighter request landing in a loop:
root@server:~# while [ 1 ]; do
  kubectl exec tiefighter -- \
    curl -s --max-time 1 -X POST deathstar.default.svc.cluster.local/v1/request-landing
  sleep 1
done
Ship landed
Ship landed
Ship landed
Ship landed

In >_ Terminal 2, check a Cilium pod:
root@server:~# NODE=$(kubectl get po -l class=deathstar -o jsonpath='{.items[].spec.nodeName}')
echo $NODE
CILIUM=$(kubectl -n kube-system get po -l k8s-app=cilium --field-selector spec.nodeName=$NODE -o name)
kubectl -n kube-system exec $CILIUM -c cilium-agent -- \
  ps axu | grep envoy
kind-worker

There's no Envoy process running in the Cilium pod. Instead, there is a dedicated DaemonSet which deployed one Envoy pod per node:
root@server:~# kubectl -n kube-system get po \
  -l k8s-app=cilium-envoy
NAME                 READY   STATUS    RESTARTS   AGE
cilium-envoy-2d7jl   1/1     Running   0          26m
cilium-envoy-pzc9w   1/1     Running   0          26m
cilium-envoy-tg8sf   1/1     Running   0          26m

This allows Envoy workers to be managed separately from the Cilium agents. In particular, it means operators can now tune resources for both Cilium and Envoy separately, as the pod privileges are also better tuned.

Besides that, the Envoy logs are now accessible in the Envoy pods directly instead of the Cilium pods:
root@server:~# kubectl -n kube-system logs daemonsets/cilium-envoy
Found 3 pods, using pod/cilium-envoy-2d7jl
[2024-08-12 06:04:02.475][13][info][main] [external/envoy/source/server/server.cc:430] initializing epoch 0 (base id=0, hot restart version=11.104)
[2024-08-12 06:04:02.475][13][info][main] [external/envoy/source/server/server.cc:432] statically linked extensions:
[2024-08-12 06:04:02.475][13][info][main] [external/envoy/source/server/server.cc:434]   envoy.access_loggers: envoy.access_loggers.file, envoy.access_loggers.http_grpc, envoy.access_loggers.open_telemetry, envoy.access_loggers.stderr, envoy.access_loggers.stdout, envoy.access_loggers.tcp_grpc, envoy.access_loggers.wasm, envoy.file_access_log, envoy.http_grpc_access_log, envoy.open_telemetry_access_log, envoy.stderr_access_log, envoy.stdout_access_log, envoy.tcp_grpc_access_log, envoy.wasm_access_log

Observing HTTP Traffic

A great benefit of using L7 Cilium Network Policies is the gain in observability.

In this challenge, we will explore how Envoy enabled Cilium to provide L7 visibility such as HTTP method, path, or even headers passed between pods in a Kubernetes cluster, without the need to instrument the workloads or deploy an additional Service Mesh solution.

Using Hubble, check the traffic that is routed through the Envoy proxy:
root@server:~# hubble observe --type trace:to-proxy
Aug 12 06:34:18.213: default/tiefighter:51396 (ID:1623) -> default/deathstar-b4b8ccfb5-lvbnx:80 (ID:58295) to-proxy FORWARDED (TCP Flags: SYN)
Aug 12 06:34:18.213: default/tiefighter:51396 (ID:1623) -> default/deathstar-b4b8ccfb5-lvbnx:80 (ID:58295) to-proxy FORWARDED (TCP Flags: ACK)
Aug 12 06:34:18.213: default/tiefighter:51396 (ID:1623) -> default/deathstar-b4b8ccfb5-lvbnx:80 (ID:58295) to-proxy FORWARDED (TCP Flags: ACK, PSH)
Aug 12 06:34:18.214: default/tiefighter:51396 (ID:1623) -> default/deathstar-b4b8ccfb5-lvbnx:80 (ID:58295) to-proxy FORWARDED (TCP Flags: ACK, FIN)
Aug 12 06:34:20.427: default/tiefighter:53184 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-proxy FORWARDED (TCP Flags: SYN)
Aug 12 06:34:20.427: default/tiefighter:53184 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-proxy FORWARDED (TCP Flags: ACK)
Aug 12 06:34:20.427: default/tiefighter:53184 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-proxy FORWARDED (TCP Flags: ACK, PSH)
Aug 12 06:34:20.429: default/tiefighter:53184 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) to-proxy FORWARDED (TCP Flags: ACK, FIN)

The trace:to-proxy filter will show all flows that go through a proxy. In general, this could be either Envoy or the Cilium DNS proxy. However, since we have not yet deployed a DNS Network Policy, you will only see flows related to Envoy at the moment.

Let's extract all the flow information based on the protocol (e.g. HTTP) and source pod (e.g. the Tie Fighter), then export the result with the JSON output option, and finally filter with jq to only see the .flow.l7 field. This will show us the specific details parsed from the L7 traffic, such as the method and headers:

root@server:~# hubble observe --protocol http --from-pod default/tiefighter -o jsonpb | \
  head -n 1 | jq '.flow.l7'
{
  "type": "REQUEST",
  "http": {
    "method": "POST",
    "url": "http://deathstar.default.svc.cluster.local/v1/request-landing",
    "protocol": "HTTP/1.1",
    "headers": [
      {
        "key": ":scheme",
        "value": "http"
      },
      {
        "key": "Accept",
        "value": "*/*"
      },
      {
        "key": "User-Agent",
        "value": "curl/7.88.1"
      },
      {
        "key": "X-Envoy-Internal",
        "value": "true"
      },
      {
        "key": "X-Request-Id",
        "value": "298a0581-a614-406d-9fb7-f3dd2aff38a2"
      }
    ]
  }
}

vObserve the details of the flow, in particular the envoy-specific headers added to the request:

    X-Envoy-Internal
    X-Request-Id

Then, look for replies:
root@server:~# hubble observe --protocol http --to-pod default/tiefighter -o jsonpb | \
  head -n 1 | jq '.flow.l7'
{
  "type": "RESPONSE",
  "latency_ns": "937874",
  "http": {
    "code": 200,
    "method": "POST",
    "url": "http://deathstar.default.svc.cluster.local/v1/request-landing",
    "protocol": "HTTP/1.1",
    "headers": [
      {
        "key": "Content-Length",
        "value": "12"
      },
      {
        "key": "Content-Type",
        "value": "text/plain"
      },
      {
        "key": "Date",
        "value": "Mon, 12 Aug 2024 06:35:45 GMT"
      },
      {
        "key": "X-Envoy-Upstream-Service-Time",
        "value": "0"
      },
      {
        "key": "X-Request-Id",
        "value": "37dc2bde-f218-4bfb-8345-6413682c71cf"
      }
    ]
  }
}

Observe the envoy headers:

    X-Envoy-Upstream-Service-Time
    X-Request-Id

All these flows are ingress flows, as you can see by filtering for HTTP flows in the egress direction, which should return nothing:
root@server:~# hubble observe --protocol http --traffic-direction egress


Let's use the X-Request-Id to match a request and its response.
First, we'll need to make sure egress traffic from the Tie Fighter is captured by Envoy, so we'll need a L7 CNP for that.
If we apply an egress CNP though, this will disrupt DNS requests, which are also egress traffic, so we need to add a DNS policy as well:
root@server:~# kubectl apply -f policies/dns.yaml -f policies/tiefighter.yaml
ciliumnetworkpolicy.cilium.io/dns created
ciliumnetworkpolicy.cilium.io/tiefighter created
root@server:~# hubble observe --protocol http --traffic-direction egress
Aug 12 06:37:53.731: default/tiefighter:58412 (ID:1623) -> default/deathstar-b4b8ccfb5-lvbnx:80 (ID:58295) http-request FORWARDED (HTTP/1.1 POST http://deathstar.default.svc.cluster.local/v1/request-landing)
Aug 12 06:37:53.733: default/tiefighter:58412 (ID:1623) <- default/deathstar-b4b8ccfb5-lvbnx:80 (ID:58295) http-response FORWARDED (HTTP/1.1 200 0ms (POST http://deathstar.default.svc.cluster.local/v1/request-landing))
Aug 12 06:37:54.839: default/tiefighter:43664 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) http-request FORWARDED (HTTP/1.1 POST http://deathstar.default.svc.cluster.local/v1/request-landing)
Aug 12 06:37:54.841: default/tiefighter:43664 (ID:1623) <- default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) http-response FORWARDED (HTTP/1.1 200 1ms (POST http://deathstar.default.svc.cluster.local/v1/request-landing))
Aug 12 06:37:55.946: default/tiefighter:43678 (ID:1623) -> default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) http-request FORWARDED (HTTP/1.1 POST http://deathstar.default.svc.cluster.local/v1/request-landing)
Aug 12 06:37:55.948: default/tiefighter:43678 (ID:1623) <- default/deathstar-b4b8ccfb5-wc4vr:80 (ID:58295) http-response FORWARDED (HTTP/1.1 200 1ms (POST http://deathstar.default.svc.cluster.local/v1/request-landing))
Aug 12 06:37:57.052: default/tiefighter:58418 (ID:1623) -> default/deathstar-b4b8ccfb5-lvbnx:80 (ID:58295) http-request FORWARDED (HTTP/1.1 POST http://deathstar.default.svc.cluster.local/v1/request-landing)
Aug 12 06:37:57.053: default/tiefighter:58418 (ID:1623) <- default/deathstar-b4b8ccfb5-lvbnx:80 (ID:58295) http-response FORWARDED (HTTP/1.1 200 0ms (POST http://deathstar.default.svc.cluster.local/v1/request-landing))
Aug 12 06:37:58.153: default/tiefighter:58420 (ID:1623) -> default/deathstar-b4b8ccfb5-lvbnx:80 (ID:58295) http-request FORWARDED (HTTP/1.1 POST http://deathstar.default.svc.cluster.local/v1/request-landing)
Aug 12 06:37:58.155: default/tiefighter:58420 (ID:1623) <- default/deathstar-b4b8ccfb5-lvbnx:80 (ID:58295) http-response FORWARDED (HTTP/1.1 200 0ms (POST http://deathstar.default.svc.cluster.local/v1/request-landing))


You can now see egress requests from the Tie Fighter being forwarded to the Death Star, as well as the responses from the Death Star:
When using Kubernetes Network Policies, responses are automatically allowed and do not require an explicit rule.
This is why egress traffic corresponding to the response from the Death Star to the Tie Fighter is allowed, even though there is not egress policy for it.

Now, let's match request IDs! Run the following command to record some Hubble HTTP flows and save them to a file:
root@server:~# hubble observe --namespace default --protocol http -o jsonpb > flows.json

Find the first EGRESS flow in the file and get its ID:
root@server:~# REQUEST_ID=$(cat flows.json | jq -r '.flow | select(.source.labels[0]=="k8s:app.kubernetes.io/name=tiefighter" and .traffic_direction=="EGRESS") .l7.http.headers[] | select(.key=="X-Request-Id") .value' | head -n1)
echo $REQUEST_ID
60bf2961-208d-4d0b-be66-b999126f2b5f

Then find all flows with this request ID in the file and display their source identities:
root@server:~# cat flows.json | \
  jq 'select(.flow.l7.http.headers[] | .value == "'$REQUEST_ID'") .flow | {src_label: .source.labels[0], dst_label: .destination.labels[0], traffic_direction, type: .l7.type, time}'
{
  "src_label": "k8s:app.kubernetes.io/name=tiefighter",
  "dst_label": "k8s:app.kubernetes.io/name=deathstar",
  "traffic_direction": "EGRESS",
  "type": "REQUEST",
  "time": "2024-08-12T06:41:15.445385631Z"
}
{
  "src_label": "k8s:app.kubernetes.io/name=tiefighter",
  "dst_label": "k8s:app.kubernetes.io/name=deathstar",
  "traffic_direction": "INGRESS",
  "type": "REQUEST",
  "time": "2024-08-12T06:41:15.446324256Z"
}
{
  "src_label": "k8s:app.kubernetes.io/name=deathstar",
  "dst_label": "k8s:app.kubernetes.io/name=tiefighter",
  "traffic_direction": "INGRESS",
  "type": "RESPONSE",
  "time": "2024-08-12T06:41:15.446870330Z"
}
{
  "src_label": "k8s:app.kubernetes.io/name=deathstar",
  "dst_label": "k8s:app.kubernetes.io/name=tiefighter",
  "traffic_direction": "EGRESS",
  "type": "RESPONSE",
  "time": "2024-08-12T06:41:15.447209036Z"
}

You will see 4 sources:

    an egress flow from the tiefighter to the deathstar, corresponding to the original request
    the ingress flow for the same request, being forwarded from the proxy to the Death Star
    another egress flow for the response, from the deathstar to the tiefighter
    the corresponding ingress flow from the deathstar pod to the tiefighter

They might not appear in the same order depending on how flows were received from the Hubble relay servers on the different nodes.

Using Envoy, Hubble collections L7 metrics which can easily be exported via Prometheus
You can then use these metrics in readily-available Grafana dashboards:

In Isovalent Enterprise, Tetragon can be used to generate L7 metrics and flows directly with eBPF, without the use of an Envoy proxy.
This can be used with or without Cilium as the CNI plugin.


The Problem of gRPC Load-Balancing

gRPC is a popular framework to build scalable and fast APIs. It is used extensively in cloud native development and micro-services architecture. gRPC-based applications are very commonly deployed in Kubernetes clusters, albeit with some restrictions.

Kubernetes does not natively support gRPC Load Balancing out-of-the-box and therefore an additional tool —such as a proxy or a service mesh— is required to perform it. That is because the load-balancing decision has to be done at Layer 7, and not at Layer 3/4, and Kubernetes Services do not support L7 Load-Balancing.

L7 Load-Balancing with Kubernetes Services + Annotations

Users want a simpler solution to achieve L7 load-balancing: something as simple as applying an annotation to a Service.

Since Cilium 1.13, you can use Cilium’s Envoy proxy to achieve load-balancing for L7 services, with a simple annotation on the Kubernetes Service.

Let's explore how in this challenge!

For this demo we will use GCP's microservices demo app. Some of the micro-services used in this app leverage gRPC for service communications.

Create a grpc namespace:
root@server:~# kubectl create namespace grpc
namespace/grpc created
root@server:~# kubectl -n grpc apply -f /opt/gcp-microservices-demo.yml
deployment.apps/currencyservice created
service/currencyservice created
serviceaccount/currencyservice created
deployment.apps/loadgenerator created
serviceaccount/loadgenerator created
deployment.apps/productcatalogservice created
service/productcatalogservice created
serviceaccount/productcatalogservice created
deployment.apps/checkoutservice created
service/checkoutservice created
serviceaccount/checkoutservice created
deployment.apps/shippingservice created
service/shippingservice created
serviceaccount/shippingservice created
deployment.apps/cartservice created
service/cartservice created
serviceaccount/cartservice created
deployment.apps/redis-cart created
service/redis-cart created
deployment.apps/emailservice created
service/emailservice created
serviceaccount/emailservice created
deployment.apps/paymentservice created
service/paymentservice created
serviceaccount/paymentservice created
deployment.apps/frontend created
service/frontend created
service/frontend-external created
serviceaccount/frontend created
deployment.apps/recommendationservice created
service/recommendationservice created
serviceaccount/recommendationservice created
deployment.apps/adservice created
service/adservice created
serviceaccount/adservice created

The Pods should be up and running in less than a minute. Wait until the currenty service is ready:
root@server:~# kubectl -n grpc rollout status deploy/currencyservice
deployment "currencyservice" successfully rolled out

Two of the micro-services (Product Catalog and Currency) are accessible over gRPC and fronted by a ClusterIP Service. We will use the Current service for out tests.

Let's try to access the currency service of the application, which lists the currencies the shopping app supports. Access to the service will be done over gRPC, using grpcurl (the equivalent of curl but for gRPC).

We're going to access it, from another Pod. Deploy the Pod:
root@server:~# kubectl -n grpc apply -f pod.yaml
pod/pod-worker created
root@server:~# yq pod.yaml 
---
apiVersion: v1
kind: Pod
metadata:
  name: pod-worker
spec:
  nodeName: kind-worker
  containers:
    - name: netshoot
      image: nicolaka/netshoot:latest
      command: ["sleep", "infinite"]

Let's now install grpcurl to access the service over gRPC. First, let's enter the shell of the Pod.

root@server:~# kubectl -n grpc apply -f pod.yaml
pod/pod-worker created
root@server:~# yq pod.yaml 
---
apiVersion: v1
kind: Pod
metadata:
  name: pod-worker
spec:
  nodeName: kind-worker
  containers:
    - name: netshoot
      image: nicolaka/netshoot:latest
      command: ["sleep", "infinite"]
root@server:~# kubectl -n grpc get -f pod.yaml
NAME         READY   STATUS    RESTARTS   AGE
pod-worker   1/1     Running   0          24s
root@server:~# kubectl -n grpc exec -ti pod-worker -- zsh
                    dP            dP                           dP   
                    88            88                           88   
88d888b. .d8888b. d8888P .d8888b. 88d888b. .d8888b. .d8888b. d8888P 
88'  `88 88ooood8   88   Y8ooooo. 88'  `88 88'  `88 88'  `88   88   
88    88 88.  ...   88         88 88    88 88.  .88 88.  .88   88   
dP    dP `88888P'   dP   `88888P' dP    dP `88888P' `88888P'   dP   
                                                                    
Welcome to Netshoot! (github.com/nicolaka/netshoot)
Version: 0.13

Once in the shell of the client, run the following command to install grpcurl:
curl -sSL "https://github.com/fullstorydev/grpcurl/releases/download/v1.8.6/grpcurl_1.8.6_linux_x86_64.tar.gz" | tar -xz -C /usr/local/bin

Since gRPC is binary-encoded, you also need the proto definitions for the gRPC services in order to make gRPC requests. Download this for the demo app:
 pod-worker  ~  curl -o demo.proto https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/main/protos/demo.proto
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  6069  100  6069    0     0  26787      0 --:--:-- --:--:-- --:--:-- 26735

Let's try accessing the currency service with:
 pod-worker  ~  grpcurl -v -plaintext -proto ./demo.proto \
  currencyservice:7000 \
  hipstershop.CurrencyService/GetSupportedCurrencies

Resolved method descriptor:
rpc GetSupportedCurrencies ( .hipstershop.Empty ) returns ( .hipstershop.GetSupportedCurrenciesResponse );

Request metadata to send:
(empty)

Response headers received:
content-type: application/grpc+proto
date: Mon, 12 Aug 2024 07:01:53 GMT
grpc-accept-encoding: identity,deflate,gzip

Response contents:
{
  "currencyCodes": [
    "EUR",
    "USD",
    "JPY",
    "BGN",
    "CZK",
    "DKK",
    "GBP",
    "HUF",
    "PLN",
    "RON",
    "SEK",
    "CHF",
    "ISK",
    "NOK",
    "HRK",
    "RUB",
    "TRY",
    "AUD",
    "BRL",
    "CAD",
    "CNY",
    "HKD",
    "IDR",
    "ILS",
    "INR",
    "KRW",
    "MXN",
    "MYR",
    "NZD",
    "PHP",
    "SGD",
    "THB",
    "ZAR"
  ]
}

Response trailers received:
(empty)
Sent 0 requests and received 1 response

This should be successful and you should see a list of currency codes (EUR, USD, JPY, etc...).

Note the Response header:
content-type: application/grpc+proto
date: Fri, 20 Jan 2023 18:08:06 GMT
grpc-accept-encoding: identity,deflate,gzip



This is the default behaviour. Access is successful but as there's no L7 Load-Balancing capability yet, no L7 load-balancing is possible.

Let's observe traffic with Hubble, the network and security visibility tool.

In >_ Terminal 2, run the following command to look at the traffic from the pod-worker:
root@server:~# hubble observe --from-pod grpc/pod-worker
Aug 12 07:01:00.651: grpc/pod-worker:57352 (ID:27569) <> kube-system/coredns-76f75df574-flqbm (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:01:31.808: grpc/pod-worker:54186 (ID:27569) -> kube-system/coredns-76f75df574-z598w:53 (ID:2105) to-endpoint FORWARDED (UDP)
Aug 12 07:01:31.808: grpc/pod-worker:54186 (ID:27569) <> kube-system/coredns-76f75df574-z598w (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:01:31.808: grpc/pod-worker:54186 (ID:27569) <> kube-system/coredns-76f75df574-z598w (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:01:31.808: grpc/pod-worker:54186 (ID:27569) <> kube-system/coredns-76f75df574-z598w (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:01:31.808: grpc/pod-worker:54186 (ID:27569) <> kube-system/coredns-76f75df574-z598w (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:01:31.808: grpc/pod-worker:54186 (ID:27569) <> kube-system/coredns-76f75df574-z598w (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:01:31.808: grpc/pod-worker:54186 (ID:27569) <> kube-system/coredns-76f75df574-z598w (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:01:31.809: grpc/pod-worker:54186 (ID:27569) <> kube-system/coredns-76f75df574-z598w (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:01:31.809: grpc/pod-worker:54186 (ID:27569) <> kube-system/coredns-76f75df574-z598w (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:01:31.809: grpc/pod-worker:54186 (ID:27569) <> kube-system/coredns-76f75df574-z598w (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:01:31.809: grpc/pod-worker:54186 (ID:27569) <> kube-system/coredns-76f75df574-z598w (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:01:31.811: grpc/pod-worker:54186 (ID:27569) <> kube-system/coredns-76f75df574-z598w (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:01:31.811: grpc/pod-worker:54186 (ID:27569) <> kube-system/coredns-76f75df574-z598w (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:01:31.812: grpc/pod-worker:54186 (ID:27569) <> kube-system/coredns-76f75df574-z598w (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:01:31.812: grpc/pod-worker:54186 (ID:27569) <> kube-system/coredns-76f75df574-z598w (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:01:31.819: grpc/pod-worker:55936 (ID:27569) -> 185.199.108.133:443 (world) to-stack FORWARDED (TCP Flags: ACK)
Aug 12 07:01:31.822: grpc/pod-worker:55936 (ID:27569) -> 185.199.108.133:443 (world) to-stack FORWARDED (TCP Flags: ACK, PSH)
Aug 12 07:01:32.035: grpc/pod-worker:55936 (ID:27569) -> 185.199.108.133:443 (world) to-stack FORWARDED (TCP Flags: ACK, FIN)
Aug 12 07:01:32.039: grpc/pod-worker:55936 (ID:27569) -> 185.199.108.133:443 (world) to-stack FORWARDED (TCP Flags: RST)
Aug 12 07:01:32.039: grpc/pod-worker:55936 (ID:27569) -> 185.199.108.133:443 (world) to-stack FORWARDED (TCP Flags: RST)
Aug 12 07:01:32.040: grpc/pod-worker:55936 (ID:27569) -> 185.199.108.133:443 (world) to-stack FORWARDED (TCP Flags: RST)
Aug 12 07:01:53.113: grpc/pod-worker (ID:27569) <> kube-system/kube-dns:53 (world) pre-xlate-fwd TRACED (UDP)
Aug 12 07:01:53.113: grpc/pod-worker (ID:27569) <> kube-system/coredns-76f75df574-flqbm:53 (ID:2105) post-xlate-fwd TRANSLATED (UDP)
Aug 12 07:01:53.113: grpc/pod-worker:37330 (ID:27569) -> kube-system/coredns-76f75df574-flqbm:53 (ID:2105) to-overlay FORWARDED (UDP)
Aug 12 07:01:53.113: grpc/pod-worker (ID:27569) <> kube-system/kube-dns:53 (world) pre-xlate-fwd TRACED (UDP)
Aug 12 07:01:53.113: grpc/pod-worker (ID:27569) <> kube-system/coredns-76f75df574-flqbm:53 (ID:2105) post-xlate-fwd TRANSLATED (UDP)
Aug 12 07:01:53.113: grpc/pod-worker:49215 (ID:27569) -> kube-system/coredns-76f75df574-flqbm:53 (ID:2105) to-overlay FORWARDED (UDP)
Aug 12 07:01:53.113: grpc/pod-worker:49215 (ID:27569) -> kube-system/coredns-76f75df574-flqbm:53 (ID:2105) to-endpoint FORWARDED (UDP)
Aug 12 07:01:53.113: grpc/pod-worker:49215 (ID:27569) <> kube-system/coredns-76f75df574-flqbm (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:01:53.113: grpc/pod-worker:37330 (ID:27569) -> kube-system/coredns-76f75df574-flqbm:53 (ID:2105) to-endpoint FORWARDED (UDP)
Aug 12 07:01:53.113: grpc/pod-worker:37330 (ID:27569) <> kube-system/coredns-76f75df574-flqbm (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:01:53.113: grpc/pod-worker (ID:27569) <> grpc/currencyservice:7000 (world) pre-xlate-fwd TRACED (TCP)
Aug 12 07:01:53.113: grpc/pod-worker (ID:27569) <> grpc/currencyservice-84cc8dbfcc-kzks7:7000 (ID:5810) post-xlate-fwd TRANSLATED (TCP)
Aug 12 07:01:53.113: grpc/pod-worker:58348 (ID:27569) -> grpc/currencyservice-84cc8dbfcc-kzks7:7000 (ID:5810) to-endpoint FORWARDED (TCP Flags: SYN)
Aug 12 07:01:53.114: grpc/pod-worker:58348 (ID:27569) -> grpc/currencyservice-84cc8dbfcc-kzks7:7000 (ID:5810) to-endpoint FORWARDED (TCP Flags: ACK)
Aug 12 07:01:53.114: grpc/pod-worker:58348 (ID:27569) -> grpc/currencyservice-84cc8dbfcc-kzks7:7000 (ID:5810) to-endpoint FORWARDED (TCP Flags: ACK, PSH)
Aug 12 07:01:53.114: grpc/pod-worker:58348 (ID:27569) <> grpc/currencyservice-84cc8dbfcc-kzks7 (ID:5810) pre-xlate-rev TRACED (TCP)
Aug 12 07:01:53.118: grpc/pod-worker:58348 (ID:27569) -> grpc/currencyservice-84cc8dbfcc-kzks7:7000 (ID:5810) to-endpoint FORWARDED (TCP Flags: ACK, FIN)
Aug 12 07:01:53.118: grpc/pod-worker:58348 (ID:27569) -> grpc/currencyservice-84cc8dbfcc-kzks7:7000 (ID:5810) to-endpoint FORWARDED (TCP Flags: ACK)

If you filter based on traffic sent to the Envoy proxy, no flow should appear:
root@server:~# hubble observe -n grpc --type trace:to-proxy
root@server:~# 

Access the 🔗 Hubble UI tab and select the grpc namespace to visualize the application's architecture and components.

Notice that all boxes only say "TCP". There are no L7 details because no L7 Network Policies have been deployed in this namespace.
In order to use L7 load balancing in the cluster, we first need to enable the CiliumEnvoyConfig CRD in the cluster, as this CRD will be used by Cilium to implement the L7 load-balancer using Envoy.
root@server:~# helm -n kube-system upgrade cilium cilium/cilium \
  --version 1.16.0 \
  --reuse-values \
  --set loadBalancer.l7.backend=envoy
Release "cilium" has been upgraded. Happy Helming!
NAME: cilium
LAST DEPLOYED: Mon Aug 12 07:04:19 2024
NAMESPACE: kube-system
STATUS: deployed
REVISION: 2
TEST SUITE: None
NOTES:
You have successfully installed Cilium with Hubble Relay and Hubble UI.

Your release version is 1.16.0.

For any further help, visit https://docs.cilium.io/en/v1.16/gettinghelp

Enabling this can be done by upgrading the Helm chart in the >_ Terminal 2 tab:
Restart the Cilium Operator so it deploys the new CRD, and the Cilium agent so it is ready to honor the L7 annotations on Services:
root@server:~# kubectl -n kube-system rollout restart deployment cilium-operator
kubectl -n kube-system rollout restart daemonset cilium
kubectl -n kube-system rollout restart daemonset cilium-envoy
deployment.apps/cilium-operator restarted
daemonset.apps/cilium restarted
daemonset.apps/cilium-envoy restarted

Verify that the Cilium Envoy Configs are activated:
root@server:~# cilium config view | grep envoy-config
enable-envoy-config                               true
envoy-config-retry-interval                       15s

Let's now enable L7 Load-Balancing for these gRPC services. Simply annotating Services with these labels will enable this functionality. In >_ Terminal 2:
root@server:~# kubectl -n grpc \
  annotate svc/currencyservice \
  "service.cilium.io/lb-l7=enabled"
service/currencyservice annotated

Look at the CiliumEnvoyConfig CRD created (note you may need to run this command a couple of times):
root@server:~# kubectl -n grpc get cec
NAME                              AGE
cilium-envoy-lb-currencyservice   22s

root@server:~# kubectl -n grpc get cec cilium-envoy-lb-currencyservice -o yaml | yq .spec

root@server:~# kubectl -n grpc get cec cilium-envoy-lb-currencyservice -o yaml | yq .spec
resources:
  - '@type': type.googleapis.com/envoy.config.listener.v3.Listener
    filterChains:
      - filterChainMatch:
          transportProtocol: raw_buffer
        filters:
          - name: envoy.filters.network.http_connection_manager
            typedConfig:
              '@type': type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
              httpFilters:
                - name: envoy.filters.http.router
                  typedConfig:
                    '@type': type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
              rds:
                routeConfigName: grpc/currencyservice
              statPrefix: grpc/currencyservice
              upgradeConfigs:
                - upgradeType: websocket
              useRemoteAddress: true
    listenerFilters:
      - name: envoy.filters.listener.tls_inspector
        typedConfig:
          '@type': type.googleapis.com/envoy.extensions.filters.listener.tls_inspector.v3.TlsInspector
    name: grpc/currencyservice
  - '@type': type.googleapis.com/envoy.config.route.v3.RouteConfiguration
    name: grpc/currencyservice
    virtualHosts:
      - domains:
          - '*'
        name: grpc/currencyservice
        routes:
          - match:
              prefix: /
            route:
              cluster: grpc/currencyservice
              maxStreamDuration:
                maxStreamDuration: 0s
  - '@type': type.googleapis.com/envoy.config.cluster.v3.Cluster
    connectTimeout: 5s
    name: grpc/currencyservice
    outlierDetection:
      consecutiveLocalOriginFailure: 2
      splitExternalLocalOriginErrors: true
    type: EDS
    typedExtensionProtocolOptions:
      envoy.extensions.upstreams.http.v3.HttpProtocolOptions:
        '@type': type.googleapis.com/envoy.extensions.upstreams.http.v3.HttpProtocolOptions
        commonHttpProtocolOptions:
          idleTimeout: 60s
        useDownstreamProtocolConfig:
          http2ProtocolOptions: {}
services:
  - listener: ""
    name: currencyservice
    namespace: grpc


The services section at the bottom shows that it applies to the currencyservice service in the grpc namespace.

There are 3 Envoy resources listed:

    a type.googleapis.com/envoy.config.listener.v3.Listener resource to setup a gRPC listener in Envoy
    a type.googleapis.com/envoy.config.route.v3.RouteConfiguration resource which targets the grpc/currentservice service 100% of the time
    a type.googleapis.com/envoy.config.cluster.v3.Cluster resource which configures the behavior of the L7 load-balancer.

Let's now try again to access these services over gRPC. In >_ Terminal 1:
grpcurl -v -plaintext -proto ./demo.proto \
  currencyservice:7000 \
  hipstershop.CurrencyService/GetSupportedCurrencies

Notice the change in the Response headers replies:
pod-worker  ~  grpcurl -v -plaintext -proto ./demo.proto \
  currencyservice:7000 \
  hipstershop.CurrencyService/GetSupportedCurrencies

Resolved method descriptor:
rpc GetSupportedCurrencies ( .hipstershop.Empty ) returns ( .hipstershop.GetSupportedCurrenciesResponse );

Request metadata to send:
(empty)

Response headers received:
content-type: application/grpc+proto
date: Mon, 12 Aug 2024 07:11:05 GMT
grpc-accept-encoding: identity,deflate,gzip
server: envoy
x-envoy-upstream-service-time: 1

Access is still successful and traffic has been forwarded to Envoy which is now handling L7 traffic to the destination pods and providing load-balancing.

Let's verify that with Hubble.

In >_ Terminal 2, run the following command again:
root@server:~# hubble observe -n grpc --type trace:to-proxy
Aug 12 07:11:05.639: grpc/pod-worker:36482 (ID:27569) -> grpc/currencyservice:7000 (world) to-proxy FORWARDED (TCP Flags: ACK)
Aug 12 07:11:10.906: grpc/frontend-74768c5ccc-zffs5:45152 (ID:65429) -> grpc/currencyservice:7000 (world) to-proxy FORWARDED (TCP Flags: ACK, PSH)
Aug 12 07:11:10.907: grpc/frontend-74768c5ccc-zffs5:45152 (ID:65429) <- grpc/currencyservice-88c8854b7-fj69v:7000 (ID:5810) to-proxy FORWARDED (TCP Flags: ACK, PSH)
Aug 12 07:11:19.078: grpc/frontend-74768c5ccc-zffs5:45152 (ID:65429) -> grpc/currencyservice:7000 (world) to-proxy FORWARDED (TCP Flags: ACK, PSH)
Aug 12 07:11:19.079: grpc/frontend-74768c5ccc-zffs5:45152 (ID:65429) <- grpc/currencyservice-88c8854b7-fj69v:7000 (ID:5810) to-proxy FORWARDED (TCP Flags: ACK, PSH)
Aug 12 07:11:22.981: grpc/checkoutservice-85dfc68d5c-dl962:38808 (ID:5697) -> grpc/currencyservice:7000 (world) to-proxy FORWARDED (TCP Flags: SYN)
Aug 12 07:11:22.982: grpc/checkoutservice-85dfc68d5c-dl962:38808 (ID:5697) -> grpc/currencyservice:7000 (world) to-proxy FORWARDED (TCP Flags: ACK)
Aug 12 07:11:22.982: grpc/checkoutservice-85dfc68d5c-dl962:38808 (ID:5697) -> grpc/currencyservice:7000 (world) to-proxy FORWARDED (TCP Flags: ACK, PSH)
Aug 12 07:11:22.983: grpc/checkoutservice-85dfc68d5c-dl962:38808 (ID:5697) <- grpc/currencyservice-88c8854b7-fj69v:7000 (ID:5810) to-proxy FORWARDED (TCP Flags: SYN, ACK)
Aug 12 07:11:22.984: grpc/checkoutservice-85dfc68d5c-dl962:38808 (ID:5697) <- grpc/currencyservice-88c8854b7-fj69v:7000 (ID:5810) to-proxy FORWARDED (TCP Flags: ACK, PSH)
Aug 12 07:11:25.813: grpc/frontend-74768c5ccc-zffs5:45152 (ID:65429) -> grpc/currencyservice:7000 (world) to-proxy FORWARDED (TCP Flags: ACK, PSH)
Aug 12 07:11:25.814: grpc/frontend-74768c5ccc-zffs5:45152 (ID:65429) <- grpc/currencyservice-88c8854b7-fj69v:7000 (ID:5810) to-proxy FORWARDED (TCP Flags: ACK, PSH)
Aug 12 07:11:31.786: grpc/frontend-74768c5ccc-zffs5:45152 (ID:65429) -> grpc/currencyservice:7000 (world) to-proxy FORWARDED (TCP Flags: ACK, PSH)
Aug 12 07:11:31.787: grpc/frontend-74768c5ccc-zffs5:45152 (ID:65429) <- grpc/currencyservice-88c8854b7-fj69v:7000 (ID:5810) to-proxy FORWARDED (TCP Flags: ACK, PSH)
Aug 12 07:11:32.826: grpc/checkoutservice-85dfc68d5c-dl962:38808 (ID:5697) -> grpc/currencyservice:7000 (world) to-proxy FORWARDED (TCP Flags: ACK, PSH)
Aug 12 07:11:32.827: grpc/checkoutservice-85dfc68d5c-dl962:38808 (ID:5697) <- grpc/currencyservice-88c8854b7-fj69v:7000 (ID:5810) to-proxy FORWARDED (TCP Flags: ACK, PSH)
Aug 12 07:11:37.970: grpc/frontend-74768c5ccc-zffs5:45152 (ID:65429) -> grpc/currencyservice:7000 (world) to-proxy FORWARDED (TCP Flags: ACK, PSH)
Aug 12 07:11:37.971: grpc/frontend-74768c5ccc-zffs5:45152 (ID:65429) <- grpc/currencyservice-88c8854b7-fj69v:7000 (ID:5810) to-proxy FORWARDED (TCP Flags: ACK, PSH)
Aug 12 07:11:43.800: grpc/frontend-74768c5ccc-zffs5:45152 (ID:65429) -> grpc/currencyservice:7000 (world) to-proxy FORWARDED (TCP Flags: ACK, PSH)
Aug 12 07:11:43.802: grpc/frontend-74768c5ccc-zffs5:45152 (ID:65429) <- grpc/currencyservice-88c8854b7-fj69v:7000 (ID:5810) to-proxy FORWARDED (TCP Flags: ACK, PSH)

Once Envoy is used as an internal load-balancer, you can fine-tune its behavior using the service.cilium.io/lb-l7-algorithm annotation.

This allows to choose the type of Envoy load-balancer to use.

In the >_ Terminal 2 tab, add that annotation to the Current Service:
root@server:~# kubectl -n grpc \
  annotate svc/currencyservice \
  "service.cilium.io/lb-l7-algorithm=least_request"
service/currencyservice annotated

Check the generated CEC again:
root@server:~# kubectl -n grpc get cec cilium-envoy-lb-currencyservice -o yaml | \
  yq .spec
resources:
  - '@type': type.googleapis.com/envoy.config.listener.v3.Listener
    filterChains:
      - filterChainMatch:
          transportProtocol: raw_buffer
        filters:
          - name: envoy.filters.network.http_connection_manager
            typedConfig:
              '@type': type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
              httpFilters:
                - name: envoy.filters.http.router
                  typedConfig:
                    '@type': type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
              rds:
                routeConfigName: grpc/currencyservice
              statPrefix: grpc/currencyservice
              upgradeConfigs:
                - upgradeType: websocket
              useRemoteAddress: true
    listenerFilters:
      - name: envoy.filters.listener.tls_inspector
        typedConfig:
          '@type': type.googleapis.com/envoy.extensions.filters.listener.tls_inspector.v3.TlsInspector
    name: grpc/currencyservice
  - '@type': type.googleapis.com/envoy.config.route.v3.RouteConfiguration
    name: grpc/currencyservice
    virtualHosts:
      - domains:
          - '*'
        name: grpc/currencyservice
        routes:
          - match:
              prefix: /
            route:
              cluster: grpc/currencyservice
              maxStreamDuration:
                maxStreamDuration: 0s
  - '@type': type.googleapis.com/envoy.config.cluster.v3.Cluster
    connectTimeout: 5s
    lbPolicy: LEAST_REQUEST
    name: grpc/currencyservice
    outlierDetection:
      consecutiveLocalOriginFailure: 2
      splitExternalLocalOriginErrors: true
    type: EDS
    typedExtensionProtocolOptions:
      envoy.extensions.upstreams.http.v3.HttpProtocolOptions:
        '@type': type.googleapis.com/envoy.extensions.upstreams.http.v3.HttpProtocolOptions
        commonHttpProtocolOptions:
          idleTimeout: 60s
        useDownstreamProtocolConfig:
          http2ProtocolOptions: {}
services:
  - listener: ""
    name: currencyservice
    namespace: grpc

  
The type.googleapis.com/envoy.config.cluster.v3.Cluster resource is now configured with lbPolicy: LEAST_REQUEST, so it will make use of the least request Envoy load-balancer.

In the next challenge, we will explore an advanced use case for Cilium Envoy Configs.

Advanced Envoy Use Cases

Cilium uses Envoy for multiple functionalities, and a good number has been added for Ingress and Gateway API support (see the Ingress Controller and Gateway API labs).

However, Envoy is a very feature-rich software, and while Cilium provides several abstractions for Envoy configurations, it only covers some of the conceivable scenarios.

For this reason, Cilium provides a Cilium Envoy Config CRDs, which lets users configure Envoy themselves to implement the features they want.

Let's use Cilium Envoy Config to generate a circuit breaker.

root@server:~# kubectl create namespace circuit-break
namespace/circuit-break created
root@server:~# kubectl -n circuit-break apply -f test-application-proxy-circuit-breaker.yaml
service/fortio created
deployment.apps/fortio-deploy created
configmap/coredns-configmap created
deployment.apps/echo-service created
service/echo-service created

Apply the Envoy Config for circuit breaking:
root@server:~# kubectl apply -f envoy-circuit-breaker.yaml
ciliumclusterwideenvoyconfig.cilium.io/envoy-circuit-breaker created

This is a CiliumClusterwideEnvoyConfig, which configures Envoy for all namespaces. Let's have a look at its specification:

root@server:~# kubectl get ccec envoy-circuit-breaker -o yaml | yq .spec
resources:
  - '@type': type.googleapis.com/envoy.config.listener.v3.Listener
    filter_chains:
      - filters:
          - name: envoy.filters.network.http_connection_manager
            typed_config:
              '@type': type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
              http_filters:
                - name: envoy.filters.http.router
                  typed_config:
                    '@type': type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
              rds:
                route_config_name: lb_route
              skip_xff_append: true
              stat_prefix: envoy-lb-listener
              use_remote_address: true
    name: envoy-lb-listener
  - '@type': type.googleapis.com/envoy.config.route.v3.RouteConfiguration
    name: lb_route
    virtual_hosts:
      - domains:
          - '*'
        name: lb_route
        routes:
          - match:
              prefix: /
            route:
              weighted_clusters:
                clusters:
                  - name: circuit-break/echo-service
                    weight: 100
  - '@type': type.googleapis.com/envoy.config.cluster.v3.Cluster
    circuit_breakers:
      thresholds:
        - max_pending_requests: 1
          max_requests: 2
          priority: DEFAULT
    connect_timeout: 5s
    lb_policy: ROUND_ROBIN
    name: circuit-break/echo-service
    outlier_detection:
      consecutive_local_origin_failure: 2
      split_external_local_origin_errors: true
    type: EDS
services:
  - name: echo-service
    namespace: circuit-break



You can see 3 resources:

    a type.googleapis.com/envoy.config.listener.v3.Listener resource, which configures an Envoy listener to receive the traffic
    a type.googleapis.com/envoy.config.route.v3.RouteConfiguration resource configuring the route to load-balance the traffic to the circuit-break/echo-server Kubernetes service
    a type.googleapis.com/envoy.config.cluster.v3.Cluster resource configuring the circuit breaking logic to break the circuit if:
        either the number of concurrent requests exceeds 2
        or the number of pending requests exceeds 1.

The services parameter at the bottom of the spec indicates that Cilium will forward traffic aimed at the echo-server service in the circuit-break namespace to this Envoy listener.

In order to test the circuit breaking logic, we will use the Fortio pod. Fortio is a load testing library, and we're going to use it to send multiple concurrent requests to trigger the circuit breaking rule.

Check that the pods are running:
root@server:~# kubectl -n circuit-break get po --show-labels
NAME                             READY   STATUS    RESTARTS   AGE   LABELS
echo-service-5fbcbb78cb-l5gc5    2/2     Running   0          81s   kind=echo,name=echo-service,other=echo,pod-template-hash=5fbcbb78cb
fortio-deploy-689bd5969b-x8cng   1/1     Running   0          81s   app=fortio,pod-template-hash=689bd5969b
root@server:~# 

Using Fortio, make 20 requests to the service, with 1 concurrent connection:
root@server:~# kubectl -n circuit-break exec deploy/fortio-deploy -c fortio -- \
  /usr/bin/fortio load -c 1 -qps 0 -n 20 http://echo-service:8080
{"ts":1723446935.751966,"level":"info","r":1,"file":"scli.go","line":123,"msg":"Starting","command":"Φορτίο","version":"1.60.3 h1:adR0uf/69M5xxKaMLAautVf9FIVkEpMwuEWyMaaSnI0= go1.20.10 amd64 linux"}
Fortio 1.60.3 running at 0 queries per second, 8->8 procs, for 20 calls: http://echo-service:8080
{"ts":1723446935.752510,"level":"info","r":1,"file":"httprunner.go","line":121,"msg":"Starting http test","run":0,"url":"http://echo-service:8080","threads":1,"qps":"-1.0","warmup":"parallel","conn-reuse":""}
Starting at max qps with 1 thread(s) [gomax 8] for exactly 20 calls (20 per thread + 0)
{"ts":1723446935.781057,"level":"info","r":1,"file":"periodic.go","line":850,"msg":"T000 ended after 27.508349ms : 20 calls. qps=727.0519942872617"}
Ended after 27.560013ms : 20 calls. qps=725.69
{"ts":1723446935.781106,"level":"info","r":1,"file":"periodic.go","line":581,"msg":"Run ended","run":0,"elapsed":"27.560013ms","calls":20,"qps":725.6890626285264}
Aggregated Function Time : count 20 avg 0.0013737066 +/- 0.0005663 min 0.000934977 max 0.003307302 sum 0.027474133
# range, mid point, percentile, count
>= 0.000934977 <= 0.001 , 0.000967489 , 20.00, 4
> 0.001 <= 0.002 , 0.0015 , 90.00, 14
> 0.002 <= 0.003 , 0.0025 , 95.00, 1
> 0.003 <= 0.0033073 , 0.00315365 , 100.00, 1
# target 50% 0.00142857
# target 75% 0.00178571
# target 90% 0.002
# target 99% 0.00324584
# target 99.9% 0.00330116
Error cases : no data
# Socket and IP used for each connection:
[0]   1 socket used, resolved to 10.96.133.65:8080, connection timing : count 1 avg 0.00017966 +/- 0 min 0.00017966 max 0.00017966 sum 0.00017966
Connection time histogram (s) : count 1 avg 0.00017966 +/- 0 min 0.00017966 max 0.00017966 sum 0.00017966
# range, mid point, percentile, count
>= 0.00017966 <= 0.00017966 , 0.00017966 , 100.00, 1
# target 50% 0.00017966
# target 75% 0.00017966
# target 90% 0.00017966
# target 99% 0.00017966
# target 99.9% 0.00017966
Sockets used: 1 (for perfect keepalive, would be 1)
Uniform: false, Jitter: false, Catchup allowed: true
IP addresses distribution:
10.96.133.65:8080: 1
Code 200 : 20 (100.0 %)
Response Header Sizes : count 20 avg 390 +/- 0 min 390 max 390 sum 7800
Response Body/Total Sizes : count 20 avg 2447 +/- 0 min 2447 max 2447 sum 48940
All done 20 calls (plus 0 warmup) 1.374 ms avg, 725.7 qps

At the bottom of the output, look for the response stats, you should see:

Code 200 : 20 (100.0 %)

All requests return a 200 response. This is expected as the load we're sending is below the thresholds we set in the circuit breaking rule.

Now increase to 2 concurrent connections:
root@server:~# kubectl -n circuit-break exec deploy/fortio-deploy -c fortio -- \
  /usr/bin/fortio load -c 2 -qps 0 -n 20 http://echo-service:8080
{"ts":1723446962.299623,"level":"info","r":1,"file":"scli.go","line":123,"msg":"Starting","command":"Φορτίο","version":"1.60.3 h1:adR0uf/69M5xxKaMLAautVf9FIVkEpMwuEWyMaaSnI0= go1.20.10 amd64 linux"}
Fortio 1.60.3 running at 0 queries per second, 8->8 procs, for 20 calls: http://echo-service:8080
{"ts":1723446962.300159,"level":"info","r":1,"file":"httprunner.go","line":121,"msg":"Starting http test","run":0,"url":"http://echo-service:8080","threads":2,"qps":"-1.0","warmup":"parallel","conn-reuse":""}
Starting at max qps with 2 thread(s) [gomax 8] for exactly 20 calls (10 per thread + 0)
{"ts":1723446962.303444,"level":"warn","r":12,"file":"http_client.go","line":1104,"msg":"Non ok http code","code":503,"status":"HTTP/1.1 503","thread":1,"run":0}
{"ts":1723446962.320371,"level":"info","r":11,"file":"periodic.go","line":850,"msg":"T000 ended after 18.289089ms : 10 calls. qps=546.7740902786355"}
{"ts":1723446962.320637,"level":"info","r":12,"file":"periodic.go","line":850,"msg":"T001 ended after 18.59151ms : 10 calls. qps=537.8799247613562"}
Ended after 18.623676ms : 20 calls. qps=1073.9
{"ts":1723446962.320689,"level":"info","r":1,"file":"periodic.go","line":581,"msg":"Run ended","run":0,"elapsed":"18.623676ms","calls":20,"qps":1073.9018440827688}
Aggregated Function Time : count 20 avg 0.0018338005 +/- 0.0005484 min 0.001225258 max 0.003148336 sum 0.03667601
# range, mid point, percentile, count
>= 0.00122526 <= 0.002 , 0.00161263 , 80.00, 16
> 0.002 <= 0.003 , 0.0025 , 90.00, 2
> 0.003 <= 0.00314834 , 0.00307417 , 100.00, 2
# target 50% 0.0016901
# target 75% 0.00194835
# target 90% 0.003
# target 99% 0.0031335
# target 99.9% 0.00314685
Error cases : count 1 avg 0.001431811 +/- 0 min 0.001431811 max 0.001431811 sum 0.001431811
# range, mid point, percentile, count
>= 0.00143181 <= 0.00143181 , 0.00143181 , 100.00, 1
# target 50% 0.00143181
# target 75% 0.00143181
# target 90% 0.00143181
# target 99% 0.00143181
# target 99.9% 0.00143181
# Socket and IP used for each connection:
[0]   1 socket used, resolved to 10.96.133.65:8080, connection timing : count 1 avg 0.000231171 +/- 0 min 0.000231171 max 0.000231171 sum 0.000231171
[1]   2 socket used, resolved to 10.96.133.65:8080, connection timing : count 2 avg 0.0001976765 +/- 2.38e-05 min 0.000173872 max 0.000221481 sum 0.000395353
Connection time histogram (s) : count 3 avg 0.00020884133 +/- 2.504e-05 min 0.000173872 max 0.000231171 sum 0.000626524
# range, mid point, percentile, count
>= 0.000173872 <= 0.000231171 , 0.000202522 , 100.00, 3
# target 50% 0.000188197
# target 75% 0.000209684
# target 90% 0.000222576
# target 99% 0.000230312
# target 99.9% 0.000231085
Sockets used: 3 (for perfect keepalive, would be 2)
Uniform: false, Jitter: false, Catchup allowed: true
IP addresses distribution:
10.96.133.65:8080: 3
Code 200 : 19 (95.0 %)
Code 503 : 1 (5.0 %)
Response Header Sizes : count 20 avg 370.5 +/- 85 min 0 max 390 sum 7410
Response Body/Total Sizes : count 20 avg 2336.7 +/- 480.8 min 241 max 2447 sum 46734
All done 20 calls (plus 0 warmup) 1.834 ms avg, 1073.9 qps

This time, the output will be similar to this:

Code 200 : 18 (90.0 %)
Code 503 : 2 (10.0 %)

A few of the requests are failing. This is statistically expected, as we're sending 2 concurrent requests and not waiting between requests.

Finally, try with 4 concurrent requests:

root@server:~# kubectl -n circuit-break exec deploy/fortio-deploy -c fortio -- \
  /usr/bin/fortio load -c 4 -qps 0 -n 20 http://echo-service:8080
{"ts":1723446987.870369,"level":"info","r":1,"file":"scli.go","line":123,"msg":"Starting","command":"Φορτίο","version":"1.60.3 h1:adR0uf/69M5xxKaMLAautVf9FIVkEpMwuEWyMaaSnI0= go1.20.10 amd64 linux"}
Fortio 1.60.3 running at 0 queries per second, 8->8 procs, for 20 calls: http://echo-service:8080
{"ts":1723446987.870933,"level":"info","r":1,"file":"httprunner.go","line":121,"msg":"Starting http test","run":0,"url":"http://echo-service:8080","threads":4,"qps":"-1.0","warmup":"parallel","conn-reuse":""}
Starting at max qps with 4 thread(s) [gomax 8] for exactly 20 calls (5 per thread + 0)
{"ts":1723446987.875497,"level":"warn","r":50,"file":"http_client.go","line":1104,"msg":"Non ok http code","code":503,"status":"HTTP/1.1 503","thread":3,"run":0}
{"ts":1723446987.875707,"level":"warn","r":49,"file":"http_client.go","line":1104,"msg":"Non ok http code","code":503,"status":"HTTP/1.1 503","thread":2,"run":0}
{"ts":1723446987.875812,"level":"warn","r":15,"file":"http_client.go","line":1104,"msg":"Non ok http code","code":503,"status":"HTTP/1.1 503","thread":0,"run":0}
{"ts":1723446987.877221,"level":"warn","r":49,"file":"http_client.go","line":1104,"msg":"Non ok http code","code":503,"status":"HTTP/1.1 503","thread":2,"run":0}
{"ts":1723446987.878600,"level":"warn","r":16,"file":"http_client.go","line":1104,"msg":"Non ok http code","code":503,"status":"HTTP/1.1 503","thread":1,"run":0}
{"ts":1723446987.879057,"level":"warn","r":49,"file":"http_client.go","line":1104,"msg":"Non ok http code","code":503,"status":"HTTP/1.1 503","thread":2,"run":0}
{"ts":1723446987.880554,"level":"warn","r":16,"file":"http_client.go","line":1104,"msg":"Non ok http code","code":503,"status":"HTTP/1.1 503","thread":1,"run":0}
{"ts":1723446987.880554,"level":"warn","r":49,"file":"http_client.go","line":1104,"msg":"Non ok http code","code":503,"status":"HTTP/1.1 503","thread":2,"run":0}
{"ts":1723446987.882153,"level":"warn","r":49,"file":"http_client.go","line":1104,"msg":"Non ok http code","code":503,"status":"HTTP/1.1 503","thread":2,"run":0}
{"ts":1723446987.882215,"level":"info","r":49,"file":"periodic.go","line":850,"msg":"T002 ended after 8.515272ms : 5 calls. qps=587.1803038117865"}
{"ts":1723446987.882301,"level":"warn","r":50,"file":"http_client.go","line":1104,"msg":"Non ok http code","code":503,"status":"HTTP/1.1 503","thread":3,"run":0}
{"ts":1723446987.884333,"level":"warn","r":50,"file":"http_client.go","line":1104,"msg":"Non ok http code","code":503,"status":"HTTP/1.1 503","thread":3,"run":0}
{"ts":1723446987.884410,"level":"info","r":50,"file":"periodic.go","line":850,"msg":"T003 ended after 10.709549ms : 5 calls. qps=466.8730681376032"}
{"ts":1723446987.886563,"level":"info","r":15,"file":"periodic.go","line":850,"msg":"T000 ended after 12.845366ms : 5 calls. qps=389.24542905200207"}
{"ts":1723446987.886920,"level":"info","r":16,"file":"periodic.go","line":850,"msg":"T001 ended after 13.216667ms : 5 calls. qps=378.31020483454716"}
Ended after 13.279659ms : 20 calls. qps=1506.1
{"ts":1723446987.887007,"level":"info","r":1,"file":"periodic.go","line":581,"msg":"Run ended","run":0,"elapsed":"13.279659ms","calls":20,"qps":1506.0627686298271}
Aggregated Function Time : count 20 avg 0.0022373641 +/- 0.000934 min 0.000755147 max 0.003949851 sum 0.044747282
# range, mid point, percentile, count
>= 0.000755147 <= 0.001 , 0.000877573 , 5.00, 1
> 0.001 <= 0.002 , 0.0015 , 55.00, 10
> 0.002 <= 0.003 , 0.0025 , 75.00, 4
> 0.003 <= 0.00394985 , 0.00347493 , 100.00, 5
# target 50% 0.0019
# target 75% 0.003
# target 90% 0.00356991
# target 99% 0.00391186
# target 99.9% 0.00394605
Error cases : count 11 avg 0.0016292202 +/- 0.0004098 min 0.000755147 max 0.002071394 sum 0.017921422
# range, mid point, percentile, count
>= 0.000755147 <= 0.001 , 0.000877573 , 9.09, 1
> 0.001 <= 0.002 , 0.0015 , 81.82, 8
> 0.002 <= 0.00207139 , 0.0020357 , 100.00, 2
# target 50% 0.0015625
# target 75% 0.00190625
# target 90% 0.00203213
# target 99% 0.00206747
# target 99.9% 0.002071
# Socket and IP used for each connection:
[0]   2 socket used, resolved to 10.96.133.65:8080, connection timing : count 2 avg 0.0002246525 +/- 3.423e-06 min 0.00022123 max 0.000228075 sum 0.000449305
[1]   3 socket used, resolved to 10.96.133.65:8080, connection timing : count 3 avg 0.000133789 +/- 2.3e-05 min 0.000114006 max 0.000166034 sum 0.000401367
[2]   5 socket used, resolved to 10.96.133.65:8080, connection timing : count 5 avg 0.0001611908 +/- 6.044e-05 min 0.000123245 max 0.000281703 sum 0.000805954
[3]   3 socket used, resolved to 10.96.133.65:8080, connection timing : count 3 avg 0.00023652667 +/- 9.899e-05 min 0.000139664 max 0.000372493 sum 0.00070958
Connection time histogram (s) : count 13 avg 0.00018201585 +/- 7.388e-05 min 0.000114006 max 0.000372493 sum 0.002366206
# range, mid point, percentile, count
>= 0.000114006 <= 0.000372493 , 0.000243249 , 100.00, 13
# target 50% 0.000232479
# target 75% 0.000302486
# target 90% 0.00034449
# target 99% 0.000369693
# target 99.9% 0.000372213
Sockets used: 13 (for perfect keepalive, would be 4)
Uniform: false, Jitter: false, Catchup allowed: true
IP addresses distribution:
10.96.133.65:8080: 13
Code 200 : 9 (45.0 %)
Code 503 : 11 (55.0 %)
Response Header Sizes : count 20 avg 175.5 +/- 194 min 0 max 390 sum 3510
Response Body/Total Sizes : count 20 avg 1233.7 +/- 1097 min 241 max 2447 sum 24674
All done 20 calls (plus 0 warmup) 2.237 ms avg, 1506.1 qps
root@server:~# 

This time, about half of the requests will be failing, as the circuit breaker is configured to only allow 2 concurrent connections and 1 pending request.

This configuration is an example of how a CiliumEnvoyConfig can be used to protect a service from a potential overload for example.

L7 Network Policy Enforcement with Envoy

As previously seen, when interpreting a Network Policy that contains both L3/L4 and L7 rules, Cilium creates eBPF programs to enforce at L3/L4, as well as Envoy listeners to implement the L7 rules.

L3/L4 rules then forward accepted traffic to Envoy for L7 enforcement, and Envoy either forwards traffic to its destination or replies with a 403 (Access denied) response.

 Setting a Listener

For advanced situations, It is possible to specify an Envoy listener as a Cilium Network Policy parameter to fully control how Envoy behaves once the L3/L4 enforcement level redirects traffic to it.

Forcing a L7 Proxy Redirection

In this challenge, we will make use of the Network Policy listener parameter to set up an Envoy listener sending traffic to an external L7 proxy.

Create namespace and application:
root@server:~# kubectl create ns proxy
namespace/proxy created
root@server:~# kubectl -n proxy run --image nicolaka/netshoot \
  proxy-client \
  --command sleep infinite
pod/proxy-client created
root@server:~# kubectl -n proxy get po proxy-client
NAME           READY   STATUS    RESTARTS   AGE
proxy-client   1/1     Running   0          15s

Then make a request to api.github.com:
root@server:~# kubectl -n proxy exec proxy-client -- \
  curl -s https://api.github.com/status | jq
{
  "message": "GitHub lives! (2024-08-12 00:17:57 -0700) (1)"
}


Check huuble logs:
root@server:~# hubble observe --from-pod proxy/proxy-client
Aug 12 07:18:00.217: proxy/proxy-client (ID:60265) <> kube-system/kube-dns:53 (world) pre-xlate-fwd TRACED (UDP)
Aug 12 07:18:00.217: proxy/proxy-client (ID:60265) <> kube-system/coredns-76f75df574-flqbm:53 (ID:2105) post-xlate-fwd TRANSLATED (UDP)
Aug 12 07:18:00.217: proxy/proxy-client:59494 (ID:60265) -> kube-system/coredns-76f75df574-flqbm:53 (ID:2105) to-overlay FORWARDED (UDP)
Aug 12 07:18:00.217: proxy/proxy-client:59494 (ID:60265) -> kube-system/coredns-76f75df574-flqbm:53 (ID:2105) to-endpoint FORWARDED (UDP)
Aug 12 07:18:00.217: proxy/proxy-client:59494 (ID:60265) <> kube-system/coredns-76f75df574-flqbm (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:18:00.217: proxy/proxy-client:59494 (ID:60265) <> kube-system/coredns-76f75df574-flqbm (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:18:00.218: proxy/proxy-client:59494 (ID:60265) <> kube-system/coredns-76f75df574-flqbm (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:18:00.218: proxy/proxy-client:59494 (ID:60265) <> kube-system/coredns-76f75df574-flqbm (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:18:00.218: proxy/proxy-client:59494 (ID:60265) <> kube-system/coredns-76f75df574-flqbm (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:18:00.218: proxy/proxy-client:59494 (ID:60265) <> kube-system/coredns-76f75df574-flqbm (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:18:00.218: proxy/proxy-client:59494 (ID:60265) <> kube-system/coredns-76f75df574-flqbm (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:18:00.218: proxy/proxy-client:59494 (ID:60265) <> kube-system/coredns-76f75df574-flqbm (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:18:00.218: proxy/proxy-client:59494 (ID:60265) <> kube-system/coredns-76f75df574-flqbm (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:18:00.218: proxy/proxy-client:59494 (ID:60265) <> kube-system/coredns-76f75df574-flqbm (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:18:00.220: proxy/proxy-client:59494 (ID:60265) <> kube-system/coredns-76f75df574-flqbm (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:18:00.220: proxy/proxy-client:59494 (ID:60265) <> kube-system/coredns-76f75df574-flqbm (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:18:00.222: proxy/proxy-client:59494 (ID:60265) <> kube-system/coredns-76f75df574-flqbm (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:18:00.222: proxy/proxy-client:59494 (ID:60265) <> kube-system/coredns-76f75df574-flqbm (ID:2105) pre-xlate-rev TRACED (UDP)
Aug 12 07:18:00.235: proxy/proxy-client:47888 (ID:60265) -> 140.82.121.6:443 (world) to-stack FORWARDED (TCP Flags: SYN)
Aug 12 07:18:00.243: proxy/proxy-client:47888 (ID:60265) -> 140.82.121.6:443 (world) to-stack FORWARDED (TCP Flags: ACK)
Aug 12 07:18:00.246: proxy/proxy-client:47888 (ID:60265) -> 140.82.121.6:443 (world) to-stack FORWARDED (TCP Flags: ACK, PSH)
Aug 12 07:18:00.275: proxy/proxy-client:47888 (ID:60265) -> 140.82.121.6:443 (world) to-stack FORWARDED (TCP Flags: ACK, FIN)
Aug 12 07:18:00.281: proxy/proxy-client:47888 (ID:60265) -> 140.82.121.6:443 (world) to-stack FORWARDED (TCP Flags: RST)
Aug 12 07:18:00.281: proxy/proxy-client:47888 (ID:60265) -> 140.82.121.6:443 (world) to-stack FORWARDED (TCP Flags: RST)
Aug 12 07:18:00.282: proxy/proxy-client:47888 (ID:60265) -> 140.82.121.6:443 (world) to-stack FORWARDED (TCP Flags: RST)
root@server:~# 

You will see the traffic going from the client to a world identity, represented by its IP address:

Mar  6 19:15:16.509: proxy/proxy-client:43602 (ID:1108) -> 140.82.121.5:443 (world) to-stack FORWARDED (TCP Flags: SYN)

The trace uses the to-stack viewpoint, not to-proxy, as the traffic does not —yet— go through Envoy.

Let's set up a web proxy on the lab's VM. We will use 3proxy as a Docker container running in the kind network, so it's accessible from the Kubernetes cluster:

root@server:~# docker run --rm -d \
  --net kind \
  --name proxy-server \
  -e "3128/tcp" \
  ghcr.io/tarampampam/3proxy:latest
Unable to find image 'ghcr.io/tarampampam/3proxy:latest' locally
latest: Pulling from tarampampam/3proxy
7b2699543f22: Pull complete 
27a91f50cc8f: Pull complete 
Digest: sha256:39e8f1e745290e9afccb0bee39058d4908e5781da4d4d11b48848b39080bf24c
Status: Downloaded newer image for ghcr.io/tarampampam/3proxy:latest
5afdc5fce7d5a55e8d96207b4d086b4741e46888004410f646858704493a3b3f

This proxy listens on ports 3128/TCP for HTTP traffic.

Wait for the container to start:
root@server:~# docker inspect --format '{{.State.Status}}' proxy-server
running
root@server:~# docker inspect proxy-server -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
172.18.0.5

Next, deploy an Envoy Config to set up the Envoy listener we will be using.

Using the </> Editor, open the file named proxy-cec.yaml and edit line 29 to replace <<PROXY_IP>> with the IP you just retrieved (which is usually 172.18.0.5).

Notice that this is a CEC (so it's namespaced) made of 2 resources:

    type.googleapis.com/envoy.config.listener.v3.Listener to set up a listener. This listener uses a TCP proxy, sending traffic to the downstream address via the Envoy dynamic variable %DOWNSTREAM_LOCAL_ADDRESS%
    type.googleapis.com/envoy.config.cluster.v3.Cluster which configures the behavior to send the traffic to the web proxy we just set up via its IP and the HTTP port 3128.

Once the file is saved, apply it in the >_ Terminal:
root@server:~# kubectl -n proxy apply -f proxy-cec.yaml
ciliumenvoyconfig.cilium.io/proxy-envoy created
Now, we need to deploy a Network Policy to force traffic into the Envoy Proxy if it passes an L3/L4 filter:
root@server:~# kubectl -n proxy apply -f proxy-cnp.yaml
ciliumnetworkpolicy.cilium.io/proxy-policy created

root@server:~# kubectl -n proxy get cnp proxy-policy -o yaml | yq .spec
egress:
  - toEntities:
      - cluster
  - toEndpoints:
      - matchLabels:
          io.kubernetes.pod.namespace: kube-system
          k8s-app: kube-dns
    toPorts:
      - ports:
          - port: "53"
            protocol: ANY
        rules:
          dns:
            - matchPattern: '*'
  - toFQDNs:
      - matchPattern: '*.github.com'
    toPorts:
      - listener:
          envoyConfig:
            kind: CiliumEnvoyConfig
            name: proxy-envoy
          name: proxy-listener
        ports:
          - port: "80"
            protocol: TCP
          - port: "443"
            protocol: TCP
endpointSelector: {}



This is an egress policy that:

    allows all requests inside the cluster without filtering (toEntities: [cluster])
    allow DNS requests to kube-system/kube-dns on port 53/UDP, and filters DNS request through the Cilium proxy
    allows HTTP (80/TCP) and HTTPS (443/TCP) traffic to DNS names matching *.github.com, and redirects this traffic through the proxy-envoy Envoy listener we previously deployed

Try the request again:

kubectl -n proxy exec proxy-client -- \
  curl -s https://api.github.com/status | jq

It should succeed just the same.
root@server:~# kubectl -n proxy exec proxy-client -- \
  curl -s https://api.github.com/status | jq
{
  "message": "GitHub lives! (2024-08-12 00:24:55 -0700) (1)"
}


Check the Hubble logs again:

root@server:~# kubectl -n proxy exec proxy-client -- \
  curl -s https://api.github.com/status | jq
{
  "message": "GitHub lives! (2024-08-12 00:24:55 -0700) (1)"
}

The DNS name "api.github.com" is now known because we're using the DNS proxy in the Network Policy, and you can see the request being first vetted against the L3/L4 network policy (policy-verdict:L3-L4 EGRESS ALLOWED), then redirected to the Envoy proxy (to-proxy FORWARDED).

Check the proxy logs:

root@server:~# docker logs proxy-server
/bin/3proxy: Starting 3proxy
{"time_unix":1723447167, "proxy":{"type:":"PROXY", "port":3128}, "error":{"code":"00000"}, "auth":{"user":"-"}, "client":{"ip":"0.0.0.0", "port":3128}, "server":{"ip":"0.0.0.0", "port":0}, "bytes":{"sent":0, "received":0}, "request":{"hostname":"[0.0.0.0]"}, "message":"Accepting connections [7/2786682560]"}
{"time_unix":1723447167, "proxy":{"type:":"SOCKS", "port":1080}, "error":{"code":"00000"}, "auth":{"user":"-"}, "client":{"ip":"0.0.0.0", "port":1080}, "server":{"ip":"0.0.0.0", "port":0}, "bytes":{"sent":0, "received":0}, "request":{"hostname":"[0.0.0.0]"}, "message":"Accepting connections [7/2786629312]"}
{"time_unix":1723447489, "proxy":{"type:":"PROXY", "port":3128}, "error":{"code":"00000"}, "auth":{"user":"-"}, "client":{"ip":"172.18.0.2", "port":56720}, "server":{"ip":"140.82.121.6", "port":443}, "bytes":{"sent":789, "received":4780}, "request":{"hostname":"140.82.121.6"}, "message":"CONNECT 140.82.121.6:443 HTTP/1.1"}
{"time_unix":1723447503, "proxy":{"type:":"PROXY", "port":3128}, "error":{"code":"00000"}, "auth":{"user":"-"}, "client":{"ip":"172.18.0.2", "port":50446}, "server":{"ip":"140.82.121.5", "port":443}, "bytes":{"sent":789, "received":4781}, "request":{"hostname":"140.82.121.5"}, "message":"CONNECT 140.82.121.5:443 HTTP/1.1"}


You will see that the request went through the proxy, and was sent to the IP address you saw earlier in the Hubble logs:

{"time_unix":1709752901, "proxy":{"type:":"PROXY", "port":3128}, "error":{"code":"00000"}, "auth":{"user":"-"}, "client":{"ip":"172.18.0.2", "port":33824}, "server":{"ip":"140.82.121.6", "port":443}, "bytes":{"sent":789, "received":4102}, "request":{"hostname":"140.82.121.6"}, "message":"CONNECT 140.82.121.6:443 HTTP/1.1"}

The client IP is the IP address of the node on which the client pod is running (since it is used to source NAT the traffic when exiting the Kubernetes cluster in VXLAN mode).

Verify that it is not possible to access google.com with this setup, as intended by the Network Policy:
root@server:~# kubectl -n proxy exec proxy-client --   curl -s --max-time 1 https://google.com
command terminated with exit code 28

root@server:~# hubble observe --from-pod proxy/proxy-client --to-fqdn google.com
Aug 12 07:26:30.126: proxy/proxy-client:33850 (ID:60265) <> google.com:443 (world) policy-verdict:none EGRESS DENIED (TCP Flags: SYN)
Aug 12 07:26:30.126: proxy/proxy-client:33850 (ID:60265) <> google.com:443 (world) Policy denied DROPPED (TCP Flags: SYN)
Aug 12 07:26:30.623: proxy/proxy-client:34950 (ID:60265) <> google.com:443 (world) policy-verdict:none EGRESS DENIED (TCP Flags: SYN)
Aug 12 07:26:30.623: proxy/proxy-client:34950 (ID:60265) <> google.com:443 (world) Policy denied DROPPED (TCP Flags: SYN)
root@server:~# 

 Debugging Envoy

Since Envoy configurations can be quite complex, it can be useful to get access to its logs and configuration.

We will explore these in this challenge.

As we have seen in a previous challenge, one first step to simplify access to Envoy logs is to deploy as it as a separate DaemonSet (which will be the default behavior in Cilium 1.16+).

Starting with Cilium 1.16, it will become easy to access the Envoy Admin UI in Cilium.

Upgrade the chart to enabled the Envoy Admin UI:
helm -n kube-system upgrade cilium cilium/cilium \
  --version 1.16.0 \
  --reuse-values \
  --set envoy.debug.admin.enabled=true \
  --set envoy.debug.admin.port=9901

This will configure Envoy on each node to serve its admin UI on port 9901.

We will then be able to access it either on the host port or via port forwarding.

For practical reasons, we will use that second option in this lab.
Let's inspect the Envoy proxy on the node where the proxy-client pod we previously deployed is running.

First, retrieve the node name for that pod:
root@server:~# CLIENT_NODE=$(kubectl -n proxy get po proxy-client -o jsonpath='{.spec.nodeName}')
echo $CLIENT_NODE
kind-worker2
root@server:~# cilium status --wait
    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    OK
 \__/¯¯\__/    Hubble Relay:       OK
    \__/       ClusterMesh:        disabled

Next, get the name of the Envoy pod running on that node:
root@server:~# ENVOY_POD=$(kubectl -n kube-system get po -l k8s-app=cilium-envoy --field-selector spec.nodeName=$CLIENT_NODE -o name)
echo $ENVOY_POD
pod/cilium-envoy-q2tf6
Finally, port-forward the 9901 port to localhost for that pod. Expose it to 0.0.0.0 so we can access it in the browser:
root@server:~# kubectl -n kube-system port-forward --address 0.0.0.0 $ENVOY_POD 9901
Forwarding from 0.0.0.0:9901 -> 9901
Handling connection for 9901
Handling connection for 9901

You can now head to the 🔗 Envoy Admin UI tab to visualize the Envoy Admin UI (refresh it if necessary).

Scroll down and click on the listeners link. You will get a list of all configured listeners in this lab:
envoy-prometheus-metrics-listener::0.0.0.0:9964
envoy-admin-listener::127.0.0.1:9901
envoy-health-listener::127.0.0.1:9878
/envoy-circuit-breaker/envoy-lb-listener::127.0.0.1:11326
proxy/proxy-envoy/proxy-listener::127.0.0.1:11698
cilium-http-ingress:13012::127.0.0.1:13012
grpc/currencyservice::127.0.0.1:14107


Press the ⬅️ button in your browser to go back to the admin interface.

Scroll up to the config_dump section, enter .*proxy-envoy.* in the third field (Dump only the currently loaded configurations whose names match the specified regex.) then press enter. You will see generated Envoy configurations for the previous challenge.

Go back and explore some other options in the Admin UI, then head to the final quiz!




For this exam challenge, you will need to implement an HTTP load-balancer with weighed services, protected by a L3/L4 network policy.

In the exam namespace, several pods have been deployed:

    3 deathstar pods (labeled org=empire, class=deathstar) with a matching deathstar service
    3 darkstar pods (labeled org=empire, class=darkstar) with a matching darkstar service
    a tiefighter pod (labeled org=empire, class=tiefighter)
    an xwing pod (labeled org=alliance, class=xwing)

Additionally, a dns Cilium Network Policy was deployed to allow egress access to kube-system/kube-dns to all pods in the namespace.

In order to pass this exam, your task is to:

    set up an egress Cilium Network Policy named empire-to-deathstar which:
        applies to all imperial vessels (labeled org=empire)
        gives access to both Death Star and Dark Star pods (using a matchExpressions filter) on port 80/TCP
        redirects to the deathstar-lb CiliumEnvoyConfig, using the lb-listener listener
    set up a Cilium Envoy Config named deathstar-lb which performs L7 weighed load-balancing to two services:
        deathstar for 80% of the requests
        darkstar for 20% of the requests

Exam challenge diagram

    Note

        You will find sample manifests in the exam/ directory
        Replace the placeholder values marked with multiple letters such as AA, BB, XXXXXX, YYYYYY, CCCCCC, PP, QQ, etc. with the proper values
        You can use the </> Editor to edit the files
        Don't forget to apply the manifests!
        Don't forget to specify the namespace when applying manifests!

Once you are done configuring and applying the manifests, you can check your configuration by running 100 requests from the Tie Fighter pod to the Death Star service:
shell

for i in $(seq 1 100); do
  kubectl -n exam exec deploy/tiefighter -- \
    curl --max-time 1 -s deathstar.exam.svc.cluster.local/v1/ | \
      jq -r .hostname
done > stars.logs

Then check the occurrence of each type of pod:
shell

cat stars.logs  | cut -d'-' -f1 | sort | uniq -c

You should get approximately a 80/20 ratio.

You can also verify that the X-Wing pod (which is not labeled with org=empire) has no access to the Death Star service by checking that requests from it get dropped:
shell

kubectl -n exam exec deploy/xwing -- \
    curl --max-time 1 -s deathstar.exam.svc.cluster.local/v1/
