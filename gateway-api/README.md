Cilium Gateway API

Your lab environment is currently being set up. Stay tuned!

In the meantime, let's review what we will go through today:

    Cilium Installation with Gateway API
    HTTP Traffic Management with Gateway API
    HTTPS Traffic Management with Gateway API
    TLS Passthrough with Gateway API
    HTTP Load Balancing with Gateway API

Resilient Connectivity

Service to service communication must be possible across boundaries such as clouds, clusters, and premises. Communication must be resilient and fault tolerant.

Embedded Envoy Proxy

Cilium already uses Envoy for L7 policy and observability for some protocols, and this same component is used as the sidecar proxy in many popular Service Mesh implementations.

So it's a natural step to extend Cilium to offer more of the features commonly associated with Service Mesh —though contrary to other solutions, without the need for any pod sidecars.

Instead, this Envoy proxy is embedded with Cilium, which means that only one Envoy container is required per node.
eBPF acceleration

In a typical Service Mesh, all network packets need to pass through a sidecar proxy container on their path to or from the application container in a Pod.

This means each packet traverses the TCP/IP stack three times before even leaving the Pod.

Before we can install Cilium with the Gateway API feature, there are a couple of important prerequisites to know:

    Cilium must be configured with kubeProxyReplacement set to true.

    CRD (Custom Resource Definition) from Gateway API must be installed beforehand.

As part of the lab deployment script, several CRDs were installed. Verify that they are available.

root@server:~# kubectl get crd \
  gatewayclasses.gateway.networking.k8s.io \
  gateways.gateway.networking.k8s.io \
  httproutes.gateway.networking.k8s.io \
  referencegrants.gateway.networking.k8s.io \
  tlsroutes.gateway.networking.k8s.io
NAME                                        CREATED AT
gatewayclasses.gateway.networking.k8s.io    2024-08-13T08:01:59Z
gateways.gateway.networking.k8s.io          2024-08-13T08:01:59Z
httproutes.gateway.networking.k8s.io        2024-08-13T08:02:00Z
referencegrants.gateway.networking.k8s.io   2024-08-13T08:02:00Z
tlsroutes.gateway.networking.k8s.io         2024-08-13T08:02:00Z

During the lab deployment, Cilium was installed using the following command:
cilium install --version v1.16.0 \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set gatewayAPI.enabled=true \


Let's have a look at our lab environment and see if Cilium has been installed correctly. The following command will wait for Cilium to be up and running and report its status:
root@server:~# cilium status --wait
    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    OK
 \__/¯¯\__/    Hubble Relay:       disabled
    \__/       ClusterMesh:        disabled

Deployment             cilium-operator    Desired: 1, Ready: 1/1, Available: 1/1
DaemonSet              cilium-envoy       Desired: 3, Ready: 3/3, Available: 3/3
DaemonSet              cilium             Desired: 3, Ready: 3/3, Available: 3/3
Containers:            cilium             Running: 3
                       cilium-operator    Running: 1
                       cilium-envoy       Running: 3
Cluster Pods:          3/3 managed by Cilium
Helm chart version:    
Image versions         cilium             quay.io/cilium/cilium:v1.16.0@sha256:46ffa4ef3cf6d8885dcc4af5963b0683f7d59daa90d49ed9fb68d3b1627fe058: 3
                       cilium-operator    quay.io/cilium/operator-generic:v1.16.0@sha256:d6621c11c4e4943bf2998af7febe05be5ed6fdcf812b27ad4388f47022190316: 1
                       cilium-envoy       quay.io/cilium/cilium-envoy:v1.29.7-39a2a56bbd5b3a591f69dbca51d3e30ef97e0e51@sha256:bd5ff8c66716080028f414ec1cb4f7dc66f40d2fb5a009fff187f4a9b90b566b: 3

Verify that Cilium was enabled and deployed with the Gateway API feature:
root@server:~# cilium config view | grep -w "enable-gateway-api"
enable-gateway-api                                true
enable-gateway-api-alpn                           false
enable-gateway-api-app-protocol                   false
enable-gateway-api-proxy-protocol                 false
enable-gateway-api-secrets-sync                   true


If the CRDs have been deployed beforehand, a GatewayClass will be deployed by Cilium during its installation (assuming the Gateway API option has been selected).

Let's verify that a GatewayClass has been deployed and accepted:
root@server:~# kubectl get GatewayClass
NAME     CONTROLLER                     ACCEPTED   AGE
cilium   io.cilium/gateway-controller   True       6m6s

The GatewayClass is a type of Gateway that can be deployed: in other words, it is a template. This is done in a way to let infrastructure providers offer different types of Gateways. Users can then choose the Gateway they like.

For instance, an infrastructure provider may create two GatewayClasses named internet and private to reflect Gateways that define Internet-facing vs private, internal applications.

In our case, the Cilium Gateway API (io.cilium/gateway-controller) will be instantiated.

This schema below represents the various components used by Gateway APIs. When using Ingress, all the functionalities were defined in one API. By deconstructing the ingress routing requirements into multiple APIs, users benefit from a more generic, flexible and role-oriented model.

The actual L7 traffic rules are defined in the HTTPRoute API.

In the next challenge, you will deploy an application and set up GatewayAPI HTTPRoutes to route HTTP traffic into the cluster.


The bookinfo Application

In this challenge, we will use bookinfo as a sample application.

This demo set of microservices provided by the Istio project consists of several deployments and services:

    🔍 details
    ⭐ ratings
    ✍ reviews
    📕 productpage

We will use several of these services as bases for our Gateway APIs

We need a Load Balancer

The Cilium Service Mesh Gateway API Controller requires the ability to create LoadBalancer Kubernetes services.

Since we are using Kind on a Virtual Machine, we do not benefit from an underlying Cloud Provider's load balancer integration.

For this lab, we will use Cilium's own LoadBalancer capabilities to provide IP Address Management (IPAM) and Layer 2 announcement of IP addresses assigned to LoadBalancer services.

You can check the Cilium LoadBalancer IPAM and L2 Service Announcement lab to learn more about it.


Let's deploy the sample application in the cluster.
root@server:~# kubectl apply -f /opt/bookinfo.yml
service/details created
serviceaccount/bookinfo-details created
deployment.apps/details-v1 created
service/ratings created
serviceaccount/bookinfo-ratings created
deployment.apps/ratings-v1 created
service/reviews created
serviceaccount/bookinfo-reviews created
deployment.apps/reviews-v1 created
deployment.apps/reviews-v2 created
deployment.apps/reviews-v3 created
service/productpage created
serviceaccount/bookinfo-productpage created
deployment.apps/productpage-v1 created

You can find more details about the Bookinfo application on the Istio website.

Check that the application is properly deployed:
root@server:~# kubectl get pods
NAME                             READY   STATUS    RESTARTS   AGE
details-v1-65599dcf88-98r9n      1/1     Running   0          23s
productpage-v1-9487c9c5b-7ntbv   1/1     Running   0          23s
ratings-v1-59b99c644-nxtxw       1/1     Running   0          23s
reviews-v1-5985998544-q68tw      1/1     Running   0          23s
reviews-v2-86d6cc668-npzlv       1/1     Running   0          23s
reviews-v3-dbb5fb5dd-m8hps       1/1     Running   0          23s

You should see multiple pods being deployed in the default namespace. Wait until they are Running (should take 30 to 45 seconds).

Notice that with Cilium Service Mesh there is no Envoy sidecar created alongside each of the demo app microservices. With a sidecar implementation the output would show 2/2 READY: one for the microservice and one for the Envoy sidecar.

Have a quick look at the Services deployed:
root@server:~# kubectl get svc
NAME          TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
details       ClusterIP   10.96.150.71    <none>        9080/TCP   53s
kubernetes    ClusterIP   10.96.0.1       <none>        443/TCP    164m
productpage   ClusterIP   10.96.63.210    <none>        9080/TCP   53s
ratings       ClusterIP   10.96.235.251   <none>        9080/TCP   53s
reviews       ClusterIP   10.96.226.85    <none>        9080/TCP   53s

Note these Services are only internal-facing (ClusterIP) and therefore there is no access from outside the cluster to these Services.
Let's deploy the Gateway with the following manifest:

root@server:~# kubectl apply -f basic-http.yaml
gateway.gateway.networking.k8s.io/my-gateway created
httproute.gateway.networking.k8s.io/http-app-1 created


First, note in the Gateway section that the gatewayClassName field uses the value cilium. This refers to the Cilium GatewayClass previously configured.

The Gateway will listen on port 80 for HTTP traffic coming southbound into the cluster. The allowedRoutes is here to specify the namespaces from which Routes may be attached to this Gateway. Same means only Routes in the same namespace may be used by this Gateway.

Note that, if we were to use All instead of Same, we would enable this gateway to be associated with routes in any namespace and it would enable us to use a single gateway across multiple namespaces that may be managed by different teams.

We could specify different namespaces in the HTTPRoutes – therefore, for example, you could send the traffic to https://acme.com/payments in a namespace where a payment app is deployed and https://acme.com/ads in a namespace used by the ads team for their application.

Let's now review the HTTPRoute manifest. HTTPRoute is a GatewayAPI type for specifiying routing behaviour of HTTP requests from a Gateway listener to a Kubernetes Service.

It is made of Rules to direct the traffic based on your requirements.

This first Rule is essentially a simple L7 proxy route: for HTTP traffic with a path starting with /details, forward the traffic over to the details Service over port 9080.
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /details
    backendRefs:
    - name: details
      port: 9080

The second rule is similar but it's leveraging different matching criteria. If the HTTP request has:

    a HTTP header with a name set to magic with a value of foo, AND
    the HTTP method is "GET", AND
    the HTTP query param is named great with a value of example, Then the traffic will be sent to the productpage service over port 9080.

rules:
  - matches:
   - headers:
      - type: Exact
        name: magic
        value: foo
      queryParams:
      - type: Exact
        name: great
        value: example
      path:
        type: PathPrefix
        value: /
      method: GET
    backendRefs:
    - name: productpage
      port: 9080


As you can see, you can deploy sophisticated L7 traffic rules that are consistent (with Ingress API, annotations were often required to achieve such routing goals and that created inconsistencies from one Ingress controller to another).

One of the benefits of these new APIs is that the Gateway API is essentially split into separate functions – one to describe the Gateway and one for the Routes to the back-end services. By splitting these two functions, it gives operators the ability to change and swap gateways but keep the same routing configuration.

In other words: if you decide you want to use a different Gateway API controller instead, you will be able to re-use the same manifest.

Let's have another look at the Services now that the Gateway has been deployed:
root@server:~# kubectl get svc
NAME                        TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)        AGE
cilium-gateway-my-gateway   LoadBalancer   10.96.101.227   172.18.255.200   80:30297/TCP   6m37s
details                     ClusterIP      10.96.150.71    <none>           9080/TCP       8m40s
kubernetes                  ClusterIP      10.96.0.1       <none>           443/TCP        172m
productpage                 ClusterIP      10.96.63.210    <none>           9080/TCP       8m40s
ratings                     ClusterIP      10.96.235.251   <none>           9080/TCP       8m40s
reviews                     ClusterIP      10.96.226.85    <none>           9080/TCP       8m40s

You will see a LoadBalancer service named cilium-gateway-my-gateway which was created for the Gateway API.
When Cilium was installed during the boot-up of the lab, it was enabled with LoadBalancer capabilities. Cilium will therefore automatically provision an IP address for it and announce this IP address over Layer 2 locally (which is how connectivity from your terminal to the Gateway IP address will be achieved).

If you would like to explore this functionality, try out the L2 Announcement lab.

The same external IP address is also associated to the Gateway:
root@server:~# kubectl get gateway
NAME         CLASS    ADDRESS          PROGRAMMED   AGE
my-gateway   cilium   172.18.255.200   True         8m20s
root@server:~# GATEWAY=$(kubectl get gateway my-gateway -o jsonpath='{.status.addresses[0].value}')
echo $GATEWAY
172.18.255.200

Let's now check that traffic based on the URL path is proxied by the Gateway API.

Check that you can make HTTP requests to that external address:
Because the path starts with /details, this traffic will match the first rule and will be proxied to the details Service over port 9080.

The curl request should be successful and return the following output:
root@server:~# curl --fail -s http://$GATEWAY/details/1 | jq
{
  "id": 1,
  "author": "William Shakespeare",
  "year": 1595,
  "type": "paperback",
  "pages": 200,
  "publisher": "PublisherA",
  "language": "English",
  "ISBN-10": "1234567890",
  "ISBN-13": "123-1234567890"
}

This time, we will route traffic based on HTTP parameters like header values, method and query parameters. Let's head back to >_ Terminal 1. Run the following command:

curl -v -H 'magic: foo' "http://$GATEWAY?great=example"


The curl query should be successful and return a successful 200 code and a verbose HTML reply (look out for Hello! This is a simple bookstore application consisting of three services as shown below)

Next, we'll review an Gateway API example with HTTPS traffic.

Deploying a HTTPS Gateway

While these examples with HTTP help us understanding Gateway API specifications, HTTPS is obviously the more secure and preferred option.

Let's see how we can use Gateway API for a HTTPS application using Cilium!


In this task, we will be using Gateway API for HTTPS traffic routing; therefore we will need a TLS certificate for data encryption.

For demonstration purposes we will use a TLS certificate signed by a made-up, self-signed certificate authority (CA). One easy way to do this is with mkcert.

Create a certificate that will validate bookinfo.cilium.rocks and hipstershop.cilium.rocks, as these are the host names used in this Gateway example:

root@server:~# mkcert '*.cilium.rocks'
Created a new local CA 💥
Note: the local CA is not installed in the system trust store.
Run "mkcert -install" for certificates to be trusted automatically ⚠️

Created a new certificate valid for the following names 📜
 - "*.cilium.rocks"

Reminder: X.509 wildcards only go one level deep, so this won't match a.b.cilium.rocks ℹ️

The certificate is at "./_wildcard.cilium.rocks.pem" and the key at "./_wildcard.cilium.rocks-key.pem" ✅

It will expire on 13 November 2026 🗓

Mkcert created a key (_wildcard.cilium.rocks-key.pem) and a certificate (_wildcard.cilium.rocks.pem) that we will use for the Gateway service.

Create a Kubernetes TLS secret with this key and certificate:
root@server:~# kubectl create secret tls demo-cert \
  --key=_wildcard.cilium.rocks-key.pem \
  --cert=_wildcard.cilium.rocks.pem
secret/demo-cert created

Review the HTTPS Gateway API example provided in the current directory:
yq basic-https.yaml

It is almost identical to the one we reviewed previously. Just notice the following in the Gateway manifest:
spec:
  gatewayClassName: cilium
  listeners:
  - name: https-1
    protocol: HTTPS
    port: 443
    hostname: "bookinfo.cilium.rocks"
    tls:
      certificateRefs:
      - kind: Secret
        name: demo-cert

And the following in the HTTPRoute manifest:
spec:
  parentRefs:
  - name: tls-gateway
  hostnames:
  - "bookinfo.cilium.rocks"

The HTTPS Gateway API examples build up on what was done in the HTTP example and adds TLS termination for two HTTP routes:

    the /details prefix will be routed to the details HTTP service deployed in the HTTP challenge
    the / prefix will be routed to the productpage HTTP service deployed in the HTTP challenge

These services will be secured via TLS and accessible on two domain names:

    bookinfo.cilium.rocks
    hipstershop.cilium.rocks

In our example, the Gateway serves the TLS certificate defined in the demo-cert Secret resource for all requests to bookinfo.cilium.rocks and to hipstershop.cilium.rocks.

Let's now deploy the Gateway to the cluster:       
root@server:~# kubectl apply -f basic-https.yaml
gateway.gateway.networking.k8s.io/tls-gateway created
httproute.gateway.networking.k8s.io/https-app-route-1 created
httproute.gateway.networking.k8s.io/https-app-route-2 created

This creates a LoadBalancer service, which after around 30 seconds or so should be populated with an external IP address.

Verify that the Gateway has an load balancer IP address assigned:
root@server:~# kubectl get gateway tls-gateway
NAME          CLASS    ADDRESS          PROGRAMMED   AGE
tls-gateway   cilium   172.18.255.201   True         24s

Then assign this IP to the GATEWAY_IP variable so we can make use of it:
root@server:~# GATEWAY_IP=$(kubectl get gateway tls-gateway -o jsonpath='{.status.addresses[0].value}')
echo $GATEWAY_IP
172.18.255.201

Install the Mkcert CA into your system so cURL can trust it:
root@server:~# mkcert -install
The local CA is now installed in the system trust store! ⚡️

Now let's make a request to the Gateway:
root@server:~# curl -s \
  --resolve bookinfo.cilium.rocks:443:${GATEWAY_IP} \
  https://bookinfo.cilium.rocks/details/1 | jq
{
  "id": 1,
  "author": "William Shakespeare",
  "year": 1595,
  "type": "paperback",
  "pages": 200,
  "publisher": "PublisherA",
  "language": "English",
  "ISBN-10": "1234567890",
  "ISBN-13": "123-1234567890"
}

The data should be properly retrieved, using HTTPS (and thus, the TLS handshake was properly achieved).

In the next challenge, we will see how to use Gateway API for general TLS traffic.

TLSRoute

In the previous task, we looked at the TLS Termination and how the Gateway can terminate HTTPS traffic from a client and route the unencrypted HTTP traffic based on HTTP properties, like path, method or headers.

In this task, we will look at a feature that was introduced in Cilium 1.14: TLSRoute. This resource lets you passthrough TLS traffic from the client all the way to the Pods - meaning the traffic is encrypted end-to-end.

We will be using a NGINX web server. Review the NGINX configuration.
cat nginx.conf

As you can see, it listens on port 443 for SSL traffic. Notice it specifies the certificate and key previously created.

We will need to mount the files to the right path (/etc/nginx-server-certs) when we deploy the server.

The NGINX server configuration is held in a Kubernetes ConfigMap. Let's create it.

root@server:~# kubectl create configmap nginx-configmap --from-file=nginx.conf=./nginx.conf
configmap/nginx-configmap created
root@server:~# 

Review the NGINX server Deployment and the Service fronting it:
yq tls-service.yaml

As you can see, we are deploying a container with the nginx image, mounting several files such as the HTML index, the NGINX configuration and the certs. Note that we are reusing the demo-cert TLS secret we created earlier.

root@server:~# kubectl apply -f tls-service.yaml
service/my-nginx created
deployment.apps/my-nginx created

Verify the Service and Deployment have been deployed successfully:
root@server:~# kubectl get svc,deployment my-nginx
NAME               TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
service/my-nginx   ClusterIP   10.96.115.16   <none>        443/TCP   23s

NAME                       READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/my-nginx   1/1     1            1           23s

Review the Gateway API configuration files provided in the current directory

They are almost identical to the one we reviewed in the previous tasks. Just notice the Passthrough mode set in the Gateway manifest:
yq tls-gateway.yaml 
Previously, we used the HTTPRoute resource. This time, we are using TLSRoute:
yq tls-route.yaml

Earlier you saw how you can terminate the TLS connection at the Gateway. That was using the Gateway API in Terminate mode. In this instance, the Gateway is in Passthrough mode: the difference is that the traffic remains encrypted all the way through between the client and the pod.

In other words:

In Terminate:

    Client -> Gateway: HTTPS
    Gateway -> Pod: HTTP

In Passthrough:

    Client -> Gateway: HTTPS
    Gateway -> Pod: HTTPS

The Gateway does not actually inspect the traffic aside from using the SNI header for routing. Indeed the hostnames field defines a set of SNI names that should match against the SNI attribute of TLS ClientHello message in TLS handshake.

Let's now deploy the Gateway and the TLSRoute to the cluster:
root@server:~# kubectl apply -f tls-gateway.yaml -f tls-route.yaml
gateway.gateway.networking.k8s.io/cilium-tls-gateway created
tlsroute.gateway.networking.k8s.io/nginx created

This creates a LoadBalancer service, which after around 30 seconds or so should be populated with an external IP address.

Verify that the Gateway has a LoadBalancer IP address assigned:
root@server:~# kubectl get gateway cilium-tls-gateway
NAME                 CLASS    ADDRESS          PROGRAMMED   AGE
cilium-tls-gateway   cilium   172.18.255.202   True         21s

Then assign this IP to the GATEWAY_IP variable so we can make use of it:
root@server:~# GATEWAY_IP=$(kubectl get gateway cilium-tls-gateway -o jsonpath='{.status.addresses[0].value}')
echo $GATEWAY_IP
172.18.255.202

Let's also double check the TLSRoute has been provisioned successfully and has been attached to the Gateway.

root@server:~# kubectl get tlsroutes.gateway.networking.k8s.io -o json | jq '.items[0].status.parents[0]'
{
  "conditions": [
    {
      "lastTransitionTime": "2024-08-13T08:37:55Z",
      "message": "Accepted TLSRoute",
      "observedGeneration": 1,
      "reason": "Accepted",
      "status": "True",
      "type": "Accepted"
    },
    {
      "lastTransitionTime": "2024-08-13T08:37:55Z",
      "message": "Service reference is valid",
      "observedGeneration": 1,
      "reason": "ResolvedRefs",
      "status": "True",
      "type": "ResolvedRefs"
    }
  ],
  "controllerName": "io.cilium/gateway-controller",
  "parentRef": {
    "group": "gateway.networking.k8s.io",
    "kind": "Gateway",
    "name": "cilium-tls-gateway"
  }
}


Now let's make a request over HTTPS to the Gateway:
root@server:~# curl -v \
  --resolve "nginx.cilium.rocks:443:$GATEWAY_IP" \
  "https://nginx.cilium.rocks:443"
* Added nginx.cilium.rocks:443:172.18.255.202 to DNS cache
* Hostname nginx.cilium.rocks was found in DNS cache
*   Trying 172.18.255.202:443...
* Connected to nginx.cilium.rocks (172.18.255.202) port 443
* ALPN: curl offers h2,http/1.1
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
*  CAfile: /etc/ssl/certs/ca-certificates.crt
*  CApath: /etc/ssl/certs
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* TLSv1.3 (IN), TLS handshake, Encrypted Extensions (8):
* TLSv1.3 (IN), TLS handshake, Certificate (11):
* TLSv1.3 (IN), TLS handshake, CERT verify (15):
* TLSv1.3 (IN), TLS handshake, Finished (20):
* TLSv1.3 (OUT), TLS change cipher, Change cipher spec (1):
* TLSv1.3 (OUT), TLS handshake, Finished (20):
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384 / X25519 / RSASSA-PSS
* ALPN: server accepted http/1.1
* Server certificate:
*  subject: O=mkcert development certificate; OU=root@server
*  start date: Aug 13 08:24:18 2024 GMT
*  expire date: Nov 13 08:24:18 2026 GMT
*  subjectAltName: host "nginx.cilium.rocks" matched cert's "*.cilium.rocks"
*  issuer: O=mkcert development CA; OU=root@server; CN=mkcert root@server
*  SSL certificate verify ok.
*   Certificate level 0: Public key type RSA (2048/112 Bits/secBits), signed using sha256WithRSAEncryption
*   Certificate level 1: Public key type RSA (3072/128 Bits/secBits), signed using sha256WithRSAEncryption
* using HTTP/1.x
> GET / HTTP/1.1
> Host: nginx.cilium.rocks
> User-Agent: curl/8.5.0
> Accept: */*
> 
* TLSv1.3 (IN), TLS handshake, Newsession Ticket (4):
* TLSv1.3 (IN), TLS handshake, Newsession Ticket (4):
* old SSL session ID is stale, removing
< HTTP/1.1 200 OK
< Server: nginx/1.27.0
< Date: Tue, 13 Aug 2024 08:39:32 GMT
< Content-Type: text/html
< Content-Length: 100
< Last-Modified: Tue, 13 Aug 2024 08:33:28 GMT
< Connection: keep-alive
< ETag: "66bb1a58-64"
< Accept-Ranges: bytes
< 
<html>
<h1>Welcome to our webserver listening on port 443.</h1>
</br>
<h1>Cilium rocks.</h1>
</html
* Connection #0 to host nginx.cilium.rocks left intact
root@server:~# 


Traffic splitting

Cilium Gateway API comes fully integrated with a HTTP traffic splitting engine.

In order to introduce a new version of an app, operators would often start pushing some traffic to a new backend and see how users react and how the app fares under load. It’s also known as A/B testing, blue-green deployments or canary releases.

You can now do it natively, with Cilium Gateway API weights. No need to install another tool or Service Mesh.


First, let's deploy a sample echo application in the cluster. The application will reply to the client and, in the body of the reply, will include information about the pod and node receiving the original request. We will use this information to illustrate that the traffic is split between multiple Kubernetes Services.

root@server:~# kubectl apply -f echo-servers.yaml
service/echo-1 created
deployment.apps/echo-1 created
service/echo-2 created
deployment.apps/echo-2 created

The data should be properly retrieved, using HTTPS (and thus, the TLS handshake was properly achieved).

There are several things to note in the output.

    It should be successful (you should see at the end, a HTML output with Cilium rocks.).
    The connection was established over port 443 - you should see Connected to nginx.cilium.rocks (172.18.255.200) port 443 .
    You should see TLS handshake and TLS version negotiation. Expect the negotiations to have resulted in TLSv1.3 being used.
    Expect to see a successful certificate verification (look out for SSL certificate verify ok).


Look at the YAML file with the command below. You'll see we are deploying multiple pods and services. The services are called echo-1 and echo-2 and traffic will be split between these services.
yq echo-servers.yaml

Check that the application is properly deployed:

root@server:~# kubectl get pods
NAME                             READY   STATUS    RESTARTS   AGE
details-v1-65599dcf88-98r9n      1/1     Running   0          31m
echo-1-6d99ff955f-99d7l          1/1     Running   0          52s
echo-2-74cb847c7c-47grm          1/1     Running   0          52s
my-nginx-96b69b744-cr9w9         1/1     Running   0          9m8s
productpage-v1-9487c9c5b-7ntbv   1/1     Running   0          31m
ratings-v1-59b99c644-nxtxw       1/1     Running   0          31m
reviews-v1-5985998544-q68tw      1/1     Running   0          31m
reviews-v2-86d6cc668-npzlv       1/1     Running   0          31m
reviews-v3-dbb5fb5dd-m8hps       1/1     Running   0          31m

You should see multiple pods being deployed in the default namespace. Wait until they are Running (should take 10 to 15 seconds).

Have a quick look at the Services deployed:
root@server:~# kubectl get svc
NAME                                TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)         AGE
cilium-gateway-cilium-tls-gateway   LoadBalancer   10.96.148.51    172.18.255.202   443:32275/TCP   5m10s
cilium-gateway-my-gateway           LoadBalancer   10.96.101.227   172.18.255.200   80:30297/TCP    30m
cilium-gateway-tls-gateway          LoadBalancer   10.96.50.203    172.18.255.201   443:32007/TCP   14m
details                             ClusterIP      10.96.150.71    <none>           9080/TCP        32m
echo-1                              ClusterIP      10.96.185.121   <none>           8080/TCP        82s
echo-2                              ClusterIP      10.96.144.95    <none>           8090/TCP        82s
kubernetes                          ClusterIP      10.96.0.1       <none>           443/TCP         3h16m
my-nginx                            ClusterIP      10.96.115.16    <none>           443/TCP         9m38s
productpage                         ClusterIP      10.96.63.210    <none>           9080/TCP        32m
ratings                             ClusterIP      10.96.235.251   <none>           9080/TCP        32m
reviews                             ClusterIP      10.96.226.85    <none>           9080/TCP        32m

Note these Services are only internal-facing (ClusterIP) and therefore there is no access from outside the cluster to these Services.
Let's deploy the HTTPRoute with the following manifest:
root@server:~# kubectl apply -f load-balancing-http-route.yaml
httproute.gateway.networking.k8s.io/load-balancing-route created

Let's review the HTTPRoute manifest.
This Rule is essentially a simple L7 proxy route: for HTTP traffic with a path starting with /echo, forward the traffic over to the echo-1 and echo-2 Services over port 8080 and 8090 respectively. Notice the even 50/50 weighing.

    backendRefs:
    - kind: Service
      name: echo-1
      port: 8080
      weight: 50
    - kind: Service
      name: echo-2
      port: 8090
      weight: 50

Let's retrieve the IP address associated with the Gateway again:
root@server:~# GATEWAY=$(kubectl get gateway my-gateway -o jsonpath='{.status.addresses[0].value}')
echo $GATEWAY
172.18.255.200

Let's now check that traffic based on the URL path is proxied by the Gateway API.

Check that you can make HTTP requests to that external address
root@server:~# curl --fail -s http://$GATEWAY/echo


Hostname: echo-2-74cb847c7c-47grm

Pod Information:
        node name:      kind-worker2
        pod name:       echo-2-74cb847c7c-47grm
        pod namespace:  default
        pod IP: 10.244.1.76

Server values:
        server_version=nginx: 1.12.2 - lua: 10010

Request Information:
        client_address=10.244.1.7
        method=GET
        real path=/echo
        query=
        request_version=1.1
        request_scheme=http
        request_uri=http://172.18.255.200:8080/echo

Request Headers:
        accept=*/*  
        host=172.18.255.200  
        user-agent=curl/8.5.0  
        x-envoy-internal=true  
        x-forwarded-for=172.18.0.1  
        x-forwarded-proto=http  
        x-request-id=22fdc857-7f9b-4fb3-a94e-3602cf3eafe0  

Request Body:
        -no body in request-

Notice that, in the reply, you get the name of the pod that received the query. For example:
Hostname: echo-2-74cb847c7c-47grm

Note that you can also see the headers in the original request. This will be useful in an upcoming task.

Repeat the command several times.

You should see the reply being balanced evenly across both pods/nodes.

Let's double check that traffic is evenly split across multiple Pods by running a loop and counting the requests:
root@server:~# for _ in {1..500}; do
  curl -s -k "http://$GATEWAY/echo" >> curlresponses.txt;
done

Verify that the responses have been (more or less) evenly spread.
root@server:~# grep -o "Hostname: echo-." curlresponses.txt | sort | uniq -c
    268 Hostname: echo-1
    232 Hostname: echo-2

This time, we will be applying a different weight.

We could change the previous manifest and re-apply it or, if you don't mind using vi, we can edit the HTTPRoute specification directly on the API Server. Let's use this second option. Run:    
kubectl edit httproute load-balancing-route

The vi editor will be automatically launch.

Replace the weights from 50 for both echo-1 and echo-2 to 99 for echo-1 and 1 for echo-2.

Exit the editor using ESC followed by :wq (to save the file as you exit).

Let's run another loop and count the replies again, with the following command:
root@server:~# for _ in {1..500}; do
  curl -s -k "http://$GATEWAY/echo" >> curlresponses991.txt;
done

Verify that the responses are spread with about 99% of them to echo-1 and about 1% of them to echo-2.
root@server:~# grep -o "Hostname: echo-." curlresponses991.txt | sort | uniq -c
    495 Hostname: echo-1
      5 Hostname: echo-2


To conclude this lab, let's finish with a simple lab. We will re-use the Services (called echo-1 and echo-2) created earlier.

To successfully pass the exam, we need:

    Both Services accessible via a Gateway API and

    HTTP traffic based on the PrefixPath /exam to reach the Services

    Traffic to be split 75:25 between echo-1 and echo-2: 75% of traffic would reach the echo-1 Service while the remaining 25% will reach the echo-2 Service.

    Using the built-in </> Editor tab, check the exam-gateway.yaml and exam-http-route.yaml files in the /root/exam folder. You will need to update the XXXX fields with the correct values.

    The Services listen on different ports - you can check the ports they listen on with kubectl get svc or by looking at the echo-servers.yaml manifest used to deploy these Services.

    Remember that you need to refer a HTTPRoute to a parent Gateway.

    Make sure you apply the manifests.

    Assuming $GATEWAY is the IP Address assigned to the Gateway, curl --fail -s http://$GATEWAY/exam | grep Hostname should return an output such as:

root@server:~# curl --fail -s http://$GATEWAY/exam | grep Hostname
Hostname: echo-1-6d99ff955f-99d7l

