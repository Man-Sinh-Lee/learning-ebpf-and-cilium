Cilium Gateway API

Your lab environment is currently being set up. Stay tuned!

This lab is a follow-up to the introductory Cilium Gateway API lab. We highly recommend you do the Cilium Gateway API lab first, if you haven't done it already.

In this one, you will learn about some additional specific use cases for Gateway API:

    HTTP request and response header rewrite
    HTTP mirror, rewrite and redirect
    gRPC routing
    Cross-namespace routing

Resilient Connectivity

Service to service communication must be possible across boundaries such as clouds, clusters, and premises. Communication must be resilient and fault tolerant.

Embedded Envoy Proxy

Cilium already uses Envoy for L7 policy and observability for some protocols, and this same component is used as the sidecar proxy in many popular Service Mesh implementations.

So it's a natural step to extend Cilium to offer more of the features commonly associated with Service Mesh — though contrary to other solutions, without the need for any pod sidecars.

Instead, this Envoy proxy is embedded with Cilium, which means that only one Envoy container is required per node.

BPF acceleration

In a typical Service Mesh, all network packets need to pass through a sidecar proxy container on their path to or from the application container in a Pod.

This means each packet traverses the TCP/IP stack three times before even leaving the Pod.

🚦 Advanced Gateway API Use Cases
Before we can install Cilium with the Gateway API feature, there are a couple of important prerequisites to know:

    Cilium must be configured with kubeProxyReplacement set to true.

    CRD (Custom Resource Definition) from Gateway API must be installed beforehand.

As part of the lab deployment script, several CRDs were installed. Verify that they are available.

root@server:~# kubectl get crd \
  gatewayclasses.gateway.networking.k8s.io \
  gateways.gateway.networking.k8s.io \
  httproutes.gateway.networking.k8s.io \
  referencegrants.gateway.networking.k8s.io \
  tlsroutes.gateway.networking.k8s.io \
  grpcroutes.gateway.networking.k8s.io
NAME                                        CREATED AT
gatewayclasses.gateway.networking.k8s.io    2024-08-13T09:12:40Z
gateways.gateway.networking.k8s.io          2024-08-13T09:12:41Z
httproutes.gateway.networking.k8s.io        2024-08-13T09:12:41Z
referencegrants.gateway.networking.k8s.io   2024-08-13T09:12:41Z
tlsroutes.gateway.networking.k8s.io         2024-08-13T09:12:42Z
grpcroutes.gateway.networking.k8s.io        2024-08-13T09:12:42Z

During the lab deployment, Cilium was installed using the following flags:
--set kubeProxyReplacement=true \
--set gatewayAPI.enabled=true

Verify that Cilium was enabled and deployed with the Gateway API features:
root@server:~# cilium config view | grep -w "enable-gateway-api "
enable-gateway-api                                true

More information about the Gateway API can be found in the previous Cilium Gateway API lab and in the Cilium Gateway API deep dive.

We need a Load Balancer

The Cilium Service Mesh Gateway API Controller requires the ability to create LoadBalancer Kubernetes services.

Since we are using Kind on a Virtual Machine, we do not benefit from an underlying Cloud Provider's load balancer integration.

For this lab, we will use Cilium's own LoadBalancer capabilities to provide IP Address Management (IPAM) and Layer 2 announcement of IP addresses assigned to LoadBalancer services.

You can check the Cilium LoadBalancer IPAM and L2 Service Announcement lab to learn more about it.

First, let's deploy a sample echo application in the cluster. The application will reply to the client and, in the body of the reply, will include information about the original request header. We will use this information to illustrate how the Gateway can modify headers and other HTTP parameters.
root@server:~# kubectl apply -f echo-servers.yaml
service/echo-1 created
deployment.apps/echo-1 created

Look at the YAML file with the command below. You'll see we are deploying multiple pods and services. The services are called echo-1 and echo-2 and traffic will be split between these services.

Check that the application is properly deployed:
root@server:~# kubectl get pods
NAME                      READY   STATUS    RESTARTS   AGE
echo-1-6d99ff955f-vsgdg   1/1     Running   0          51s

You should see multiple pods being deployed in the default namespace. Wait until they are Running (should take 10 to 15 seconds).

Have a quick look at the Services deployed:
root@server:~# kubectl get svc
NAME         TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
echo-1       ClusterIP   10.96.13.203   <none>        8080/TCP   69s
kubernetes   ClusterIP   10.96.0.1      <none>        443/TCP    52m

Note these Services are only internal-facing (ClusterIP) and therefore there is no access from outside the cluster to these Services.

Let's deploy the Gateway and the HTTPRoute with the following manifest:

root@server:~# kubectl apply -f gateway.yaml -f http-route.yaml
gateway.gateway.networking.k8s.io/cilium-gw created
httproute.gateway.networking.k8s.io/example-route-1 created

Let's have another look at the Services now that the Gateway has been deployed:
root@server:~# kubectl get svc
NAME                       TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)        AGE
cilium-gateway-cilium-gw   LoadBalancer   10.96.43.91    172.18.255.200   80:31614/TCP   6m45s
echo-1                     ClusterIP      10.96.13.203   <none>           8080/TCP       8m25s
kubernetes                 ClusterIP      10.96.0.1      <none>           443/TCP        59m

You will see a LoadBalancer service named cilium-gateway-cilium-gw which was created for the Gateway API.

We now have an IP address also associated with the Gateway:
root@server:~# kubectl get gateway
NAME        CLASS    ADDRESS          PROGRAMMED   AGE
cilium-gw   cilium   172.18.255.200   True         7m8s

Let's retrieve this IP address:
root@server:~# GATEWAY=$(kubectl get gateway cilium-gw -o jsonpath='{.status.addresses[0].value}')
echo $GATEWAY
172.18.255.200

Note that this IP address was assigned by Cilium's LB-IPAM (Load-Balancer IP Address Management) feature.

Let's now check that traffic based on the URL path is proxied by the Gateway API.

Check that you can make HTTP requests to that external address:

root@server:~# curl --fail -s http://$GATEWAY/echo


Hostname: echo-1-6d99ff955f-vsgdg

Pod Information:
        node name:      kind-worker2
        pod name:       echo-1-6d99ff955f-vsgdg
        pod namespace:  default
        pod IP: 10.244.1.42

Server values:
        server_version=nginx: 1.12.2 - lua: 10010

Request Information:
        client_address=10.244.1.127
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
        x-request-id=599bdf6a-452e-4872-a749-df99794d6e49  

Request Body:
        -no body in request-

Note that you can see, in the reply, the headers from the original request. This will be useful in the next task.


HTTP Header Request Modifier

In this challenge, you will use Cilium Gateway API to modify HTTP headers of HTTP requests.

HTTP header modification is the process of adding, removing, or modifying HTTP headers in incoming requests. The Cilium Gateway API lets users easily customize incoming traffic to meet their specific needs.

With this functionality, Cilium Gateway API lets us add, remove or edit HTTP Headers of incoming traffic.

This is best validated by trying without and with the functionality. We’ll use the same echo servers.

Let's deploy an HTTPRoute resource with the following manifest (we are using the same Gateway deployed in the previous task).
root@server:~# kubectl apply -f echo-header-http-route.yaml
httproute.gateway.networking.k8s.io/header-http-echo created
root@server:~# yq echo-header-http-route.yaml


Notice how the file has commented lines (we will uncomment them later).

Let's retrieve the Gateway IP address:
root@server:~# GATEWAY=$(kubectl get gateway cilium-gw -o jsonpath='{.status.addresses[0].value}')
echo $GATEWAY
172.18.255.200

Make HTTP requests to that external address:
root@server:~# curl --fail -s http://$GATEWAY/cilium-add-a-request-header


Hostname: echo-1-6d99ff955f-vsgdg

Pod Information:
        node name:      kind-worker2
        pod name:       echo-1-6d99ff955f-vsgdg
        pod namespace:  default
        pod IP: 10.244.1.42

Server values:
        server_version=nginx: 1.12.2 - lua: 10010

Request Information:
        client_address=10.244.1.127
        method=GET
        real path=/cilium-add-a-request-header
        query=
        request_version=1.1
        request_scheme=http
        request_uri=http://172.18.255.200:8080/cilium-add-a-request-header

Request Headers:
        accept=*/*  
        host=172.18.255.200  
        user-agent=curl/8.5.0  
        x-envoy-internal=true  
        x-forwarded-for=172.18.0.1  
        x-forwarded-proto=http  
        x-request-id=720035e8-2a80-4afb-842c-025a3fae6b16  

Request Body:
        -no body in request-

In the reply, you should see the original request header. They should look similar to this:       
Request Headers:
        accept=*/*  
        host=172.18.255.200  
        user-agent=curl/8.5.0  
        x-envoy-internal=true  
        x-forwarded-for=172.18.0.1  
        x-forwarded-proto=http  
        x-request-id=720035e8-2a80-4afb-842c-025a3fae6b16  


Head to the </> Editor and uncomment the commented lines of echo-header-http-route.yaml (lines 14 to 19).

The lines you are uncommenting are pretty self-explanatory: you are using a filter of the type RequestHeaderModifier to add a specific header, with a name and a value.

Re-apply the HTTPRoute in the >_ Terminal 1 tab:

root@server:~# kubectl apply -f echo-header-http-route.yaml
httproute.gateway.networking.k8s.io/header-http-echo configured
root@server:~# yq echo-header-http-route.yaml 
---
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: header-http-echo
spec:
  parentRefs:
    - name: cilium-gw
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /cilium-add-a-request-header
      filters:
        - type: RequestHeaderModifier
          requestHeaderModifier:
            add:
              - name: my-cilium-header-name
                value: my-cilium-header-value
      backendRefs:
        - name: echo-1
          port: 8080


Let's now check that the header is modified by Cilium Gateway API:

Make a curl HTTP request to that address again:
root@server:~# curl --fail -s http://$GATEWAY/cilium-add-a-request-header


Hostname: echo-1-6d99ff955f-vsgdg

Pod Information:
        node name:      kind-worker2
        pod name:       echo-1-6d99ff955f-vsgdg
        pod namespace:  default
        pod IP: 10.244.1.42

Server values:
        server_version=nginx: 1.12.2 - lua: 10010

Request Information:
        client_address=10.244.1.127
        method=GET
        real path=/cilium-add-a-request-header
        query=
        request_version=1.1
        request_scheme=http
        request_uri=http://172.18.255.200:8080/cilium-add-a-request-header

Request Headers:
        accept=*/*  
        host=172.18.255.200  
        my-cilium-header-name=my-cilium-header-value  
        user-agent=curl/8.5.0  
        x-envoy-internal=true  
        x-forwarded-for=172.18.0.1  
        x-forwarded-proto=http  
        x-request-id=c406f9a3-1f2f-4ac8-9c5c-dfb41af3fbbc  

Request Body:
        -no body in request-

You should see, in the Request Headers section of the reply, that the header my-cilium-header-name=my-cilium-header-value has been added to the HTTP request.

Note that you can also remove or edit HTTP request headers sent from the client.

In the next task, we will use a feature to do the same, for HTTP response headers.

You can use the observability platform Hubble in >_ Terminal 2 to observe the traffic.

First, forward Hubble's port to access it from the VM:
cilium hubble port-forward &

Then, use the Hubble CLI to observe traffic flows, filtering on the specific HTTP path you adding with Gateway API:
hubble observe --http-path "/cilium-add-a-request-header"

You can see how traffic was sent through the Cilium L7 Ingress (which implements Gateway API) and that you can use Hubble to observe traffic using Layer 7 filters such as HTTP Path.


HTTP Response Header Rewrite

In this challenge, we will test HTTP response header rewrite using Cilium Gateway API.

Just like editing request headers can be useful, the same goes for response headers. For example, it allows teams to add/remove cookies for only a certain backend, which can help in identifying certain users that were redirected to that backend previously.

Another potential use case could be when you have a frontend that needs to know whether it's talking to a stable or a beta version of the backend server, in order to render different UI or adapt its response parsing accordingly.


Let's deploy the HTTPRoute with the following manifest:

root@server:~# yq response-header-modifier-http-route.yaml 
---
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: response-header-modifier
spec:
  parentRefs:
    - name: cilium-gw
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /multiple
      filters:
        - type: ResponseHeaderModifier
          responseHeaderModifier:
            add:
              - name: X-Header-Add-1
                value: header-add-1
              - name: X-Header-Add-2
                value: header-add-2
              - name: X-Header-Add-3
                value: header-add-3
      backendRefs:
        - name: echo-1
          port: 8080

root@server:~# kubectl apply -f response-header-modifier-http-route.yaml
httproute.gateway.networking.k8s.io/response-header-modifier created

Notice how this time, the header's response is modified, using the type: ResponseHeaderModifier filter.

We are going to add 3 headers in one go.

Let's retrieve the Gateway IP address:
root@server:~# GATEWAY=$(kubectl get gateway cilium-gw -o jsonpath='{.status.addresses[0].value}')
echo $GATEWAY
172.18.255.200

Check that you can make HTTP requests to that external address:
root@server:~# curl --fail -s http://$GATEWAY/multiple


Hostname: echo-1-6d99ff955f-vsgdg

Pod Information:
        node name:      kind-worker2
        pod name:       echo-1-6d99ff955f-vsgdg
        pod namespace:  default
        pod IP: 10.244.1.42

Server values:
        server_version=nginx: 1.12.2 - lua: 10010

Request Information:
        client_address=10.244.1.127
        method=GET
        real path=/multiple
        query=
        request_version=1.1
        request_scheme=http
        request_uri=http://172.18.255.200:8080/multiple

Request Headers:
        accept=*/*  
        host=172.18.255.200  
        user-agent=curl/8.5.0  
        x-envoy-internal=true  
        x-forwarded-for=172.18.0.1  
        x-forwarded-proto=http  
        x-request-id=086fc399-163f-4501-a602-0a59948a4b5c  

Request Body:
        -no body in request-

Note the body of the packet includes details about the original request.


HTTP Traffic Mirroring

In this challenge, we will mirror HTTP traffic using Cilium Gateway API.

You can mirror traffic destined for a backend to another backend.

This is useful when you want to introduce a v2 of a service or simply for troubleshooting and analytics purposes.


n this task, we will use the Gateway to mirror traffic destined for a backend to another backend.

This is useful when you want to introduce a v2 of a service or simply for troubleshooting and analytics purposes.

We will be using a different demo app. This demo app will deploy some Pods and Services - infra-backend-v1 and infra-backend-v2. We will mirror the traffic bound for infra-backend-v1 to infra-backend-v2.

Verify that the demo app has been properly deployed:
root@server:~# kubectl get -f demo-app.yaml
NAME                       TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)    AGE
service/infra-backend-v1   ClusterIP   10.96.16.3   <none>        8080/TCP   89s

NAME                               READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/infra-backend-v1   1/1     1            1           89s

NAME                       TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
service/infra-backend-v2   ClusterIP   10.96.253.43   <none>        8080/TCP   89s

NAME                               READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/infra-backend-v2   1/1     1            1           89s


We have prepared an HTTPRoute manifest to mirror HTTP requests to a different backend. Mirroring traffic to a different backend can be useful for troubleshooting, analysis and observability. Note that, while we may mirror traffic to another backend, we will ignore the responses from said backend.

Deploy the HTTPRoute:
root@server:~# kubectl apply -f http-mirror-route.yaml
httproute.gateway.networking.k8s.io/request-mirror created

root@server:~# yq http-mirror-route.yaml 
---
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: request-mirror
spec:
  parentRefs:
    - name: cilium-gw
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /mirror
      #filters:
      #- type: RequestMirror
      #  requestMirror:
      #    backendRef:
      #      name: infra-backend-v2
      #      port: 8080
      backendRefs:
        - name: infra-backend-v1
          port: 8080

Note that the filters block is currently commented.

Retrieve the Gateway IP address:
root@server:~# GATEWAY=$(kubectl get gateway cilium-gw -o jsonpath='{.status.addresses[0].value}')
echo $GATEWAY
172.18.255.200

Make a request to the gateway:
root@server:~# curl -s http://$GATEWAY/mirror | jq
{
  "path": "/mirror",
  "host": "172.18.255.200",
  "method": "GET",
  "proto": "HTTP/1.1",
  "headers": {
    "Accept": [
      "*/*"
    ],
    "User-Agent": [
      "curl/8.5.0"
    ],
    "X-Envoy-Internal": [
      "true"
    ],
    "X-Forwarded-For": [
      "172.18.0.1"
    ],
    "X-Forwarded-Proto": [
      "http"
    ],
    "X-Request-Id": [
      "4f92f5de-f5ce-427a-9508-5b8d054873fb"
    ]
  },
  "namespace": "default",
  "ingress": "",
  "service": "",
  "pod": "infra-backend-v1-8558ddcc55-rjgkc"
}

root@server:~# curl -s http://$GATEWAY/mirror | jq
{
  "path": "/mirror",
  "host": "172.18.255.200",
  "method": "GET",
  "proto": "HTTP/1.1",
  "headers": {
    "Accept": [
      "*/*"
    ],
    "User-Agent": [
      "curl/8.5.0"
    ],
    "X-Envoy-Internal": [
      "true"
    ],
    "X-Forwarded-For": [
      "172.18.0.1"
    ],
    "X-Forwarded-Proto": [
      "http"
    ],
    "X-Request-Id": [
      "4f92f5de-f5ce-427a-9508-5b8d054873fb"
    ]
  },
  "namespace": "default",
  "ingress": "",
  "service": "",
  "pod": "infra-backend-v1-8558ddcc55-rjgkc"
}

Using the </> Editor, edit the http-mirror-route.yaml manifest and uncomment the filters section (lines 14-19) in the manifest, then apply it in the >_ Terminal:

root@server:~# yq http-mirror-route.yaml 
---
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: request-mirror
spec:
  parentRefs:
    - name: cilium-gw
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /mirror
      filters:
        - type: RequestMirror
          requestMirror:
            backendRef:
              name: infra-backend-v2
              port: 8080
      backendRefs:
        - name: infra-backend-v1
          port: 8080
root@server:~# kubectl apply -f http-mirror-route.yaml
httproute.gateway.networking.k8s.io/request-mirror configured

Make a new request to the gateway:
root@server:~# curl -s http://$GATEWAY/mirror | jq
{
  "path": "/mirror",
  "host": "172.18.255.200",
  "method": "GET",
  "proto": "HTTP/1.1",
  "headers": {
    "Accept": [
      "*/*"
    ],
    "User-Agent": [
      "curl/8.5.0"
    ],
    "X-Envoy-Internal": [
      "true"
    ],
    "X-Forwarded-For": [
      "172.18.0.1"
    ],
    "X-Forwarded-Proto": [
      "http"
    ],
    "X-Request-Id": [
      "a28cbc3d-19e0-4f0e-a250-9b5d0c148430"
    ]
  },
  "namespace": "default",
  "ingress": "",
  "service": "",
  "pod": "infra-backend-v1-8558ddcc55-rjgkc"
}

Has the mirroring actually happened?

Check the >_ 📜 Backend Logs tab again.

You will see logs on both sides of the split screen, showing that the traffic was indeed mirrored.

Press Check to move on to the next task, where you will be rewriting the HTTP URL.

HTTP URL Rewrite

In this challenge, we will rewrite the URL used in HTTP traffic using Cilium Gateway API.

Rewrites modify the URL used of a client request before proxying it.


In this task, we will use the Gateway to rewrite the path used in the HTTP requests.

Let's start by, again, retrieving the Gateway IP address:
root@server:~# GATEWAY=$(kubectl get gateway cilium-gw -o jsonpath='{.status.addresses[0].value}')
echo $GATEWAY
172.18.255.200

We have prepared a HTTPRoute to rewrite the URL in HTTP requests.
root@server:~# yq http-rewrite-route.yaml 
---
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: rewrite-path
spec:
  parentRefs:
    - name: cilium-gw
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /prefix/one
      filters:
        - type: URLRewrite
          urlRewrite:
            path:
              type: ReplacePrefixMatch
              replacePrefixMatch: /one
      backendRefs:
        - name: infra-backend-v1
          port: 8080

root@server:~# kubectl apply -f http-rewrite-route.yaml
httproute.gateway.networking.k8s.io/rewrite-path created

With this manifest, we will replace the /prefix/one in the request URL to /one.

Let's now check that traffic based on the URL path is proxied and altered by the Gateway API:

Make HTTP requests to that external address and path:
Expect to see this reply. The request is received by an echo server that copies the original request and sends the reply back in the body of the packet.

root@server:~# curl -s http://$GATEWAY/prefix/one | jq
{
  "path": "/one",
  "host": "172.18.255.200",
  "method": "GET",
  "proto": "HTTP/1.1",
  "headers": {
    "Accept": [
      "*/*"
    ],
    "User-Agent": [
      "curl/8.5.0"
    ],
    "X-Envoy-Internal": [
      "true"
    ],
    "X-Envoy-Original-Path": [
      "/prefix/one"
    ],
    "X-Forwarded-For": [
      "172.18.0.1"
    ],
    "X-Forwarded-Proto": [
      "http"
    ],
    "X-Request-Id": [
      "9d30976a-42a0-481b-8263-503a5811cd28"
    ]
  },
  "namespace": "default",
  "ingress": "",
  "service": "",
  "pod": "infra-backend-v1-8558ddcc55-rjgkc"
}

What does it tell us? The Gateway changed the original request from "/prefix/one" to "/one" (see "path" in the output above).

Note that, as we use Envoy for L7 traffic processing, that Envoy also adds the information about the original path in the packet (see "X-Envoy-Original-Path").

Note that rewriting the URL in HTTP Requests can also be combined with some features we explored in a previous lab. For example, you can add custom HTTP headers while also rewriting the URL path.


HTTP Traffic Redirect

In this challenge, we will redirect clients to a different URL using Cilium Gateway API.

You can customize the path, hostname and the HTTP redirection code (such as 301 or 302) in your redirection messages.

This is useful during a temporary or permanent migration of an application.

In this task, we will redirect HTTP traffic!

Let's deploy the HTTPRoute - we will review it, section by section, throughout this task.
root@server:~# yq redirect-route.yaml 
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: redirect-path
spec:
  parentRefs:
    - name: cilium-gw
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /original-prefix
      filters:
        - type: RequestRedirect
          requestRedirect:
            path:
              type: ReplacePrefixMatch
              replacePrefixMatch: /replacement-prefix
    - matches:
        - path:
            type: PathPrefix
            value: /path-and-host
      filters:
        - type: RequestRedirect
          requestRedirect:
            hostname: example.org
            path:
              type: ReplacePrefixMatch
              replacePrefixMatch: /replacement-prefix
    - matches:
        - path:
            type: PathPrefix
            value: /path-and-status
      filters:
        - type: RequestRedirect
          requestRedirect:
            path:
              type: ReplacePrefixMatch
              replacePrefixMatch: /replacement-prefix
            statusCode: 301
    - matches:
        - path:
            type: PathPrefix
            value: /scheme-and-host
      filters:
        - type: RequestRedirect
          requestRedirect:
            hostname: example.org
            scheme: "https"

root@server:~# kubectl apply -f redirect-route.yaml
httproute.gateway.networking.k8s.io/redirect-path created

Let's retrieve the Gateway IP address:
root@server:~# GATEWAY=$(kubectl get gateway cilium-gw -o jsonpath='{.status.addresses[0].value}')
echo $GATEWAY
172.18.255.200

Let's now check that traffic based on the URL path is proxied and altered by the HTTPRoute created above:
root@server:~# yq '.spec.rules[0]' redirect-route.yaml
matches:
  - path:
      type: PathPrefix
      value: /original-prefix
filters:
  - type: RequestRedirect
    requestRedirect:
      path:
        type: ReplacePrefixMatch
        replacePrefixMatch: /replacement-prefix

Make HTTP requests to that external address and path:

root@server:~# curl -l -v http://$GATEWAY/original-prefix
*   Trying 172.18.255.200:80...
* Connected to 172.18.255.200 (172.18.255.200) port 80
> GET /original-prefix HTTP/1.1
> Host: 172.18.255.200
> User-Agent: curl/8.5.0
> Accept: */*
> 
< HTTP/1.1 302 Found
< location: http://172.18.255.200:80/replacement-prefix
< date: Tue, 13 Aug 2024 09:58:48 GMT
< server: envoy
< content-length: 0
< 
* Connection #0 to host 172.18.255.200 left intact

Notice we use -l in the curl request to follow the redirects (by default, curl will not follow redirects). Notice we use the verbose option of curl to see the response headers.

Notice that, in the reply, you get the name of the pod that received the query. For example:
< HTTP/1.1 302 Found
< location: http://172.18.255.200:80/replacement-prefix
< date: Tue, 13 Aug 2024 09:58:48 GMT
< server: envoy
< content-length: 0
< 
* Connection #0 to host 172.18.255.200 left intact


The location is used in Redirect messages to tell the client where to go. As you can see, the client is redirected to http://172.18.255.200:80/replacement-prefix.

Only the path prefix was modified.

You can also direct the client to a different host. Check the second rule:
root@server:~# yq '.spec.rules[1]' redirect-route.yaml
matches:
  - path:
      type: PathPrefix
      value: /path-and-host
filters:
  - type: RequestRedirect
    requestRedirect:
      hostname: example.org
      path:
        type: ReplacePrefixMatch
        replacePrefixMatch: /replacement-prefix


Make HTTP requests to that external address and path:
root@server:~# curl -l -v http://$GATEWAY/path-and-host
*   Trying 172.18.255.200:80...
* Connected to 172.18.255.200 (172.18.255.200) port 80
> GET /path-and-host HTTP/1.1
> Host: 172.18.255.200
> User-Agent: curl/8.5.0
> Accept: */*
> 
< HTTP/1.1 302 Found
< location: http://example.org:80/replacement-prefix
< date: Tue, 13 Aug 2024 10:01:21 GMT
< server: envoy
< content-length: 0
< 
* Connection #0 to host 172.18.255.200 left intact

As you can see, the client is redirected to http://example.org:80/replacement-prefix.

Both the hostname and the path prefix were modified.

Next, you can also modify the status code. By default, as you can see, the redirect status code is 302. It means that the resources have been moved temporarily.

To indicate that the resources the client is trying to access have moved permanently, you can use the status code 301. You can also combine it with the prefix replacement.

Check the third rule:
root@server:~# yq '.spec.rules[2]' redirect-route.yaml
matches:
  - path:
      type: PathPrefix
      value: /path-and-status
filters:
  - type: RequestRedirect
    requestRedirect:
      path:
        type: ReplacePrefixMatch
        replacePrefixMatch: /replacement-prefix
      statusCode: 301

root@server:~# curl -l -v http://$GATEWAY/path-and-status
*   Trying 172.18.255.200:80...
* Connected to 172.18.255.200 (172.18.255.200) port 80
> GET /path-and-status HTTP/1.1
> Host: 172.18.255.200
> User-Agent: curl/8.5.0
> Accept: */*
> 
< HTTP/1.1 301 Moved Permanently
< location: http://172.18.255.200:80/replacement-prefix
< date: Tue, 13 Aug 2024 10:03:15 GMT
< server: envoy
< content-length: 0
< 
* Connection #0 to host 172.18.255.200 left intact

As you can see, the status code returned is 301 Moved Permanently and the client is redirected to http://172.18.255.200:80/replacement-prefix.

Finally, we can also change the scheme and tell the client to use HTTPS instead of HTTP for example.

You can achieve that with the fourth rule:
root@server:~# yq '.spec.rules[3]' redirect-route.yaml
matches:
  - path:
      type: PathPrefix
      value: /scheme-and-host
filters:
  - type: RequestRedirect
    requestRedirect:
      hostname: example.org
      scheme: "https"

Make HTTP requests to that external address and path:
root@server:~# curl -l -v http://$GATEWAY/scheme-and-host
*   Trying 172.18.255.200:80...
* Connected to 172.18.255.200 (172.18.255.200) port 80
> GET /scheme-and-host HTTP/1.1
> Host: 172.18.255.200
> User-Agent: curl/8.5.0
> Accept: */*
> 
< HTTP/1.1 302 Found
< location: https://example.org:443/scheme-and-host
< date: Tue, 13 Aug 2024 10:04:39 GMT
< server: envoy
< content-length: 0
< 
* Connection #0 to host 172.18.255.200 left intact

As you can see, the client initally tried to connect via HTTP and is redirected to https://example.org:443/scheme-and-host.


Cross Namespace Support

The Gateway API has core support for cross Namespace routing. This is useful when more than one user or team is sharing the underlying networking infrastructure, yet control and configuration must be segmented to minimize access and fault domains.

Gateways and Routes can be deployed into different Namespaces and Routes can attach to Gateways across Namespace boundaries. This allows user access control to be applied differently across Namespaces for Routes and Gateways, effectively segmenting access and control to different parts of the cluster-wide routing configuration.

The ability for Routes to attach to Gateways across Namespace boundaries are governed by Route attachment. Route attachment is explored in this lab and demonstrates how independent teams can safely share the same Gateway.


Route Attachment

Route attachment is an important concept that dictates how Routes attach to Gateways and program their routing rules. It is especially relevant when there are Routes across Namespaces that share one or more Gateways.

Gateway and Route attachment is bidirectional - attachment can only succeed if the Gateway owner and Route owner both agree to the relationship.

Gateways support attachment constraints which are fields on Gateway listeners that restrict which Routes can be attached.

Gateways support Namespaces and Route types as attachment constraints. Any Routes that do not meet the attachment constraints are not able to attach to that Gateway. Similarly, Routes explicitly reference Gateways that they want to attach to through the Route's parentRef field.

Together these create a handshake between the infra owners and application owners that enables them to independently define how applications are exposed through Gateways.

This is effectively a policy that reduces administrative overhead. App owners can specify which Gateways their apps should use and infra owners can constrain the Namespaces and types of Routes that a Gateway accepts.


In this task, we will consider a fictional ACME company and three different business units within ACME. Each of them has its own environment, application and namespace.

    The recruiting team has a public-facing careers app where applicants can submit their CV.
    The product team has a public-facing product app where prospective customers can find out more the ACME product.
    The HR team has an internal-facing hr app storing private employee details.

Each app is deployed in its own Namespace. Because careers and product are both public-facing apps, the Security team approved the use of a shared Gateway API. A benefit of a shared Gateway API is that platform and security teams could control centrally the Gateway API, including its certificate management. In the public cloud, it would also reduce the cost (a Gateway API per app would require a public IP and a cloud load balancer, which are not free resources).

However, the Security team does not want the HR details to be exposed and accessible from outside the cluster and therefore does not approve a HTTPRoute attachment from the hr namespace to the Gateway.

Cilium Gateway API Cross-Namespace

When this task was initialized, four namespaces were created: a shared infra-ns namespace and namespaces for each of the three business units.

Verify with:

root@server:~# kubectl get ns --show-labels \
  infra-ns careers product hr
NAME       STATUS   AGE    LABELS
infra-ns   Active   5m3s   kubernetes.io/metadata.name=infra-ns
careers    Active   5m3s   kubernetes.io/metadata.name=careers,shared-gateway-access=true
product    Active   5m3s   kubernetes.io/metadata.name=product,shared-gateway-access=true
hr         Active   5m3s   kubernetes.io/metadata.name=hr

Notice that product and careers both have the shared-gateway-access=true label, but hr does not.

Let's deploy the Gateway and the HTTPRoutes with the following manifest:
root@server:~# kubectl apply -f cross-namespace.yaml
gateway.gateway.networking.k8s.io/shared-gateway created
httproute.gateway.networking.k8s.io/cross-namespace created
httproute.gateway.networking.k8s.io/cross-namespace created
httproute.gateway.networking.k8s.io/cross-namespace created

By now, you should be familiar with the vast majority of the manifest. Here are some of the differences. First, in the Gateway definition, notice it has been deployed in the infra-ns namespace:
yaml

metadata:
  name: shared-gateway
  namespace: infra-ns

This section might also look unfamiliar:
yaml

    allowedRoutes:
      namespaces:
        from: Selector
        selector:
          matchLabels:
            shared-gateway-access: "true"


This Gateway uses a Namespace selector to define which HTTPRoutes are allowed to attach. This allows the infrastructure team to constrain who —or which apps— can use this Gateway by allowlisting a set of Namespaces.

Only Namespaces which are labelled shared-gateway-access: "true" will be able to attach their Routes to the shared Gateway.

In the HTTPRoute definitions, notice how we refer to the shared-gateway in the parentRefs. We specify the Gateway we want to attach to and the Namespace it is in.

Let's test the HTTPRoutes. First, let's fetch the Gateway IP:

root@server:~# GATEWAY=$(kubectl get gateway shared-gateway -n infra-ns -o jsonpath='{.status.addresses[0].value}')
echo $GATEWAY
172.18.255.201

Now, let's connect to the product and careers Services:
root@server:~# curl -s -o /dev/null -w "%{http_code}\n" http://$GATEWAY/product
200

This command should return a 200 status code.
root@server:~# curl -s -o /dev/null -w "%{http_code}\n" http://$GATEWAY/careers
200

This command should also return a 200 status code.

Let's try to connect to the hr Service:

root@server:~# curl -s -o /dev/null -w "%{http_code}\n" http://$GATEWAY/hr
404


It should return a 404. Why?

The HTTPRoute in the hr Namespace with a parentRef for infra-ns/shared-gateway would be ignored by the Gateway because the attachment constraint (Namespace label) was not met.

Verify with the following commands by checking the status of the HTTPRoutes:
root@server:~# echo "Product HTTPRoute Status"
kubectl get httproutes.gateway.networking.k8s.io -n product -o jsonpath='{.items[0].status.parents[0].conditions[0]}' | jq
echo "Careers HTTPRoute Status"
kubectl get httproutes.gateway.networking.k8s.io -n careers -o jsonpath='{.items[0].status.parents[0].conditions[0]}' | jq
echo "HR HTTPRoute Status"
kubectl get httproutes.gateway.networking.k8s.io -n hr -o jsonpath='{.items[0].status.parents[0].conditions[0]}' | jq
Product HTTPRoute Status
{
  "lastTransitionTime": "2024-08-13T10:12:33Z",
  "message": "Accepted HTTPRoute",
  "observedGeneration": 1,
  "reason": "Accepted",
  "status": "True",
  "type": "Accepted"
}
Careers HTTPRoute Status
{
  "lastTransitionTime": "2024-08-13T10:12:33Z",
  "message": "Accepted HTTPRoute",
  "observedGeneration": 1,
  "reason": "Accepted",
  "status": "True",
  "type": "Accepted"
}
HR HTTPRoute Status
{
  "lastTransitionTime": "2024-08-13T10:12:33Z",
  "message": "HTTPRoute is not allowed to attach to this Gateway due to namespace selector restrictions",
  "observedGeneration": 1,
  "reason": "NotAllowedByListeners",
  "status": "False",
  "type": "Accepted"
}

The first two should be "Accepted HTTPRoute" while the last one should have been rejected (its status should be False and the message should start with HTTPRoute is not allowed to attach to this Gateway).

This feature provides engineers with multiple options: either have a dedicated Gateway API per Namespace or per app if required or alternatively use shared Gateway API for centralized management and to reduce potential costs.

In the next challenge, you will see how Gateway API can be used to route gRPC traffic!

Deploying a gRPC Route

While HTTP is still the king of protocols in the web, gRPC is increasingly used, in particular for its low latency and high throughput capabilities.

Let's see how we can deploy a Kubernetes gRPC Route with Cilium Gateway API for a gRPC application using Cilium!

Deploy a gRPC Application

In this challenge, we will deploy a sample gRPC application, which consists of multiple services such as:

    📧 email
    🛒 checkout and cart
    💡 recommendation
    👨‍💻 frontend
    💳 payment
    🚚 shipping
    💱 currency
    📦 productcatalog

In this challenge, we will set up a gRPCRoute with two path prefixes:

    /hipstershop.ProductCatalogService pointing to the productcatalog service
    /hipstershop.CurrencyService pointing to the currency service


For this demo we will use GCP's microservices demo app.

Install the app with the following command.

root@server:~# kubectl apply -f /opt/gcp-microservices-demo.yml
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

Since gRPC is binary-encoded, you also need the proto definitions for the gRPC services in order to make gRPC requests. Download this for the demo app:
root@server:~# curl -o demo.proto https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/main/protos/demo.proto
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  6069  100  6069    0     0  28183      0 --:--:-- --:--:-- --:--:-- 28227

You'll find the gRPC definition in grpc-route.yaml:
root@server:~# yq grpc-route.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GRPCRoute
metadata:
  name: productcatalogservice-rule
spec:
  parentRefs:
    - namespace: default
      name: cilium-gw
  rules:
    - matches:
        - method:
            service: hipstershop.ProductCatalogService
            method: ListProducts
      backendRefs:
        - name: productcatalogservice
          port: 3550
---
apiVersion: gateway.networking.k8s.io/v1
kind: GRPCRoute
metadata:
  name: currencyservice-rule
spec:
  parentRefs:
    - namespace: default
      name: cilium-gw
  rules:
    - matches:
        - method:
            service: hipstershop.CurrencyService
            method: GetSupportedCurrencies
      backendRefs:
        - name: currencyservice
          port: 7000

This defines paths for requests to be routed to the productcatalogservice and currencyservice microservices.

Let's deploy it:
root@server:~# kubectl apply -f grpc-route.yaml
grpcroute.gateway.networking.k8s.io/productcatalogservice-rule created
grpcroute.gateway.networking.k8s.io/currencyservice-rule created
root@server:~# 

Let's retrieve the load balancer's IP address:
root@server:~# GATEWAY=$(kubectl get gateway cilium-gw -o jsonpath='{.status.addresses[0].value}')
echo $GATEWAY
172.18.255.200

Before verifying gRPC routing with the Cilium Gateway API, let's verify that the app is ready:
root@server:~# kubectl rollout status deploy/emailservice
kubectl rollout status deploy/checkoutservice
kubectl rollout status deploy/recommendationservice
kubectl rollout status deploy/frontend
kubectl rollout status deploy/paymentservice
kubectl rollout status deploy/productcatalogservice
kubectl rollout status deploy/cartservice
kubectl rollout status deploy/loadgenerator
kubectl rollout status deploy/currencyservice
kubectl rollout status deploy/shippingservice
kubectl rollout status deploy/redis-cart
kubectl rollout status deploy/adservice
deployment "emailservice" successfully rolled out
deployment "checkoutservice" successfully rolled out
deployment "recommendationservice" successfully rolled out
deployment "frontend" successfully rolled out
deployment "paymentservice" successfully rolled out
deployment "productcatalogservice" successfully rolled out
deployment "cartservice" successfully rolled out
deployment "loadgenerator" successfully rolled out
deployment "currencyservice" successfully rolled out
deployment "shippingservice" successfully rolled out
deployment "redis-cart" successfully rolled out
deployment "adservice" successfully rolled out

Let's try to access the currency service of the application, which lists the currencies the shopping app supports:
root@server:~# grpcurl -plaintext -proto ./demo.proto $GATEWAY:80 hipstershop.CurrencyService/GetSupportedCurrencies | jq
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

Also try accessing the product catalog service with:
root@server:~# grpcurl -plaintext -proto ./demo.proto $GATEWAY:80 hipstershop.ProductCatalogService/ListProducts | jq
{
  "products": [
    {
      "id": "OLJCESPC7Z",
      "name": "Sunglasses",
      "description": "Add a modern touch to your outfits with these sleek aviator sunglasses.",
      "picture": "/static/img/products/sunglasses.jpg",
      "priceUsd": {
        "currencyCode": "USD",
        "units": "19",
        "nanos": 990000000
      },
      "categories": [
        "accessories"
      ]
    },
    {
      "id": "66VCHSJNUP",
      "name": "Tank Top",
      "description": "Perfectly cropped cotton tank, with a scooped neckline.",
      "picture": "/static/img/products/tank-top.jpg",
      "priceUsd": {
        "currencyCode": "USD",
        "units": "18",
        "nanos": 990000000
      },
      "categories": [
        "clothing",
        "tops"
      ]
    },
    {
      "id": "1YMWWN1N4O",
      "name": "Watch",
      "description": "This gold-tone stainless steel watch will work with most of your outfits.",
      "picture": "/static/img/products/watch.jpg",
      "priceUsd": {
        "currencyCode": "USD",
        "units": "109",
        "nanos": 990000000
      },
      "categories": [
        "accessories"
      ]
    },
    {
      "id": "L9ECAV7KIM",
      "name": "Loafers",
      "description": "A neat addition to your summer wardrobe.",
      "picture": "/static/img/products/loafers.jpg",
      "priceUsd": {
        "currencyCode": "USD",
        "units": "89",
        "nanos": 990000000
      },
      "categories": [
        "footwear"
      ]
    },
    {
      "id": "2ZYFJ3GM2N",
      "name": "Hairdryer",
      "description": "This lightweight hairdryer has 3 heat and speed settings. It's perfect for travel.",
      "picture": "/static/img/products/hairdryer.jpg",
      "priceUsd": {
        "currencyCode": "USD",
        "units": "24",
        "nanos": 990000000
      },
      "categories": [
        "hair",
        "beauty"
      ]
    },
    {
      "id": "0PUK6V6EV0",
      "name": "Candle Holder",
      "description": "This small but intricate candle holder is an excellent gift.",
      "picture": "/static/img/products/candle-holder.jpg",
      "priceUsd": {
        "currencyCode": "USD",
        "units": "18",
        "nanos": 990000000
      },
      "categories": [
        "decor",
        "home"
      ]
    },
    {
      "id": "LS4PSXUNUM",
      "name": "Salt & Pepper Shakers",
      "description": "Add some flavor to your kitchen.",
      "picture": "/static/img/products/salt-and-pepper-shakers.jpg",
      "priceUsd": {
        "currencyCode": "USD",
        "units": "18",
        "nanos": 490000000
      },
      "categories": [
        "kitchen"
      ]
    },
    {
      "id": "9SIQT8TOJO",
      "name": "Bamboo Glass Jar",
      "description": "This bamboo glass jar can hold 57 oz (1.7 l) and is perfect for any kitchen.",
      "picture": "/static/img/products/bamboo-glass-jar.jpg",
      "priceUsd": {
        "currencyCode": "USD",
        "units": "5",
        "nanos": 490000000
      },
      "categories": [
        "kitchen"
      ]
    },
    {
      "id": "6E92ZMYYFZ",
      "name": "Mug",
      "description": "A simple mug with a mustard interior.",
      "picture": "/static/img/products/mug.jpg",
      "priceUsd": {
        "currencyCode": "USD",
        "units": "8",
        "nanos": 990000000
      },
      "categories": [
        "kitchen"
      ]
    }
  ]
}

You should see, in the output, a collection of products in JSON, including a candle holder, a hairdryer and sunglasses!

In the next task, you will see how we can use Gateway API not just for Ingress use cases but for Layer 7 traffic management within the cluster.

Internal Layer 7 Traffic Management

In Kubernetes, the Service resource type lets you load-balance traffic inside the cluster (East-West). However, the load-balancing options are very limited: only L3/L4, optionally with topology hints.

Achieving layer 7 load-balancing and advanced routing typically requires deploying a service mesh solution to the cluster.

This usually means using non-standard resource types specific to the service mesh solution. Could there be a way to achieve this result without an additional component, and using standard resources?

The GAMMA initiative

The GAMMA initiative is a dedicated workstream within the Gateway API subproject.

GAMMA stands for Gateway API for Mesh Management and Administration and its goal is to define how Gateway API can be used to configure a service mesh, with the intention of making minimal changes to Gateway API and always preserving the role-oriented nature of Gateway API.

The GAMMA initiative

In Gateway API v1.0, GAMMA supports adding extra HTTP routing to Services by binding a HTTPRoute to a Service as a parent (as opposed to the north/south Gateway API usage of binding a HTTPRoute to a Gateway as a parent, as you've seen so far throughout this lab).

GAMMA provides a standard API for Layer 7 traffic management capabilities within the cluster.

Let's find out more in this challenge.

For this demo we will use a very simple echo application, which we will deploy in the gamma namespace

Install the app with the following command.
root@server:~# kubectl apply -f gamma-manifest.yaml
namespace/gamma created
deployment.apps/echo-v1 created
service/echo-v1 created
deployment.apps/echo-v2 created
service/echo-v2 created
service/echo created
pod/client created

root@server:~# kubectl -n gamma get pods,svc
NAME                           READY   STATUS    RESTARTS   AGE
pod/client                     1/1     Running   0          69s
pod/echo-v1-6775745567-tb2sj   1/1     Running   0          69s
pod/echo-v2-7d7979dd4b-2vsh4   1/1     Running   0          69s

NAME              TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                                     AGE
service/echo      ClusterIP   10.96.2.58      <none>        80/TCP,8080/TCP,443/TCP,9090/TCP,7070/TCP   69s
service/echo-v1   ClusterIP   10.96.42.20     <none>        80/TCP,8080/TCP,443/TCP,9090/TCP,7070/TCP   69s
service/echo-v2   ClusterIP   10.96.115.149   <none>        80/TCP,8080/TCP,443/TCP,9090/TCP,7070/TCP   69s

Let's deploy a HTTPRoute in the gamma namespace.

Check its definition in gamma-route.yaml:
root@server:~#yq gamma-route.yamll
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: gamma-route
  namespace: gamma
spec:
  parentRefs:
    - group: ""
      kind: Service
      name: echo
  rules:
    - matches:
        - path:
            type: Exact
            value: /v1
      backendRefs:
        - name: echo-v1
          port: 80
    - matches:
        - path:
            type: Exact
            value: /v2
      backendRefs:
        - name: echo-v2
          port: 80

You will notice that, instead of attaching a route to a (North/South) Gateway like we did in previous challenges, we are attaching the route to a parent Service, called echo, using the parentRefs field.

Traffic bound to this parent service will be intercepted by Cilium and routed through the per-node Envoy proxy.

Note how we will forward traffic to the /v1 path to the echo-v1 service and the same for v2. This is how we can, for example, do a/b or green/blue canary testing for internal apps.

Let's deploy it:
root@server:~# kubectl apply -f gamma-route.yaml
httproute.gateway.networking.k8s.io/gamma-route created

Unlike the previous tasks where, from outside the cluster, we accessed a service inside the cluster through the North/South Gateway, this time we will make the request from a client inside the cluster to a service also living in the cluster (East-West) traffic.

Let's verify our cluster client is ready:
root@server:~# kubectl get -n gamma pods client
NAME     READY   STATUS    RESTARTS   AGE
client   1/1     Running   0          3m22s

Let's try to access the http://echo/v1 from our client. The echo Pod for echo-v1 will reply with information, including its own hostname.

root@server:~# kubectl -n gamma exec -it client -- curl http://echo/v1
ServiceVersion=
ServicePort=8080
Host=echo
URL=/v1
Method=GET
Proto=HTTP/1.1
IP=10.244.2.58
RequestHeader=Accept:*/*
RequestHeader=User-Agent:curl/8.7.1
RequestHeader=X-Envoy-Internal:true
RequestHeader=X-Forwarded-For:10.244.2.217
RequestHeader=X-Forwarded-Proto:http
RequestHeader=X-Request-Id:b2e6d174-20e7-4764-a1ff-ca7e591e082e
Hostname=echo-v1-6775745567-5jqd7

Let's now access the http://echo/v2 from our client. This time, the traffic will be forward to the echo Pod serving the echo-v2 Service. Let's verify that traffic was received by the echo-v2 pod by filtering with grep:

root@server:~# kubectl -n gamma exec -it client -- curl http://echo/v2
ServiceVersion=
ServicePort=8080
Host=echo
URL=/v2
Method=GET
Proto=HTTP/1.1
IP=10.244.2.58
RequestHeader=Accept:*/*
RequestHeader=User-Agent:curl/8.7.1
RequestHeader=X-Envoy-Internal:true
RequestHeader=X-Forwarded-For:10.244.2.217
RequestHeader=X-Forwarded-Proto:http
RequestHeader=X-Request-Id:09e2004b-bd16-4db2-adf7-5ab56605c926
Hostname=echo-v2-7d7979dd4b-tvq5r

As you can see, using the same API and logic as with the Gateway API, we're able to do path-based routing for east-west traffic within the cluster.

Let's explore another use case.

We explored this use case in the first Gateway API lab where we did some traffic splitting across 2 services. Again, using the same API, we can now do it within the cluster for east-west traffic.

Let's deploy the HTTPRoute with the following manifest:

root@server:~# kubectl apply -f load-balancing-http-route.yaml
httproute.gateway.networking.k8s.io/load-balancing-route created

Let's review the HTTPRoute manifest.
root@server:~# yq load-balancing-http-route.yaml
---
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: load-balancing-route
  namespace: gamma
spec:
  parentRefs:
    - group: ""
      kind: Service
      name: echo
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /load-balancing
      backendRefs:
        - kind: Service
          name: echo-v1
          port: 80
          weight: 50
        - kind: Service
          name: echo-v2
          port: 80
          weight: 50

This Rule is essentially a simple L7 proxy route: for HTTP traffic with a path starting with /load-balancing, forward the traffic over to the echo-v1 and echo-v2 Services.
backendRefs:
  - kind: Service
    name: echo-v1
    port: 80
    weight: 50
  - kind: Service
    name: echo-v2
    port: 80
    weight: 50

Let's double check that traffic is evenly split across the two services by running a loop and counting the requests. Run the following script.
root@server:~# kubectl -n gamma exec -it client -- bash -c '
for _ in {1..500}; do
  curl -s -k "http://echo/load-balancing" >> curlresponses.txt;
done
grep -o "Hostname=echo-v1" curlresponses.txt | sort | uniq -c
grep -o "Hostname=echo-v2" curlresponses.txt | sort | uniq -c
'
    251 Hostname=echo-v1
    249 Hostname=echo-v2

This time, we will be applying a different weight.

Using the </> Editor tab, edit the load-balancing-http-route.yaml file. Replace the weights from 50 for both echo-1 and echo-2 to 90 for echo-1 and 10 for echo-2.

Then go back to the >_ Terminal tab and apply the manifest again:
root@server:~# kubectl apply -f load-balancing-http-route.yaml
httproute.gateway.networking.k8s.io/load-balancing-route configured
root@server:~# kubectl -n gamma exec -it client -- bash -c '
for _ in {1..500}; do
  curl -s -k "http://echo/load-balancing" >> curlresponses9010.txt;
done
grep -o "Hostname=echo-v1" curlresponses9010.txt | sort | uniq -c
grep -o "Hostname=echo-v2" curlresponses9010.txt | sort | uniq -c
'
    439 Hostname=echo-v1
     61 Hostname=echo-v2

Verify that the responses are spread with about 90% of them to echo-1 and about 10% of them to echo-2.


HTTPRoutes support timeouts as an experimental feature. Let's apply that to the /v1 path of the gamma-route we deployed earlier.

First, check the response headers of the service:
root@server:~# kubectl -n gamma exec -it client -- curl http://echo/v1

There is no header mentioning timeouts at this point.

Let's add a timeout of 10 ms to the route. Using the </> Editor tab, edit the gamma-route.yaml file. Edit the first rule, which matches /v1 to add a timeouts section with request: 10ms.

The first matches section should now look like this:
  - matches:
    - path:
        type: Exact
        value: /v1
    backendRefs:
    - name: echo-v1
      port: 80
    timeouts:
      request: 10ms

Then go back to the >_ Terminal tab and apply the manifest again:
root@server:~# kubectl apply -f gamma-route.yaml
httproute.gateway.networking.k8s.io/gamma-route configured
      
Now, check the service again:
root@server:~# kubectl -n gamma exec -it client -- curl http://echo/v1

root@server:~# kubectl -n gamma exec -it client -- curl http://echo/v1
ServiceVersion=
ServicePort=8080
Host=echo
URL=/v1
Method=GET
Proto=HTTP/1.1
IP=10.244.2.58
RequestHeader=Accept:*/*
RequestHeader=User-Agent:curl/8.7.1
RequestHeader=X-Envoy-Expected-Rq-Timeout-Ms:10
RequestHeader=X-Envoy-Internal:true
RequestHeader=X-Forwarded-For:10.244.2.217
RequestHeader=X-Forwarded-Proto:http
RequestHeader=X-Request-Id:0a506cbc-fbf7-448f-a177-888ee45f88df
Hostname=echo-v1-6775745567-5jqd7      

Edit the file again in the </> Editor, set the timeout to 1ms and apply the manifest again in the >_ Terminal.

root@server:~# kubectl apply -f gamma-route.yaml
httproute.gateway.networking.k8s.io/gamma-route configured

Finally, check the service once more:
root@server:~# kubectl -n gamma exec -it client -- curl http://echo/v1
upstream request timeout
Given the very low threshold, you should now get a timeout most of the time (try multiple times if you don't):
upstream request timeout


---
apiVersion: gateway.networking.k8s.io/v1beta1
kind: Gateway
metadata:
  name: shared-gateway
  namespace: infra-ns
spec:
  gatewayClassName: cilium
  listeners:
    - name: shared-http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: Selector
          selector:
            matchLabels:
              shared-gateway-access: "true"       
---
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: XXXX
  namespace: exam
spec:
  parentRefs:
    - name: XXXX
      namespace: XXXX
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /exam
      filters:
        - type: RequestHeaderModifier
          requestHeaderModifier:
            set:
              - name: XXXX
                value: XXXX
      backendRefs:
        - kind: Service
          name: echo-exam
          port: 9080
For this final challenge, you will need to use two of the Gateway API features explored in this lab.

The task requires you to set the value of the x-request-id header to the value exam-header-value. This should only apply to HTTP Requests bound to an exam namespace that can only be reached via the shared Gateway created earlier (on the exam path).

    A namespace exam was created in the background.

    An echoserver-exam Deployment and an echo-exam Service have also been deployed in the background.

    A template HTTPRoute has been pre-created in the background (exam-httproute.yaml). Feel free to use the </> Editor to modify it.

    You will need to update the XXXX fields with the correct values.

    Make sure you apply the manifests.

    The final exam script will check for the value of curl --fail -s http://$GATEWAY/exam | jq -r '.request.headers."x-request-id"', with $GATEWAY the IP Address assigned to the Gateway,. If the value returned is exam-header-value, you will have successfully completed the lab.

apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: exam-httproute
  namespace: exam
spec:
  parentRefs:
    - name: shared-gateway
      namespace: infra-ns
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /exam
      filters:
        - type: RequestHeaderModifier
          requestHeaderModifier:
            set:
              - name: x-request-id
                value: exam-header-value
      backendRefs:
        - kind: Service
          name: echo-exam
          port: 9080