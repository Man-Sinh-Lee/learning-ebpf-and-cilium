cilium install --helm-values values-migration.yaml --dry-run-helm-values >> values-initial.yaml
cat values-initial.yaml
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium --namespace kube-system --values values-initial.yaml
kubectl -n kube-system get ciliumnodeconfigs.cilium.io cilium-default -o yaml

kubectl cordon $NODE
kubectl drain $NODE --ignore-daemonsets
kubectl label node $NODE --overwrite "io.cilium.migration/cilium-default=true"
kubectl -n kube-system delete pod --field-selector spec.nodeName=$NODE -l k8s-app=cilium
kubectl -n kube-system rollout status ds/cilium -w
docker restart $NODE
kubectl get cn kind-worker -o jsonpath='{.spec.ipam.podCIDRs[0]}'
kubectl run --attach --rm --restart=Never \
verify  --overrides='{"spec": {"nodeName": "'$NODE'", "tolerations": [{"operator": "Exists"}]}}'   \
--image alpine -- /bin/sh -c 'ip addr' | grep 10.245 -B 2
NGINX=($(kubectl get pods -l app=nginx -o=jsonpath='{.items[0].status.podIP}'))
echo $NGINX
kubectl run --attach --rm --restart=Never verify  \
--overrides='{"spec": {"nodeName": "'$NODE'", "tolerations": [{"operator": "Exists"}]}}'   \
--image alpine/curl --env NGINX=$NGINX -- /bin/sh -c 'curl -s $NGINX '

NODE="kind-worker2"
kubectl cordon $NODE

kubectl drain $NODE --ignore-daemonsets
kubectl get pods -o wide
kubectl label node $NODE --overwrite "io.cilium.migration/cilium-default=true"
kubectl -n kube-system delete pod --field-selector spec.nodeName=$NODE -l k8s-app=cilium
kubectl -n kube-system rollout status ds/cilium -w
docker restart $NODE
kubectl uncordon $NODE

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
cilium install --helm-values values-initial.yaml --helm-set operator.unmanagedPodWatcher.restart=true \
--helm-set cni.customConf=false --helm-set policyEnforcementMode=default --dry-run-helm-values >> values-final.yaml
diff values-initial.yaml values-final.yaml

helm upgrade --namespace kube-system cilium cilium/cilium --values values-final.yaml
kubectl -n kube-system rollout restart daemonset cilium
cilium status --wait
kubectl delete -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml