# Kafka K8S Testing

## Requirements
### CLI Tools
* kubectl cli (v1.34 https://dl.k8s.io/release/v1.34.0/bin/linux/amd64/kubectl)
* vcf cli (v9.0.0)
* helm cli (v3.19 https://get.helm.sh/helm-v3.19.0-linux-amd64.tar.gz)

## Procedure

### 1. Get files
```shell
git clone https://github.com/cleeistaken/kafka-k8s-test.git
```

### 2. Set variables
```shell
# Update with correct values!
SUPERVISOR_IP="10.0.0.1"
SUPERVISOR_USERNAME="user@domain"
NAMESPACE_NAME="modern-app"
CLUSTER_NAME="modern-app-vks"
```
### 3. Clean kubectl and vcf configs
```shell
rm ~/.kube/config
rm -rf ~/.config/vcf/
```

### 4. Login to supervisor
```shell
# Login and get contexts
kubectl vsphere login --server=$SUPERVISOR_IP  --insecure-skip-tls-verify=true -u $SUPERVISOR_USERNAME
kubectl config get-contexts
```

### 5. Create context on supervisor
```shell
# Create a context named 'pt'
vcf context create pt --endpoint $SUPERVISOR_IP --insecure-skip-tls-verify -u $SUPERVISOR_USERNAME 
vcf context use pt
```

### 6. Create VKS cluster
```shell
# Create a VKS cluster as defined in vks.yaml
kubectl apply -f vks.yaml
```

### 7. Connect to VKS cluster
```shell
# Connect to the VKS cluster
vcf context create vks --endpoint $SUPERVISOR_IP --insecure-skip-tls-verify -u $SUPERVISOR_USERNAME --workload-cluster-namespace=$NAMESPACE_NAME --workload-cluster-name=$CLUSTER_NAME
vcf context use vks:$CLUSTER_NAME
```

### 8. Create namespace
```shell
# Create a namespace on the VKS cluster
kubectl create namespace strimzi
kubectl config set-context --current --namespace=strimzi
```

### 9. Deploy operator
```shell
# Install the strimzi operator
helm install strimzi-cluster-operator oci://quay.io/strimzi-helm/strimzi-kafka-operator
```

### 10. Create kafka cluster
```shell
# Create kafka cluster as defined in kafka-cluster.yaml
kubectl apply -f kafka-cluster.yaml
```

### 11. Create client
```shell
kubectl apply -f client-pod.yaml
```

### 12. Copy test script
```shell
kubectl cp run-producer.sh ubuntu:/opt/kafka_2.13-3.9.1/bin
```

### 13. Run test
```shell
kubectl exec -it ubuntu -- /bin/bash
cd /opt/kafka_2.13-3.9.1/bin
chmod a+x run-producer.sh
./run-producer.sh
```
