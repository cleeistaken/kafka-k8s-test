# Kafka K8S Testing

## Requirements
* kubectl cli (v1.30.10+vmware.1-fips)
* vcf cli (v9.0.0)
* helm cli (v4.0.0-rc.1)


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

### 3. Create context on supervisor
```shell
# Create a context named 'pt'
vcf context create pt --endpoint $SUPERVISOR_IP --insecure-skip-tls-verify -u $SUPERVISOR_USERNAME 
vcf context use pt
```

### 4. Create VKS cluster
```shell
# Create a VKS cluster as defined in vks.yaml
kubectl apply -f vks.yaml
```

### 5. Connect to VKS cluster
```shell
# Connect to the VKS cluster
vcf context create vks --endpoint $SUPERVISOR_IP --insecure-skip-tls-verify -u $SUPERVISOR_USERNAME --workload-cluster-namespace=$NAMESPACE_NAME --workload-cluster-name=$CLUSTER_NAME
vcf context use vks:$CLUSTER_NAME
```

### 6. Create namespace
```shell
# Create a namespace on the VKS cluster
kubectl create namespace strimzi
kubectl config set-context --current --namespace=strimzi
```

### 7. Deploy operator
```shell
# Install the strimzi operator
helm install strimzi-cluster-operator oci://quay.io/strimzi-helm/strimzi-kafka-operator
```

### 8. Create kafka cluster
```shell
# Create kafka cluster as defined in kafka-cluster.yaml
kubectl apply -f kafka-cluster.yaml
```

### 9. Create client
```shell
kubectl apply -f client-pod.yaml
```

### 10. Copy test script
```shell
kubectl cp run-producer.sh ubuntu:/opt/kafka_2.13-3.9.1/bin
```

### 11. Run test
```shell
kubectl exec -it ubuntu -- /bin/bash
cd /opt/kafka_2.13-3.9.1/bin
chmod a+x run-producer.sh
./run-producer.sh
```
