# Kafka K8S Testing

## Requirements
### CLI Tools
* kubectl cli v1.34: https://dl.k8s.io/release/v1.34.0/bin/linux/amd64/kubectl
* vcf cli v9.0.1: https://packages.broadcom.com/artifactory/vcf-distro/vcf-cli/linux/amd64/v9.0.1/
* helm cli v3.19: https://get.helm.sh/helm-v3.19.0-linux-amd64.tar.gz

## OCP Procedure

### 1. Get files
```shell
git clone https://github.com/cleeistaken/kafka-k8s-test.git
```

### 2. Create Project
```shell
# create strimi namespace and set it as current context
oc new-project strimzi
```

### 3. Label Nodes
```shell
# label each node to prepare for rack awareness deployment
oc label node master-0.ocp-pt.showcase.tmm.broadcom.lab topology.kubernetes.io/region=rack1
oc label node master-1.ocp-pt.showcase.tmm.broadcom.lab topology.kubernetes.io/region=rack2
oc label node master-2.ocp-pt.showcase.tmm.broadcom.lab topology.kubernetes.io/region=rack3
oc label node master-3.ocp-pt.showcase.tmm.broadcom.lab topology.kubernetes.io/region=rack4
```

### 4. Deploy operator
```shell
# Install the strimzi operator
helm install strimzi-cluster-operator oci://quay.io/strimzi-helm/strimzi-kafka-operator
```

### 5. Create kafka cluster
```shell
# Create kafka cluster as defined in kafka-cluster.yaml
kubectl apply -f kafka-cluster.yaml
```

### 6. Create client
```shell
kubectl apply -f client-pod.yaml
```

### 7. Copy test script
```shell
kubectl cp run-producer.sh ubuntu:/opt/kafka_2.13-3.9.1/bin
```

### 8. Run test
```shell
# Log into the client pod
kubectl exec -it ubuntu -- /bin/bash

# Then paste this in the client pod shell
cd /opt/kafka_2.13-3.9.1/bin
chmod a+x run-producer.sh
./run-producer.sh
```

## References
* https://kubernetes.io/docs/tasks/tools/
* https://helm.sh/docs/intro/install/
* https://packages.broadcom.com/artifactory/vcf-distro/vcf-cli/