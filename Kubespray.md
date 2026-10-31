# Kubespray Offline Deployment Guide (HA Cluster with Nexus Cache)

This document provides a comprehensive, step-by-step setup guide for deploying a High Availability (HA) Kubernetes cluster using **Kubespray** on **Rocky Linux** in an offline/air-gapped environment powered by **Nexus Repository Manager** as a pull-through cache.

---

## 1. Architecture & Infrastructure Topology

### Infrastructure Map

```

                                       
              ┌──────────────────────────┼──────────────────────────┐
              │                          │                          │
     ┌────────┴────────┐        ┌────────┴────────┐        ┌────────┴────────┐
     │    master1      │        │    master2      │        │    master3      │
     │  .131 (Control) │        │  .133 (Control) │        │  .135 (Control) │
     │  K8s API + etcd │        │  K8s API + etcd │        │  K8s API + etcd │
     └────────┬────────┘        └────────┬────────┘        └────────┬────────┘
              │                          │                          │
              └───────────────┬──────────┴───────────────┬──────────┘
                              │     Calico / IPVS        │
     ┌────────────────────────┼──────────────────────────┼────────────────────────┐
     │                        │                          │                        │
┌────┴─────┐           ┌──────┴─────┐            ┌───────┴───┐            ┌───────┴───┐
│ worker1  │           │  worker2   │            │  worker3  │            │  worker4  │
│  .132    │           │   .134     │            │   .136    │            │   .137    │
└────┬─────┘           └──────┬─────┘            └───────┬───┘            └───────┬───┘
     │                        │                          │                        │
     └───────────────┬────────┴──────────────────────────┴───────────────┬────────┘
                     │   Image pulls (8082) / Binary downloads (8081)    │
                     │          Upstream DNS + NTP: 192.168.247.x        │
                     │                                                   │
          ┌──────────┴───────────────────────────────────────────────────┴─────────┐
          │                 Nexus Repository Manager (192.168.227.138)            │
          │   Docker Group :8082  (k8s / quay / gcr / ghcr / dockerhub proxies)   │
          │   Raw Proxies   :8081  (dl.k8s.io / github / googleapis / helm)       │
          └───────────────────────────────────────────────────────────────────────┘
```

### IP Reference Table

| Hostname / Component | IP Address | Role / Description |
| :--- | :--- | :--- |
| **master1** | `192.168.227.131` | K8s Control Plane + etcd Member 1 |
| **master2** | `192.168.227.133` | K8s Control Plane + etcd Member 2 |
| **master3** | `192.168.227.135` | K8s Control Plane + etcd Member 3 |
| **worker1** | `192.168.227.132` | Kubernetes Worker Node 1 |
| **worker2** | `192.168.227.134` | Kubernetes Worker Node 2 |
| **worker3** | `192.168.227.136` | Kubernetes Worker Node 3 |
| **worker4** | `192.168.227.137` | Kubernetes Worker Node 4 |
| **Nexus Repository** | `192.168.227.138` | Docker Registry Group (Port 8082), Raw Proxies (Port 8081) |
| **Internal DNS / NTP** | `192.168.247.247`, `192.168.247.101` | Core Infrastructure DNS and NTP servers |

---

## 2. Environment Preparation

Run the following commands on the Ansible deployment machine:

# Hostname Resolution
configure the /etc/hosts file on every node in your cluster (Masters, Workers, and the Kubespray node).

```
#### kubespray ###
192.168.227.138 kubespray.lotus.ir kubespray
######## masters #####
192.168.227.139 master1-s2.lotus.ir master1-s2
192.168.227.140 master2-s2.lotus.ir master2-s2
192.168.227.141 master3-s2.lotus.ir master3-s2
######### workers ######
192.168.227.142 worker1-s2.lotus.ir worker1-s2
192.168.227.143 worker2-s2.lotus.ir worker2-s2
192.168.227.144 worker3-s2.lotus.ir worker3-s2
192.168.227.145 worker4-s2.lotus.ir worker4-s2
```

# Clone Kubespray repository on kubespray server
```
git clone https://github.com/kubernetes-sigs/kubespray.git
cp -R kubespray/ kubespray-cluster-live2
```

#  install required packages on nodes(master and worker)
```
dnf install -y python3-libselinux python3-policycoreutils ==> its neccesarry for kuber
dnf install -y iscsi-initiator-utils ==> it is neccessry for longhorn
```

# firewall must be stop and disable on all nodes


#  remove exec-shield on all master+worker 
```
sed -i '/kernel.exec-shield/d' /etc/sysctl.conf
sed -i '/kernel.exec-shield/d' /etc/sysctl.d/99-sysctl.conf
sysctl -p

```

# 5. STEP 5 - SSH KEY DISTRIBUTION

```
ssh-copy-id -p 5621 root@master1-s2
ssh-copy-id -p 5621 root@master2-s2
ssh-copy-id -p 5621 root@master3-s2
ssh-copy-id -p 5621 root@worker1-s2
ssh-copy-id -p 5621 root@worker2-s2
ssh-copy-id -p 5621 root@worker3-s2
ssh-copy-id -p 5621 root@worker4-s2
```

---

## 3. Inventory Configuration (`inventory/sample/inventory.ini`)

Edit `inventory/mycluster/inventory.ini` to define the 3 Master and 4 Worker topology:

```ini
[all:vars]
ansible_ssh_port=5621
[kube_control_plane]
master1-s2 ansible_host=192.168.227.139  # ip=10.3.0.1 etcd_member_name=etcd1
master2-s2 ansible_host=192.168.227.140  # ip=10.3.0.1 etcd_member_name=etcd1
master3-s2 ansible_host=192.168.227.141  # ip=10.3.0.1 etcd_member_name=etcd1

[etcd:children]
kube_control_plane

[kube_node]
worker1-s2 ansible_host=192.168.227.142  # ip=10.3.0.4
worker2-s2 ansible_host=192.168.227.143  # ip=10.3.0.4
worker3-s2 ansible_host=192.168.227.144  # ip=10.3.0.4
worker4-s2 ansible_host=192.168.227.145  # ip=10.3.0.4
```

---

## 4. Kubespray Configuration Files

### 4.1 Infrastructure Baseline (`inventory/mycluster/group_vars/all/all.yml`)

Configure binary directory, external Load Balancer VIP, DNS, and NTP servers:

```yaml
---
bin_dir: /usr/local/bin

# External Load Balancer for Kube-ApiServer (if only want to use Haproxy)
#loadbalancer_apiserver:
#  address: 1.2.3.4
#  port: 1234


# Upstream DNS Servers
upstream_dns_servers:
  - 192.168.247.247
  - 192.168.247.101

## NTP Settings
ntp_enabled: true
ntp_manage_config: true
ntp_servers:
  - "192.168.247.247"
  - "192.168.247.101"
  - "192.168.243.100"

```

---

### 4.2 Cluster Core Config (`inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml`)

```yaml
---
# Container runtime
container_manager: containerd

# kubeconfig and kubectl
kubeconfig_localhost: true
kubectl_localhost: true

# Network Plugin (Calico) & Subnets
kube_network_plugin: calico
kube_service_addresses: 10.233.0.0/18
kube_pods_subnet: 10.233.64.0/18

#Cluster name
cluster_name: cluster-live
```

---

### 4.3 Addons (`inventory/mycluster/group_vars/k8s_cluster/addons.yml`)

```yaml
---
helm_enabled: true
metrics_server_enabled: true
```

---
### 4.4 Offline Configuration (`inventory/mycluster/group_vars/all/offline.yml`)

```yaml
registry_host: "192.168.227.138:8082"
files_repo: "http://192.168.227.138:8081/repository/k8s-raw-files"
yum_repo: "http://192.168.227.138:8081/repository/yum-group"
kube_image_repo: "{{ registry_host }}"
gcr_image_repo: "{{ registry_host }}"
github_image_repo: "{{ registry_host }}"
docker_image_repo: "{{ registry_host }}"
quay_image_repo: "{{ registry_host }}"
kubeadm_download_url: "{{ files_repo }}/v{{ kube_version }}/bin/linux/{{ image_arch }}/kubeadm"
kubectl_download_url: "{{ files_repo }}/v{{ kube_version }}/bin/linux/{{ image_arch }}/kubectl"
kubelet_download_url: "{{ files_repo }}/v{{ kube_version }}/bin/linux/{{ image_arch }}/kubelet"
github_url: "http://192.168.227.138:8081/repository/github"
dl_k8s_io_url: "http://192.168.227.138:8081/repository/k8s-raw-files"
storage_googleapis_url: "http://192.168.227.138:8081/repository/googleapi-raw"
get_helm_url: "http://192.168.227.138:8081/repository/helm-raw"
```

---
### 4.5 Containerd Mirror Configuration (`inventory/mycluster/group_vars/all/containerd.yml`)

Since `192.168.227.138:8082` operates over plain HTTP:

```yaml
containerd_registries_mirrors:
  - prefix: 192.168.227.138:8082
    mirrors:
      - host: http://192.168.227.138:8082
        capabilities: ["pull", "resolve"]
        skip_verify: true
```
---

### 4.6 extend cert validity (roles/kubernetes/control-plane/defaults/main.yml)
```
kube_cert_validity_period: 87600h
kube_ca_cert_validity_period: 87600h

```

---

### 5. RUN CONTAINER (on deployer)
```
docker run -itd \\
  --mount type=bind,source=/root/kubespray-cluster-live2,dst=/kubespray \\
  --mount type=bind,source="${HOME}"/.ssh/id_rsa,dst=/root/.ssh/id_rsa \\
  kubespray/kubespray:v2.31.0

```
```
docker exec -it <container-id> bash
cd /kubespray
# verify changes before run
```

### 6. Run Ansible
```
ansible-playbook -i inventory/sample/inventory.ini \\
  --private-key /root/.ssh/id_rsa \\
  cluster.yml
```

### 7. TROUBLESHOOT :manual image pull on a node if fails
```
nerdctl -n k8s.io pull 192.168.227.138:8082/kube-proxy:v1.35.4
```
