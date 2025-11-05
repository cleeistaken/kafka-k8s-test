## Requirements
* kubectl cli
* vcf cli
* helm cli


## Procedure

### 1. Set variables
```shell
SUPERVISOR_IP="10.0.0.1"
SUPERVISOR_USERNAME="user@domain"
NAMESPACE_NAME="modern-app"
CLUSTER_NAME="modern-app-vks"
```

### 2. Create context on supervisor
```shell
# Create a context named 'pt'
vcf context create pt --endpoint $SUPERVISOR_IP --insecure-skip-tls-verify -u $SUPERVISOR_USERNAME 
vcf context use pt
```

### 3. Create VKS cluster
```shell
# Create a VKS cluster as defined in vks.yaml
kubectl apply -f vks.yaml
```

### 4. Connect to VKS cluster
```shell
# Connect to the VKS cluster
vcf context create vks --endpoint $SUPERVISOR_IP --insecure-skip-tls-verify -u $SUPERVISOR_USERNAME --workload-cluster-namespace=$NAMESPACE_NAME --workload-cluster-name=$CLUSTER_NAME
vcf context use vks:$CLUSTER_NAME
```

### 5. Create namespace
```shell
# Create a namespace on the VKS cluster
kubectl create namespace strimzi
kubectl config set-context --current --namespace=strimzi
```

### 6. Deploy operator
```shell
# Install the strimzi operator
helm install strimzi-cluster-operator oci://quay.io/strimzi-helm/strimzi-kafka-operator
```

### 7. Create kafka cluster
```shell
# Create kafka cluster as defined in kafka-cluster.yaml
kubectl apply -f kafka-cluster.yaml
```

### 8. Create client
```shell
kubectl apply -f client-pod.yaml
```

### 9. Copy test script
```shell
kubectl cp run-producer.sh ubuntu:/opt/kafka_2.13-3.9.1/bin
```

### 10. Run test
```shell
kubectl exec -it ubuntu -- /bin/bash
cd /opt/kafka_2.13-3.9.1/bin
chmod a+x run-producer.sh
./run-producer.sh
```
