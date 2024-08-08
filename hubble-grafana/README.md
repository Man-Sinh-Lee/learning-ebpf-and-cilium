Golden Signals with Hubble and Grafana

What are the four Golden Signals?

The 4 general categories of signals that matter to any systems —especially a Kubernetes environment— include latency, throughput, errors, and saturation. Each has its own individual definition of health and which metrics and analytics define those thresholds. The origins of this came from the popular Google SRE book.

Latency

Most often represented as response time in milliseconds (ms) at the application layer.

Application response time is affected by latency across all of the core system resources including network, storage, processor (CPU), and memory.

Latency at the application layer also needs to be correlated to latency and resource usage that may be happening internally within the application processes, between pods/services, across the network/mesh etc.

Latency, or the delay between a user's request and the system's response, is a critical factor in determining the user experience and system performance.

High latency can lead to frustration and decreased user satisfaction, while low latency can improve user engagement and retention.

By monitoring and optimizing latency, you can ensure that your system is performing at its best and providing a seamless user experience.

Throughput

Sometimes referred to as traffic, throughput is the volume and types of requests that are being sent and received by services and applications from within and from outside a Kubernetes environment.

Throughput metrics include examples like web requests, API calls, and is described as the demand commonly represented as the number of requests per second.

It should be measured across all layers to identify requests to and from services, and also which I/O is going further down to the node.

Errors

The number of requests (traffic) which are failing, often represented either in absolute numbers or as the percentage of requests with errors versus the total number of requests.

There may be errors that happen due to application issues, possible misconfiguration, and some errors happen as defined by policy.

Policy-driven error may indicate accidental misconfiguration or potentially a malicious process.

Saturation

The overall utilization of resources including CPU (capacity, quotas, throttling), memory (capacity, allocation), storage (capacity, allocation, and I/O throughput), and network.

Some resources saturate linearly (e.g. storage capacity) while others (memory, CPU, and network) fluctuate much more with the ephemeral nature of containerized applications.

Network saturation is a great example of the complexity of monitoring Kubernetes because there is node networking, service-to-service network throughput, and once a service mesh is in place, there are more paths, and potentially more bottlenecks that can be saturated.

Why is Observability in Kubernetes a Multi-Dimensional Challenge?

Our 4 golden signals for observing Kubernetes are especially interesting (and challenging) because each has its own measurement of health. An aggregate combination of golden signals defines the overall system health. Both visually and mathematically, this is a multi-dimensional challenge.

How often do SRE and container Ops teams get asked “what’s going on with Application X?” without having a specific application monitoring trigger or alert? Or even when certain alerts are appearing but aren’t the singular reason an application is negatively affected.

There could be a combination of latency, utilization, and errors that have to be correlated to the root cause.

cat cilium-values.yaml

httpV2:exemplars=true;labelsContext=source_ip,source_namespace,source_workload,destination_ip,destination_namespace,destination_workload,traffic_direction;sourceContext=workload-name|reserved-identity;destinationContext=workload-name|reserved-identity
    examplars=true will let us display OpenTelemetry trace points from application traces as an overlay on the Grafana graphs
    labelsContext is set to add extra labels to metrics including source/destination IPs, source/destination namespaces, source/destination workloads, as well as traffic direction (ingress or egress)
    sourceContext sets how the source label is built, in this case using the workload name when possible, or a reserved identity (e.g. world) otherwise
    destinationContext does the same for destinations


Application Components

Here is an overview of the jobs-app components:

    coreapi is a RESTful HTTP main API used by the resumes, recruiter, and jobposting components. It manages creating, retrieving and listing resumes and jobpostings from Elasticsearch.

    crawler will periodically generate random resumes and sends them to loader via gRPC.

    loader is a gRPC service which submits resumes into the resumes kafka topic to be processed by the resumes component.

    resumes subscribes to the resumes kafka topic, and submits the resumes to the coreapi, which stores them in Elasticsearch.

    elasticsearch used to store resumes, job postings, and analytics.

    kafka takes resumes in from loader in the resumes topic.

    jobposting uses the coreapi to lists job postings on a web UI and allows applicants to submit their resumes.

The jobs-app application comes with a set of Cilium Network Policy resources which enable Layer 7 visibility using Cilium's Envoy Proxy.
kubectl -n tenant-jobs get cnp

This policy ensures all traffic is allowed by default. While this is not the best practice from a security point of view, it makes the setup easier for this lab. Check the Zero Trust Visibility lab for more information on a best approach to securing a namespace.
kubectl -n tenant-jobs get cnp allow-all-within-namespace -o yaml

This policy allows pods in the namespace to access the Kube DNS service. It also adds a DNS rule to get the DNS traffic proxied through Cilium's DNS proxy, which makes it possible to resolve DNS names in Hubble flows.
kubectl -n tenant-jobs get cnp dns-visibility -o yaml

This third policy allows egress traffic to the world identities (everything outside the cluster) on port 80 and forces it through Cilium's Envoy proxy for Layer 7 visibility.
kubectl -n tenant-jobs get cnp l7-egress-visibility -o yaml

This last policy allows ingress traffic from all pods in the namespace to ports 9080, 50051, and 9200 in TCP. It forces this traffic through Cilium's Envoy proxy for Layer 7 visibility.
kubectl -n tenant-jobs get cnp l7-ingress-visibility -o yaml

Rollout check deployment status:
kubectl rollout -n tenant-jobs status deployment/coreapi
kubectl rollout -n tenant-jobs status deployment/crawler
kubectl rollout -n tenant-jobs status deployment/jobposting
kubectl rollout -n tenant-jobs status deployment/loader
kubectl rollout -n tenant-jobs status deployment/recruiter
kubectl rollout -n tenant-jobs status deployment/resumes

In this lab, we set up a Grafana server with a data source pointing to Prometheus and imported the L7 HTTP metrics Dashboard to visualize Hubble related metrics.
Notice how you now have access to a wide variety of HTTP metrics:

    Incoming Request Volume
    Incoming Request Success Rate
    Request Duration
    Requests by Response Code

Notice how you can see the metrics by source (second section, Requests by Source, with three panels) or by destination (third section, Requests by Destination, with three panels). This would enable you to find where the anomaly resides.

In the Requests by Source section, check the HTTP Request Duration by Source. Notice there are several statistics available: P50, P95 and P99. We usually describe latency with its 99th percentile, or P99.

If our HTTP-based web application has a P99 latency of less than or equal to 2 milliseconds, then it mean that 99% of web calls are serviced with a response under 2 milliseconds. Conversely, only 1% of calls get a delayed response of over 2 milliseconds.

In the next challenge, we will increase traffic in the application and visualize the changes on the dashboard.

From the 🔗 📈 Grafana dashboard, find the Destination Workload variable at the top of the page, and make sure loader is selected.

Next, increase the request volume by configuring crawler to generate more resumes, and running more replicas of the crawler and resumes deployments.

helm upgrade jobs-app ./helm/jobs-app.tgz \
    --namespace tenant-jobs \
    --reuse-values \
    --set crawler.replicas=3 \
    --set crawler.crawlFrequencyLowerBound=0.2 \
    --set crawler.crawlFrequencyUpperBound=0.5 \
    --set resumes.replicas=2

Going back to 🔗 📈 Grafana, watch the Incoming Requests by Source and Response Code panel. You should see the request rate increase as a result of the increased resume generation rates by crawler, as the crawler submit resumes to the loader. The rate should stabilize around 3 req/s.

Now select coreapi as the Destination Workload variable at the top of the page.

In the Incoming Requests by Source and Response Code view, you should see the request rate increase for coreapi as well. The rate should stabilize around 4 req/s.

Let's deploy a new jobs-app configuration and use our metrics to see the change in the request error rate
helm upgrade jobs-app ./helm/jobs-app.tgz \
  --namespace tenant-jobs \
  --reuse-values \
  --set coreapi.errorRate=0.5 \
  --set coreapi.sleepRate=0.01

Now go back into 🔗 📈 Grafana and ensure coreapi is selected as Destination Workload.

After about a minute, you will see the Incoming Request Success Rate (non-5xx responses) By Source graph start to go down.

Shortly after, a new series will appear in the Incoming Requests by Source and Response Code graph, tracking 500 HTTP codes (internal errors).

Finally, the Incoming Request Success Rate (non-5xx responses) panel should stabilize around 93%.


Next, we'll upgrade the jobs-app setup to increase sleep between responses, so as to make the request duration longer.
helm upgrade jobs-app ./helm/jobs-app.tgz \
  --namespace tenant-jobs \
  --reuse-values \
  --set coreapi.sleepRate=0.2 \
  --set coreapi.sleepLowerBound=0.5 \
  --set coreapi.sleepUpperBound=5.0

Go back into 🔗 📈 Grafana and select the coreapi as Destination Workload.

After about a minute, you will see the values in the HTTP Request Duration by Source graph increase to around 800ms.

Notice that the three curves for P50, P95, and P99 have quite distinct values. This means that there is an increased latency, but only for a small ratio of requests.

The screenshot above for example shows that while 99% of the requests are served with a latency under ~1s (P99 curve), there's 95% of them under 600ms (P95 curve) and 50% of them are much faster (P50 curve).

Click on the tenant-jobs/resumes P50 label under the graph to view only these values:
You can see that 50% of the requests are actually taking ~30ms to be served.

Inspect the minimum, maximum, and mean values for each series in the legend of the graph. This can be useful to identify an issue with latency.

In the next challenge, we will see how we can correlate the request duration graphs with OpenTelemetry traces produced by the application.

Tracing Integration

If your application exports tracing headers, Hubble can be configured to extract these trace IDs from HTTP headers and export them with the Hubble HTTP metrics as exemplars which allow us to link from metrics to traces in Grafana.

Grafana Tempo and the OpenTelemetry Operator and Collector have been added to the cluster.

Upgrade the jobs-app setup to enable OpenTelemetry tracing.
helm upgrade jobs-app ./helm/jobs-app.tgz \
  --namespace tenant-jobs \
  --reuse-values \
  --set tracing.enabled=true

This will make the application produce OpenTelemetry traces.

When Layer 7 data is processed by Cilium's Envoy proxy, Hubble will be able to extract the Trace IDs from HTTP headers and correlate them with Hubble's data to enrich the Grafana dashboards.

Go back into 🔗 📈 Grafana and ensure that coreapi is selected as the Destination Workload.

In the HTTP Request Duration by Source/Destination panels, you should start to see the exemplars showing up as dots alongside the line graph visualizations.
Each one of these exemplars represents the duration of a single request and links to a trace ID.

Click on the title of the HTTP Request Duration by Source panel and choose 👁️ View. You will see a larger version of the graph, which will make it easier to visualize the trace points.

Next, click the "Query with Tempo" button at the bottom of the popup. This will allow you to visualize the OpenTelemetry trace for the application.
Notice that there a long blank between the end of the loader request (line 3, with a dark pink marker) and the beginning of the resumes reply (line 4, with a very light pink marker). This explains why this request has a high latency (which is the case since you chose an exemplar from the top of the graph).

On top of the Trace View, there is a Node graph panel. Open it to view the directed graph showing where time was spent in the transaction.

You are very likely to see errors with the coreapi service in the trace. The resumes component is trying to connect to coreapi but the requests don't go through. resumes actually retries the connection multiple times, resulting in multiple errors until it succeeds.

If you open the Node graph view, you will the retries there as well: