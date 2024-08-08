helm upgrade --install cilium cilium/cilium -n kube-system --set kubeProxyReplacement=true --set loadBalancer.l7.backend=envoy --set-string extraConfig.enable-envoy-config=true
cilium config view | grep -w "kube-proxy"
kubectl apply -f sw-pods.yaml
kubectl rollout status deployment/deathstar
kubectl get pod xwing
kubectl exec xwing -- curl --max-time 1 -s -X POST deathstar.default.svc.cluster.local/v1/request-landing
hubble observe --to-pod default/deathstar
kubectl apply -f l4-policy.yaml
kubectl get ciliumnetworkpolicy rule1 -o yaml | yq .spec
kubectl exec xwing -- curl --max-time 1 -s -X POST deathstar.default.svc.cluster.local/v1/request-landing
kubectl exec tiefighter -- curl --max-time 1 -s -X POST deathstar.default.svc.cluster.local/v1/request-landing
hubble observe --to-pod default/deathstar