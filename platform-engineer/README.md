his short lab will introduce you to the Cilium and Hubble features particularly relevant for Platform Engineering teams.

In particular, you will learn about:

    Cilium Ingress Controller
    Gateway API
    Connectivity Visibility with Hubble
    Golden Signals monitoring of your applications


Kubernetes Workload Traffic

In this practical lab session, we'll demonstrate how Cilium offers Load Balancing, Kubernetes Ingress and Gateway API for workload traffic access and management.

We'll showcase how the different resource types provide access to your workloads, and the features needed to secure them.

Cilium helps you implement robust security measures which are essential in guarding against data breaches, unauthorized access, and various potential risks.

Kubernetes Troubleshooting with Hubble and Grafana

As a second focus area, we will demonstrate how Cilium and Hubble can provide Kubernetes Troubleshooting direct from the platform, looking at some common network issues caused by misconfigurations.

Furthermore, dive into application metrics provided by Cilium and Hubble without the need to rewrite the application, with visualizations provided by popular open-source tooling, Grafana.

Check cilium is up and running:
cilium status --wait

Your task, as an Imperial officer specialized in inter-galactic platforms, is to set up communications between the Darth Vader's new space station, the Death Star and the Imperial fleet, and monitor the health of these resources.

The endor.yaml manifest will deploy a Star Wars-inspired demo application which consists of:

    an endor Namespace, containing
    a deathstar Deployment with 1 replicas.
    a Kubernetes Service to access the Death Star pods
    a tiefighter Deployment with 1 replica
    an xwing Deployment with 1 replica

Check the deployments with:
kubectl get -f endor.yaml

Switch to the 🔗 🛰️ Hubble UI tab, a project that is part of the Cilium realm, which lets you visualize traffic in a Kubernetes cluster as a service map.

Select the endor namespace.

You will see these three identities represented in the service map:

    xwing is for pods from the xwing deployment
    tiefighter represents pods from the tiefighter deployment
    deathstar represents the various pods deployed by the deathstar deployment

Both the tiefighter and xwing pods make requests to:

    the deathstar service (HTTP)
    disney.com and swapi.dev (HTTPS)

The domain names for disney.com and swapi.dev are known by Hubble because Cilium has been configured to proxy DNS traffic and cache the DNS responses from Kube DNS, providing a way to both inspect and secure traffic by DNS name.

Click on the xwing box in the service map. This filters traffic to only show flows involving the xwing identity.

Observe that all flows end with a red section, indicating that traffic coming from the xwing identity is being dropped.

You can also see at the bottom of the screen all the flow logs confirming that communications coming from the xwing identity are dropped.

This is because the endor namespace has been secured with Network Policies, allowing only specific traffic.

Click on the deathstar box. You can see that traffic is coming to the deathstar identity from two pods identities: xwing and tiefighter.

Note that the box tells you that traffic coming to the deathstar pods is entirely on port 80/TCP and HTTP traffic.

You can even see that the /v1/request-landing HTTP path was called, using the POST method!

This is because the deathstar pods have an associated layer 7 Cilium Network Policies to enable this capability.

Click on the tiefighter box. All logs at the bottom of the screen are green, indicating that traffic is allowed and forwarded to the three destinations.

Providing external Access

Darth Vader wants to expose the Death Star externally so it can be accessed by the world.

We will walk through a number of options including a load balancer service, Kubernetes Ingress and the new Gateway API features, a new standard to manage traffic to your Kubernetes cluster.

Load Balancer with Layer 2 Advertisements

To make the Death Star accessible, we will configure a Kubernetes service type Load Balancer.

This is one of the most common configurations, but typically requires external components from a cloud provider. With Cilium these features are part of the platform removing the need to rely on specific cloud provider features.

Kubernetes Ingress and Gateway API

Cilium comes with a Kubernetes Ingress Controller out-of-the-box.

This provides the ability to configure L7 north-south load-balancing without a plugin, as well as typical Ingress features such as TLS Termination.

Gateway API is the new standard to manage L7 vertical load balancing in Kubernetes. Cilium provides several Gateway API resources to enable fine-grained L7 logic for external workload access.


The Empire would like the Death Star to be accessible from the outside of the Kubernetes cluster.

The first option to expose a service to the world is to use a standard Kubernetes Service resource, with a type LoadBalancer.

This usually requires to run on a Cloud Provider that will automatically provision an external L4 load balancer and point it to the Kubernetes nodes using a dynamic NodePort.

Our cluster cannot benefit from dynamic external load balancer provisioning, so are we stuck?

Actually, Cilium can provide both the load balancer IP (using the LB-IPAM feature) as well as announce it to the network using either BGP or ARP.

Since we don't have a BGP peering in place, we've used ARP and let the host machine learn how to access the service via L2.

Check the service with:
root@server:~# kubectl -n endor get svc deathstar
NAME        TYPE           CLUSTER-IP    EXTERNAL-IP      PORT(S)        AGE
deathstar   LoadBalancer   10.96.57.70   172.18.255.201   80:30441/TCP   26m

LB-IPAM has provisioned an IP address for this service. Access it with:
root@server:~# curl -s http://172.18.255.201/v1/
{
        "name": "Death Star",
        "hostname": "deathstar-b4b8ccfb5-qhplw",
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

Success!

Switch back to the 🔗 🛰️ Hubble UI tab and click on the deathstar box.

Notice traffic is now reaching the Death Star from the world identity. This is because we accessed the service from outside of the cluster.

Darth Vader is not satisfied with the L4 Load Balancer, because it uses HTTP instead of HTTPS!

Short of rethinking the Death Star to support HTTPS natively, you need to provide TLS termination without modifying the Death Star's code.

As a Platform Engineer, you know that the standard solution for this in Kubernetes is to use an Ingress resource. However, this means deploying an Ingress Controller to the cluster, and setting it up!

Fortunately, Cilium already comes with an Ingress controller out-of-the-box!

We've deployed an Ingress resource to access the Death Star, and we will secure the access using a certificate for *.cilium.rocks.

In the >_ Terminal tab, inspect the Ingress with:

kubectl -n endor get ingress deathstar -o yaml | yq '.spec'

Note that it uses the built-in cilium Ingress class.

Test access to the Deathstar using the below command:
root@server:~# curl -s \
  --resolve deathstar.cilium.rocks:443:172.18.255.200 \
  https://deathstar.cilium.rocks/v1/
{
        "name": "Death Star",
        "hostname": "deathstar-b4b8ccfb5-qhplw",
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

It works, and Darth Vader is not going to choke us (just yet) 😌

Get back to the 🔗 🛰️ Hubble UI tab. And click on the Death Star box, if it is not already selected.

The Death Star service is now being accessed by the ingress identity. This is a special identity that Cilium uses to identify L7-proxied ingress. You can also see which HTTP path was accessed by the ingress, thanks to Cilium L7 observability.


K8s Gateway API:
After the first Death Star exploded, Darth Vader decided to design a new model without the security flaw that allowed its demise.

In order to be on the safe side, he would like to perform A/B testing on the next Death Star.

If you're familiar with Ingress controllers, you know that weighed load balancing is not a core feature of the specification. Many Ingress controller projects implement their own annotations, or even CRDs, to bypass such limitations.

For the last few years, the Kubernetes developers have been working on the next generation of L7 routing specification which would address such features. It is called Gateway API, and you can essentially think of it as Ingress v2.

And thankfully for us, Gateway API is already stable (just announced), and supported by Cilium out-of-the-box!

There's other benefits to Gateway API for Platform Engineers. In particular, it cleanly separates concerns and responsibilities between platform engineering and platform users, by providing both infrastructure resources (Gateway) and user resources (HTTPRoute, TLSRoute, etc.).

We've deployed a Gateway resource, along with an HTTPRoute resource for the Death Star service, providing access to the new Death Star for 1% of the requests.

In the >_ Terminal tab, inspect the Gateway with:
kubectl -n endor get gateway tls-gateway

Just like before, it has been assigned an IP address by Cilium LB-IPAM.

Inspect the Gateway's details:
kubectl -n endor get gateway tls-gateway -o yaml | yq '.spec'

Notice that:

    the gatewayClassName is the built-in Cilium controller
    the Gateway is configured for HTTPS, so all resources attached to it will use the hosts and certificate

Deploy the HTTPRoute:
kubectl apply -f http-route991.yaml
kubectl -n endor get httproute deathstar -o yaml | yq '.spec'

It is attached to the TLS Gateway, uses the deathstar.cilium.rocks hostname for TLS termination, and targets two services: the deathstar service 99% of the time, and the deathstar2 service 1% of the time.

Access the service with:
curl -s \
  --resolve deathstar.cilium.rocks:443:172.18.255.202 \
  https://deathstar.cilium.rocks/v1/

Repeat the request a few times and note the changes in the hostname field. You should see the reply coming essentially from the deathstar pod.

Let's double check that traffic is evenly split across multiple Pods by running a loop and counting the requests (this will take a few seconds):

for _ in {1..200}; do
  curl -s \
    --resolve deathstar.cilium.rocks:443:172.18.255.202 \
    https://deathstar.cilium.rocks/v1/ | \
    jq '.hostname' >> curlresponses.txt
done

We can count the requests to each pod using the below command:
grep -c 'deathstar-' curlresponses.txt => 196
grep -c 'deathstar2-' curlresponses.txt => 4

The old Death Star is receiving 99 requests for 1 request to the new Death Star. Once we are happy that the new service is working as expected, we can update the httproute configuration direct more traffic to the new service.

In the 🔗 🛰️ Hubble UI tab, notice that the ingress identity is still the one used to access the Death Star. This identity is used for both Ingress and Gateway API resources, and it uses the same Envoy proxy mechanism under the hood.

Troubleshooting Kubernetes with Hubble and Grafana

In this task, you will start visualizing Hubble metrics on a Grafana dashboard for our application. We will use the available out-of-the box metrics to trouble communication issues with our Tiefighters.

Finally we'll view application specific metrics that are provided by Cilium and Hubble to platform owners and application owners without any reconfiguration, side cars or agents needed for the application itself.

Emperor Palpatine has ordered that the Imperial fleet resources should be easy to monitor with the existing tools. Reporting on the communications to the Death Star is considered most important.

In this lab, we have set up a Grafana server with a data source pointing to Prometheus and imported the L7 HTTP metrics Dashboard to visualize Hubble related metrics. This is configured via the Helm values used in the Cilium install.

Disaster! Tiefighters are unable to communicate with resources outside of the Death Star, something has started to block communications.

Imperial headquarters are contacting you to sort this tout. Type the following in the >_ Terminal tab to take the communication:
starcom --interactive

Using the 🔗 📈 Grafana - Network Overview dashboard, we can check quickly if there is a change in flows types and verdicts. Answering questions such as has a recent policy change caused the issue, are there connectivity issues, and which resources are the top consumers.

At the bottom of the page, we can see from the last graph "Network Policy Drops by Source", that the policy verdict metric has not dramatically increased since the beginning of this lab session.

This shows us that the issues reported are probably not related to a policy change.

We know the reported issue is related to communication to outside resources.

Go to the 🔗 📈 Grafana - DNS tab, which takes us to the Hubble DNS metrics.

You should now see a sharp drop in the first left-hand graph "DNS - Queries".
So now we can tell that name resolution is failing. This is also correlated with an ingress in the "Missing DNS Responses" Graph under it.

Eventually if we wait long enough, we'll even see "DNS Errors" logged too.

With this information we can now start to pinpoint the particular issue. We can see this is a resolution issue, and we know that this is for resources outside of the cluster. Let's inspect the traffic using the Hubble CLI, filtering on traffic from CoreDNS, which is used for name resolution in the cluster.

In the >_ Terminal tab, run this command to see the traffic from CoreDNS to the outside external DNS servers for external lookup:
root@server:~# hubble observe --from-pod kube-system/coredns --to-identity world
Aug  7 21:42:30.171: kube-system/coredns-76f75df574-c2vw9:37049 (ID:46357) -> 1.2.3.4:53 (world) to-stack FORWARDED (UDP)
Aug  7 21:42:30.258: kube-system/coredns-76f75df574-d8jcn:56964 (ID:46357) -> 1.2.3.4:53 (world) to-stack FORWARDED (UDP)
Aug  7 21:42:30.258: kube-system/coredns-76f75df574-d8jcn:40617 (ID:46357) -> 1.2.3.4:53 (world) to-stack FORWARDED (UDP)
Aug  7 21:42:30.543: kube-system/coredns-76f75df574-c2vw9:51831 (ID:46357) -> 1.2.3.4:53 (world) to-stack FORWARDED (UDP)

We can now see that external DNS resolution from CoreDNS is going to 1.2.3.4, which is not a DNS server.

Let's fix the issue by replacing the IP address 1.2.3.4 with the correct DNS server 8.8.8.8 in the CoreDNS configuration:
root@server:~# kubectl -n kube-system edit configmap/coredns
configmap/coredns edited
root@server:~# kubectl -n kube-system get configmap/coredns -oyaml
apiVersion: v1
data:
  Corefile: |
    .:53 {
        errors
        health {
           lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        prometheus :9153
        forward . 8.8.8.8 {
           max_concurrent 1000
        }
        cache 30
        loop
        reload
        loadbalance
    }
kind: ConfigMap
metadata:
  creationTimestamp: "2024-08-07T20:45:09Z"
  name: coredns
  namespace: kube-system
  resourceVersion: "25047"
  uid: 19c65e3c-68c4-49cf-be24-783198d18bfa

Find the line with 1.2.3.4, change it to 8.8.8.8, then save and quit the editor (with Esc+:x).

Restart CoreDNS, so that the change can take effect:
kubectl -n kube-system rollout restart deploy coredns

Rerun the command to check that CoreDNS is now resolving addresses against the correct External DNS Server.
hubble observe --from-pod kube-system/coredns --to-identity world
Aug  7 21:45:00.265: kube-system/coredns-76f75df574-d8jcn:46894 (ID:46357) -> 8.8.8.8:53 (world) to-stack FORWARDED (UDP)
Aug  7 21:45:21.061: kube-system/coredns-58486f598b-dx6z8:54373 (ID:46357) -> 8.8.8.8:53 (world) to-stack FORWARDED (UDP)
Aug  7 21:45:21.556: kube-system/coredns-58486f598b-4h2cd:47498 (ID:46357) -> 8.8.8.8:53 (world) to-stack FORWARDED (UDP)
Aug  7 21:45:22.134: kube-system/coredns-58486f598b-4h2cd:51848 (ID:46357) -> 8.8.8.8:53 (world) to-stack FORWARDED (UDP)
Aug  7 21:45:25.347: kube-system/coredns-58486f598b-dx6z8:41059 (ID:46357) -> 8.8.8.8:53 (world) to-stack FORWARDED (UDP)

Now let's see the metrics that are available from Cilium and Hubble for the application teams who will be using your platform.
Go to the 🔗 📈 Grafana - L7 Metrics tab.

Everything in the dashboard is using the Hubble HTTP metrics, without any instrumentation required from the application, and without anything being injected into the application.

s a platform engineer you may not find yourself investigating these types of metrics often, however with Cilium this level of data is available to your application teams with a simple configuration!

Notice how you now have access to a wide variety of HTTP metrics:

    Incoming Request Volume
    Incoming Request Success Rate
    Request Duration
    Requests by Response Code

Notice how you can see the metrics by source (second section, Requests by Source, with three panels) or by destination (third section, Requests by Destination, with three panels). This would enable you to find where the anomaly resides.

In the Requests by Source section, check the HTTP Request Duration by Source. Notice there are several statistics available: P50, P95 and P99. We usually describe latency with its 99th percentile, or P99.

If our HTTP-based web application has a P99 latency of less than or equal to 2 milliseconds, then it mean that 99% of web calls are serviced with a response under 2 milliseconds. Conversely, only 1% of calls get a delayed response of over 2 milliseconds.

In Summary to wrap up the Cilium and Hubble features covered in this discovery lab for platform engineers, we covered the following:

    Deployed an application workload
    Configured secure ingress and gateway for incoming traffic using the new Kubernetes standard on routing traffic to your resources.
    Test the traffic management features of the secure gateway to change the traffic balancing behaviour to our highly available workloads.
    Understand the application workload service map and view communications between workloads as well as visibility at Layer 7 such as HTTP Request Paths.
    Dive into observability features using Cilium, Hubble and Grafana together, to assist Kubernetes network troubleshooting.


