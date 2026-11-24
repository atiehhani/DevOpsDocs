## Air-Gap Install for AWX


To install AWX on a k3s cluster running on Rocky Linux 9.5,
you need to first install and configure k3s,
then use the AWX Operator for deployment.  
The key steps include disabling SELinux enforcement,
opening the necessary firewall ports, installing k3s,
and finally deploying AWX via Kustomize.  

### 1. System Preparation (Rocky Linux 9.5)
Before installing k3s, you need to adjust system settings to ensure compatibility.

Disable SELinux Enforcing Mode:   
k3s may encounter network issues under SELinux Enforcing mode. 
It is recommended to set it to Permissive mode.
```bash
sudo setenforce 0
sudo sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
```
Configure Firewall: Open the ports required by Kubernetes and AWX.
```bash
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=30000-32767/tcp
# Trust k3s internal network segments
sudo firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16
sudo firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16
sudo firewall-cmd --reload
```
### 2. Install k3s
### 3. Deploy AWX Operator



**AWX Operator:** quay.io/ansible/awx-operator:2.19.1 → 192.168.227.138:8082/awx-operator:2.19.1  
**kube-rbac-proxy:** gcr.io/kubebuilder/kube-rbac-proxy:v0.15.0 (or corresponding version) → 192.168.227.138:8082/
kube-rbac-proxy:v0.15.0  
**AWX main application:** quay.io/ansible/awx:latest (or version matching Operator) → 192.168.227.138:8082/  awx:latest  
**AWX EE:** quay.io/ansible/awx-ee:latest → 192.168.227.138:8082/awx-ee:latest  
**PostgreSQL:** docker.io/postgres:12 → 192.168.227.138:8082/postgres:12  
**Redis:** docker.io/redis:latest → 192.168.227.138:8082/redis:latest  
**CentOS (init container):** quay.io/centos/centos:stream9 → 192.168.227.138:8082/centos:stream9  
#### 1)
```bash
wget http://192.168.227.138:8081/repository/github/k3s-io/k3s/releases/download/v1.37.1%2Bk3s1/k3s-airgap-images-amd64.tar.gz
```
#### 2)
```bash
 mkdir -p /var/lib/rancher/k3s/agent/images/
 ```
#### 3)
```bash
 cp k3s-airgap-images-amd64.tar /var/lib/rancher/k3s/agent/images/
 ```
AWX is now deployed via the Operator. You need to create a directory and define it using a kustomization.yaml file.

#### 4)
```bash
 mkdir -p ~/awx-on-k3s && cd ~/awx-on-k3s
 ```
 #### 5) Create your new namespace for awx
```bash
kubectl create namespace awx
```
#### 6) kustomization.yaml
```bash
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./awx-operator/config/default
  - ./awx-demo.yml
  - ./pv.yaml
  - ./pvc.yaml
  - ./pv-fetch.yaml
  - ./pvc-fetch.yaml

images:
  - name: quay.io/ansible/awx-operator
    newName: 192.168.227.138:8089/ansible/awx-operator
    newTag: 2.19.1
  - name: gcr.io/kubebuilder/kube-rbac-proxy
    newName: 192.168.227.138:8089/brancz/kube-rbac-proxy
    newTag: v0.15.0
namespace: awx
```
#### 7) awx-demo.yml
```bash
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-demo
spec:
  service_type: nodeport
  nodeport_port: 30080
  
  # PostgreSQL (already configured)
  postgres_image: 192.168.227.138:8089/sclorg/postgresql-15-c9s
  postgres_image_version: latest

  # AWX Main Image
  image: 192.168.227.138:8089/ansible/awx
  image_version: "24.6.1"

  # Redis
  redis_image: 192.168.227.138:8089/redis
  redis_image_version: "7"

  init_container_image: 192.168.227.138:8089/ansible/awx-ee
  init_container_image_version: "24.6.1"

  # Execution Environment
  ee_images:
    - name: awx-ee
      image: 192.168.227.138:8089/ansible/awx-ee:24.6.1
  control_plane_ee_image: 192.168.227.138:8089/ansible/awx-ee:24.6.1

  projects_persistence: true
    #  projects_existing_claim: 8Gi
  projects_existing_claim: awx-projects-claim
  projects_storage_access_mode: ReadWriteOnce

  init_projects_container_image: 192.168.227.138:8089/centos/centos:stream9
```
#### 8) awx.yaml
```bash
apiVersion: awx.ansible.com/v1betal
kind: AWX
metadata:
  name: awx
    #  namespace: awx
spec:
  service_type: NodePort
  nodeport_port: 30080
  ingress_type: none

  postgres_data_volume_init: true
  postgres_storage_class: awx-postgres-volume
  postgres_storage_requirements:
    requests:
      storage: 1Gi

  projects_persistence: true
  projects_existing_claim: awx-projects-claim

  web_replicas: 1
  task_replicas: 1

  extra_volumes: |
    - name: fetch-data
      persistentVolumeClaim:
        claimName: awx-fetch-claim

  ee_extra_volume_mounts: |
    - name: fetch-data
      mountPath: /fetched
```
Apply the configuration to start deployment:  
Ensure that both files are in the same directory
```bash
kubectl apply -k .
```
After a few minutes, check the Pod status:
```bash
kubectl get pods -n awx
```

default admin user password:
```bash
kubectl get secret awx-demo-admin-password -n awx -o jsonpath="{.data.password}" | base64 --decode
```
Execute Deployment and Retrieve Password



