kubectl apply -f bookinfo.yaml
kubectl apply -f basic-ingress.yaml
kubectl apply -f basic-ingress.yaml
INGRESS_IP=$(kubectl get ingress basic-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo $INGRESS_IP
curl -so /dev/null -w "%{http_code}\n" http://$INGRESS_IP/
curl -so /dev/null -w "%{http_code}\n" http://$INGRESS_IP/details/1
curl -so /dev/null -w "%{http_code}\n" http://$INGRESS_IP/ratings 
kubectl patch svc cilium-ingress-basic-ingress --patch '{"spec": {"type": "LoadBalancer", "ports": [ { "name": "http", "port": 80, "protocol": "TCP", "targetPort": 80, "nodePort": 32042 } ] } }'
hubble observe --namespace default
hubble observe --namespace default -o jsonpb | jq
kubectl annotate pod -l app=productpage --overwrite io.cilium.proxy-visibility="<Ingress/9080/TCP/HTTP>"
kubectl apply -f https://docs.isovalent.com/public/http-ingress-visibility.yaml
hubble observe --namespace default
hubble observe --protocol http --label app=reviews --port 9080
kubectl get ingress
INGRESS_IP=$(kubectl get ingress grpc-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
grpcurl -plaintext -proto ./demo.proto $INGRESS_IP:80 hipstershop.CurrencyService/GetSupportedCurrencies
grpcurl -plaintext -proto ./demo.proto $INGRESS_IP:80 hipstershop.ProductCatalogService/ListProducts
mkcert '*.cilium.rocks'
kubectl create secret tls demo-cert \
  --key=_wildcard.cilium.rocks-key.pem \
  --cert=_wildcard.cilium.rocks.pem
kubectl delete ingress basic-ingress
kubectl delete ingress grpc-ingress
kubectl get ingress tls-ingress
INGRESS_IP=$(kubectl get ingress tls-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo $INGRESS_IP
cat << EOF >> /etc/hosts
${INGRESS_IP} bookinfo.cilium.rocks
${INGRESS_IP} hipstershop.cilium.rocks
EOF

mkcert -install
curl -s https://bookinfo.cilium.rocks/details/1 | jq
grpcurl -proto ./demo.proto hipstershop.cilium.rocks:443 hipstershop.ProductCatalogService/ListProducts | jq