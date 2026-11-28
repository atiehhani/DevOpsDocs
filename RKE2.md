### 1) Key Concepts and Items
Server: In RKE2, this system service includes all Kubernetes Master sub-services.

Agent: In RKE2, this system service includes all Kubernetes Worker sub-services.

MainCluster: This cluster represents the main cluster at Informatics Services Company.

BankCluster: Represents the cluster implemented by a bank.

Token: Created by the first Master node and used by other nodes to join the cluster.

Note: The Token is a random string. The Token mentioned in this document cannot be used at installation time.

### 2) Structure
RKE2 (Rancher Kubernetes Engine 2) is a well-known Kubernetes distribution developed by Rancher. The most important difference between RKE2 and other Kubernetes distributions is the simplicity of deployment and support in offline or air-gapped environments. For this purpose, Rancher provides all required artifacts and images in the form of several compressed files and uses these artifacts through a bootstrap script to set up the cluster and its components. It should be noted that the container runtime and internal image repository mechanism are also embedded in RKE2.
#### Main cluster components:

LoadBalancer: Two Nginx servers act as load balancers for Master nodes for Workers and Masters.

VIP (Virtual IP): An IP address that does not physically belong to a specific machine and receives requests ahead of the LoadBalancer.

RKE2 Server (k8s Master): At least 3 nodes.

RKE2 Agent (k8s Worker): In this document, only one node is added. Obviously, the number of Worker nodes in production will be higher.

This cluster requires a Distributed File System, and the recommended storage is Ceph or Rook Ceph.
### 3-1) Overall Service Diagram

### 3-2) Preprocess
```bash
sudo dnf upgrade
```
### 4) Load Balancer installation  
To provide standard and High Availability service, the Load balancer will be placed between the Worker and Master nodes. Therefore, Worker nodes will communicate with Master servers only through the Load balancer. It is recommended to use two virtual Load balancer servers and to configure a VIP for these two Load balancers using the keepalived service. Wherever Load balancer IP is mentioned in the Config files, it refers to this VIP.

Note: During the initial RKE2 cluster setup, in the nginx.conf file, all Master servers except Master1 are disabled and commented out. After all Master servers are installed and running, the remaining Master servers are enabled and uncommented, and the Nginx service is restarted.

Back up the initial Nginx config file:  
```bash
mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
```
Create a new config file and place the following values in it. Note that the fqdn values in the file below must be changed according to the RKE2 server servers, their corresponding IPs, and their count.  
```bash
cat <<EOF > /etc/nginx/nginx.conf
user nginx;
worker_processes 4;
worker_rlimit_nofile 40000;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;
# Load dynamic modules. See /usr/share/doc/nginx/README.dynamic.
include /usr/share/nginx/modules/*.conf;
events {
    worker_connections 8192;
}
stream {
    ###### Kube API (9345) - RKE2 registration
    upstream backend {
        least_conn;
        server BankCluster-Master01:9345 max_fails=3 fail_timeout=5s;
        # server BankCluster-Master02:9345 max_fails=3 fail_timeout=5s;
        # server BankCluster-Master03:9345 max_fails=3 fail_timeout=5s;
    }
    server {
        listen 9345;
        proxy_pass backend;
    }
    ###### Kubernetes API (6443)
    upstream rancher_api {
        least_conn;
        server BankCluster-Master01:6443 max_fails=3 fail_timeout=5s;
        # server BankCluster-Master02:6443 max_fails=3 fail_timeout=5s;
        # server BankCluster-Master03:6443 max_fails=3 fail_timeout=5s;
    }
    server {
        listen 6443;
        proxy_pass rancher_api;
    }
}
EOF
```

Verify that the Nginx config file is correctly formatted and has no errors:

```bash
nginx -t
```
Start and enable the Nginx service and check its status to ensure it is working properly:

``` bash
systemctl enable --now nginx
systemctl status nginx
```
### 5) Virtual machine settings and requirements
The changes mentioned through the end of this section (section 5) are applied identically on all cluster servers.

#### 5-1) Operating system specifications
The OS specifications should match the output of the following commands:  

```bash
## Requirements
# OS
uname -a
Linux Bank-cluster1 6.12.0-101.33.4.3.el9uek.x86_64 #1 SMP PREEMPT_DYNAMIC Mon
Jul 14 18:34:15 PDT 2025 x86_64 x86_64 x86_64 GNU/Linux

# OS Release
cat /etc/os-release
NAME="Oracle Linux Server"
VERSION="9.6"
ID="ol"
ID_LIKE="fedora"
VARIANT="Server"
VARIANT_ID="server"
VERSION_ID="9.6"
PLATFORM_ID="platform:el9"
PRETTY_NAME="Oracle Linux Server 9.6"
ANSI_COLOR="0;31"
CPE_NAME="cpe:/o:oracle:linux:9:6:server"
HOME_URL="https://linux.oracle.com/"
BUG_REPORT_URL="https://github.com/oracle/oracle-linux"
ORACLE_BUGZILLA_PRODUCT="Oracle Linux 9"
ORACLE_BUGZILLA_PRODUCT_VERSION=9.6
ORACLE_SUPPORT_PRODUCT="Oracle Linux"
ORACLE_SUPPORT_PRODUCT_VERSION=9.6
```
#### 5-2) Required hardware resources
Role	CPU	Memory
Master	8 Core	16 G
Worker	16 Core	32 G
CPU specifications:  
```bash
lscpu | grep -i Architecture:
Architecture: x86_64
```
#### 5-3) IP Address configuration
If you use the IP Address range 10.42.0.0/16 or 10.43.0.0/16 for the virtual machines, uncomment the Cluster-cidr and Service-cidr settings shown in the box below during the Master installation stage (RKE2 installation).
```bash
#cluster-cidr: 10.xy.0.0/16 # Pod network CIDR
#service-cidr: 10.xz.0.0/16 # Service network CIDR
```

Note that for the desired range, choose values different from the VM range instead of the IPs shown.

#### 5-4) Hosts

```bash
cat <<EOF > /etc/hosts
127.0.0.1 localhost localhost.localdomain localhost4 localhost4.localdomain4
::1 localhost localhost.localdomain localhost6 localhost6.localdomain6
# Nexus Repo
192.168.10.xx REPO-Name
#LoadBalancer
192.168.10.xx VIP-Name
#Bank Cluster
192.168.10.xx BankCluster-01 #master01
192.168.10.xx BankCluster-02 #master02
192.168.10.xx BankCluster-03 #master03
192.168.10.xx BankCluster-04 #worker01
EOF
```
#### 5-5) Hostname
For all cluster components, the hostname must be set to match the hosts records:
```bash
hostnamectl set-hostname BankClusterxx
```
#### 5-6) SELinux
Disable SELinux on all servers:  
```bash
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
```

#### 5-7) Cgroup configuration
Modify Grub on all servers as follows:

```bash]
cat <<EOF > /etc/default/grub
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="crashkernel=1G-64G:448M,64G-:512M resume=/dev/mapper/ol-swap
rd.lvm.lv=ol/root rd.lvm.lv=ol/swap systemd.unified_cgroup_hierarchy=1"
GRUB_DISABLE_RECOVERY="true"
GRUB_ENABLE_BLSCFG=true
EOF
```
Then:
```bash
grubby --update-kernel=ALL --args="systemd.unified_cgroup_hierarchy=1"
```
At this stage, reboot the hosts and verify the changes:

```bash
shutdown -r now
mount -l | grep cgroup
cgroup2 on /sys/fs/cgroup type cgroup2
(rw,nosuid,nodev,noexec,relatime,nsdelegate,memory_recursiveprot)
```
#### 5-8) Kernel Parameters
Modify the sysctl file as follows:
```bash
cat <<EOF > /etc/sysctl.conf
### kernel parameters
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-arptables = 1
# SWAP settings
vm.swappiness=0
vm.panic_on_oom=0
vm.overcommit_memory=1
kernel.panic=10
kernel.panic_on_oops=1
vm.max_map_count = 262144
# Have a larger connection range available
net.ipv4.ip_local_port_range=1024 65000
# Increase max connection
net.core.somaxconn=10000
# Reuse closed sockets faster
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=15
# The maximum number of "backlogged sockets". Default is 128.
net.core.netdev_max_backlog=4096
net.core.rmem_max=16777216
# Various network tunables
net.ipv4.tcp_max_syn_backlog=20480
net.ipv4.tcp_max_tw_buckets=400000
net.ipv4.tcp_no_metrics_save=1
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_syn_retries=2
net.ipv4.tcp_synack_retries=2
net.ipv4.tcp_wmem=4096 65536 16777216
# ARP cache settings for a highly loaded docker swarm
net.ipv4.neigh.default.gc_thresh1=8096
net.ipv4.neigh.default.gc_thresh2=12288
net.ipv4.neigh.default.gc_thresh3=16384
# ip_forward and tcp keepalive for iptables
net.ipv4.tcp_keepalive_time=600
# monitor file system events
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=1048576
#### doc
net.ipv4.conf.all.forwarding=1
net.ipv6.conf.all.forwarding=1
fs.file-max = 2097152
EOF
```
Then persist it:
```bash
sysctl -p
```
**Note**: No errors should appear in the output of the above command.  

#### 5-9) Firewalld
The firewalld and nftables services must be disabled and masked:

```bash
systemctl disable --now firewalld
systemctl mask firewalld
systemctl disable --now nftables
systemctl mask nftables
```
#### 5-10) Creating required directories
```bash
mkdir -p /etc/rancher/rke2/ /var/lib/rancher/rke2/agent/images/ \
/var/lib/rancher/rke2/server/manifests/
```
#### 5-11) Registries
To introduce and enable a local Registry in the RKE2 cluster, add the following file on all Master and Worker nodes:  

```bash
cat <<EOF > /etc/rancher/rke2/registries.yaml
mirrors:
  quay.io:
    endpoint:
      - "https://REPO-NAME"
  docker.io:
    endpoint:
      - "https://REPO-NAME"
  cr.l5d.io:
    endpoint:
      - "https://REPO-NAME"
  registry.k8s.io:
    endpoint:
      - "https://REPO-NAME"
  gcr.io:
    endpoint:
      - "https://REPO-NAME"
  docker.elastic.co:
    endpoint:
      - "https://REPO-NAME"
  ghcr.io:
    endpoint:
      - "https://REPO-NAME"
EOF
```
#### 5-12) NetworkManager service configuration
To improve routing performance by the RKE2 cluster CNI, add the following file on all Master and Worker nodes:
```bash
cat <<EOF > /etc/NetworkManager/conf.d/rke2-unmanagedDevices.conf
[keyfile]
unmanaged-devices=interface-name:flannel*;interface-name:cali*;interface-name:tunl*;interface-name:vxlan.calico;interface-name:vxlan-v6.calico;interface-name:wireguard.cali;interface-name:wg-v6.cali
EOF
```
#### 5-13) Network card configuration
Configure the Gateway address on the network Interface, and the file should be similar to the following:

```bash
vi /etc/NetworkManager/system-connections/ens192.nmconnection
[ipv4]
address1=192.168.10.xx/24,192.168.10.x
method=manual

systemctl restart NetworkManager
```
#### 5-14) Swap settings
Turn off Swap on the OS with the following commands:

```bash
swapoff -a
sed -i.bak '/\sswap\s/s/^/#/' /etc/fstab
```
After applying the commands, verify with the following command that the values are set to 0:
```bash
free -mh | grep -i swap
Swap: 0B 0B 0B
```
### **6) RKE2 installation**
Transfer the Artifact file provided by Informatics Services Company to all Master and Worker servers and extract it:
```bash
tar xvfz rke2-artifacts.tar.gz
```
#### 6-1) Cilium CLI and Helm
Place the Cilium and Helm binaries on the Master servers of the cluster as follows:

```bash
cd ~/rke2-artifacts/
tar xvfz cilium-linux-amd64.tar.gz
cp cilium /usr/local/bin/
#check it
cilium version
cilium-cli: v0.18.5 compiled with go1.24.4 on linux/amd64
cilium image (default): v1.17.5
cilium image (stable): unknown
cilium image (running): unknown. Unable to obtain cilium version. Reason:
release: not found
```
```bash
cp helm /usr/local/bin/
# check it
helm version
version.BuildInfo{Version:"v3.11.3",
GitCommit:"323249351482b3bbfc9f5004f65d400aa70f9ae7", GitTreeState:"clean",
GoVersion:"go1.20.3"}
```
#### 6-2) Installing the first Master
Run the following command to install the Master service:

```bash
cd ~/rke2-artifacts/
INSTALL_RKE2_ARTIFACT_PATH=/root/rke2-artifacts sh install.sh
```
Then configure the RKE2 service Config file as follows

```bash
cat <<EOF > /etc/rancher/rke2/config.yaml
tls-san:
  - <VIP-Name>
  - <vip ip address>
#cluster-cidr: 10.xy.0.0/16 # Pod network CIDR
#service-cidr: 10.xz.0.0/16 # Service network CIDR
write-kubeconfig-mode: "0600"
cni: cilium
disable:
  - rke2-canal
  - rke2-kube-proxy
  - servicelb
disable-cloud-controller: true
disable-kube-proxy: true
debug: true
kube-scheduler-arg: ['bind-address=0.0.0.0', 'secure-port=10259']
kube-apiserver-arg:
  - "enable-admission-plugins=DefaultTolerationSeconds"
  - "default-not-ready-toleration-seconds=40"
  - "default-unreachable-toleration-seconds=40"
kube-controller-manager-arg:
  - "node-monitor-period=2s"
  - "node-monitor-grace-period=30s"
  - "bind-address=0.0.0.0"
  - "secure-port=10257"
kubelet-arg:
  - "node-status-update-frequency=4s"
kube-scheduler-arg: ['bind-address=0.0.0.0', 'secure-port=10259']
node-name: BankCluster-01
node-ip: <current master ip address>
EOF
```
To ensure correct network connectivity between the RKE2 cluster and the Virtual Servers of other banks' clusters, the cluster network address range must be extracted as follows for the ipv4NativeRoutingCIDR parameter:

```bash
## Master node Interface
NET_INT=ens192
RoutingCIDR=$(ip route show dev ${NET_INT} proto kernel scope link | awk '{print $1}')
## sample
echo $RoutingCIDR
192.168.10.0/24
```
**Note:** If the Data Plane is separated from the Control Plane in the RKE2 cluster, the Data Plane network address range must be used.

To configure and install the Cilium CNI in the RKE2 cluster, configure the following file on all Master servers:
```bash
cat <<EOF > /var/lib/rancher/rke2/server/manifests/rke2-cilium-config.yaml
---
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-cilium
  namespace: kube-system
spec:
  valuesContent: |-
    # ========== ENI SHOULD DISABLE ==========
    eni:
      enabled: false
    # ========== ENVOY ==========
    envoy:
      enabled: true
    # ========== HUBBLE ==========
    hubble:
      enabled: true
      metrics:
        dashboards:
          enabled: true
      relay:
        enabled: true
      ui:
        enabled: true
    # ========== IP ADDRESS ALLOCATION ==========
    ipam:
      mode: kubernetes
    # ========== KUBE-PROXY REPLACEMENT ==========
    kubeProxyReplacement: true
    kubeProxyReplacementHealthzBindAddr: "0.0.0.0:10256"
    localRedirectPolicies:
      enabled: true
    k8sServiceHost: "LOAD_BALANCER_IP" # VIP of loadbalancer for HA
    k8sServicePort: "6443"
    ipv4NativeRoutingCIDR: "$RoutingCIDR"
    # ========== OPERATOR ==========
    operator:
      replicas: 2
      resources:
        requests:
          memory: "100Mi"
          cpu: "100m"
        limits:
          memory: "800Mi"
          cpu: "800m"
    # ========== ENCRYPTION ==========
    encryption:
      enabled: true
      type: wireguard
      nodeEncryption: true
    # ========== BPF MASQUERADING ==========
    enable-bpf-host-routing: true
    bpf:
      hostLegacyRouting: false
      masquerade: true
      masqueradeMode: native
    # ========== ROUTING and OPTIMIZATIONS ==========
    routingMode: native
    autoDirectNodeRoutes: true
    directRoutingDevice: auto
    # ========== BANDWIDTH MANAGER ==========
    bandwidthManager:
      enabled: true
      bbr: true
EOF
```
**Note:** Any future change to this file, if correctly configured, triggers an automatic Helm upgrade of Cilium and restarts Cilium pods; there is no need to restart the service.

Start and enable the service with the following command. Note that activating this service will take time:
```bash
systemctl enable --now rke2-server.service

```
Verify the server service is error-free:
```bash
systemctl status rke2-server.service
journalctl -f -u rke2-server.service

```
Modify the bashrc file to access the required commands:
```bash
cat <<'EOF' >> ~/.bashrc
## Environment
export PATH=$PATH:/var/lib/rancher/rke2/bin
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
source <(kubectl completion bash)
source <(helm completion bash)
EOF
source ~/.bashrc
```
Also check the health of the nodes and Pods on the cluster:
```bash

# Check all nodes
kubectl get nodes
# Check all pods
kubectl get pods -A
```
#### 6-3) Connecting other Masters to RKE2
To have a High Availability cluster, you must add two more Masters to the Cluster. For the LoadBalancer IP Address, use Port 9345 (referenced earlier in the Nginx service). When a request reaches the Nginx service on Port 9345, it is proxied in the Backend to the Masters on Port 9345.

For the Token, copy it from the following path on the Master1 server:
```bash
cat /var/lib/rancher/rke2/server/node-token
K10326asewvb45fff46d90218b68729f42ad5812e49dedc217ffac31a9210efb8547::server:7cbbde069084932727f4666cab91325f
```
#### 6-4) Installing Master 2 and Master 3
```bash
cd /root/rke2-artifacts/
INSTALL_RKE2_ARTIFACT_PATH=/root/rke2-artifacts sh install.sh
```
Configure the config file as follows:

```bash
cat <<EOF >> /etc/rancher/rke2/config.yaml
server: https://<vip ip address>:9345
token: K10326asewvb45fff46d90218b68729f42ad5812e49dedc217ffac31a9210efb8547::server:7cbbde069084932727f4666cab91325f
tls-san:
  - LoadBalancer_DNS_NAME
  - <LoadBalancer/vip ip address>
#cluster-cidr: 10.xy.0.0/16 # Pod network CIDR
#service-cidr: 10.xz.0.0/16 # Service network CIDR
write-kubeconfig-mode: "0600"
cni: cilium
disable:
  - rke2-canal
  - rke2-kube-proxy
  - servicelb
disable-kube-proxy: true
disable-cloud-controller: true
debug: true
kube-scheduler-arg: ['bind-address=0.0.0.0', 'secure-port=10259']
kube-apiserver-arg:
  - "enable-admission-plugins=DefaultTolerationSeconds"
  - "default-not-ready-toleration-seconds=40"
  - "default-unreachable-toleration-seconds=40"
kube-controller-manager-arg:
  - "node-monitor-period=2s"
  - "node-monitor-grace-period=30s"
  - "bind-address=0.0.0.0"
  - "secure-port=10257"
kubelet-arg:
  - "node-status-update-frequency=4s"
kube-scheduler-arg: ['bind-address=0.0.0.0', 'secure-port=10259']
node-name: BankCluster-02
node-ip: <current master ip address>
EOF
```
Enable the service:
```bash
systemctl enable --now rke2-server
```
Verify the server service is error-free:
```bash
systemctl status rke2-server.service
journalctl -f -u rke2-server.service
```
On the first Master, check the Node status. The new Master should have been added:

```bash
# Check all nodes
kubectl get nodes
# Check all pods
kubectl get pods -A
```

#### 6-5) Installing and connecting Worker servers to the cluster
At least six Workers must be defined in each cluster. Assuming the files have already been transferred to the server, run the following commands:
```bash
cd /root/rke2-artifacts
INSTALL_RKE2_ARTIFACT_PATH=/root/rke2-artifacts INSTALL_RKE2_TYPE="agent" sh install.sh
```

At this stage, you must configure the Worker-side Config file so that when the service comes up, it registers as a Worker Node with the Master nodes. For authentication with the Master nodes, you need the LoadBalancer address and the Token.

For the LoadBalancer IP Address, use Port 9345 (referenced earlier in the Nginx service). When a request reaches the Nginx service on Port 9345, it is proxied to the Masters on Port 9345. For the Token, copy it from the Master1 server from the following path:
```bash
cat /var/lib/rancher/rke2/server/node-token
K10326asewvb45fff46d90218b68729f42ad5812e49dedc217ffac31a9210efb8547::server:7cbbde069084932727f4666cab91325f
```
Finally, place both in the following file:

```bash
cat <<EOF > /etc/rancher/rke2/config.yaml
token: K10326asewvb45fff46d90218b68729f42ad5812e49dedc217ffac31a9210efb8547::server:7cbbde069084932727f4666cab91325f
server: https://"<vip ip address>":9345
kubelet-arg:
  - "container-log-max-size=40Mi"
  - "container-log-max-files=30"
  - "node-status-update-frequency=4s"
node-name: BankCluster-04
node-ip: <current worker ip address>
EOF
```
Now enable and start the Worker service:
```bash
systemctl enable --now rke2-agent.service
```

Note that activating this service will take time. Verify the Worker service is error-free:
```bash
systemctl status rke2-agent.service
journalctl -f -u rke2-agent.service
```
Then, on Master1, verify that the new Worker has been added:
```bash
# on master1:
kubectl get nodes
```
Repeat the above steps to add the other Worker servers to the RKE2 cluster.

### 7) Final configuration and verification
Unschedulable the Master servers with the following commands:
```bash
kubectl taint nodes BankCluster-01 node-role.kubernetes.io/control-plane:NoSchedule
kubectl taint nodes BankCluster-02 node-role.kubernetes.io/control-plane:NoSchedule
kubectl taint nodes BankCluster-03 node-role.kubernetes.io/control-plane:NoSchedule
```

Check the following items; if the Cluster is accessible without errors, the installation is complete:

```bash
#check all Nodes
kubectl get nodes
# Check all pods
kubectl get pods -A
#check cilium status on all cluster
cilium status --wait
```

### 8) Updating and upgrading the RKE2 cluster version
This section is for updating and upgrading the RKE2 cluster version of the Borna digital rial system. Due to the limited gap and version differences of kube-apiserver, kube-scheduler, etc. between Master and Worker nodes, the RKE2 version upgrade must be done step by step (one Minor at a time) and in coordination with and with the announcement of Informatics Services Company.

#### 8-1) Obtaining the required file
Obtain the file rke2_v1.<x>.<x>+rke2r1.tar.gz (for RKE2 v1.x.x versions — the version changes, and the examples below are illustrative only; the exact version will be announced) from the shared path, place it on all Worker and Master servers of the RKE2 cluster, and decompress it with the following command:
```bash
tar xvfz rke2_v1.33.8+rke2r1.tar.gz
cd /root/rke2_v1.33.8+rke2r1
ls -ltrh
total 1.3G
-rw-r--r-- 1 root root 557M Feb 18 09:56 rke2-images-cilium.linux-amd64.tar.zst
-rw-r--r-- 1 root root 719M Feb 18 09:57 rke2-images.linux-amd64.tar.zst
-rw-r--r-- 1 root root 4.2K Feb 18 09:57 sha256sum-amd64.txt
-rw-r--r-- 1 root root  37M Feb 18 09:57 rke2.linux-amd64.tar.gz
```
**Note:** To simplify and speed up the update, you can import the RKE2 Images into your own Repository using the following commands:

```bash

docker image load -i rke2-images.linux-amd64.tar.zst
docker image load -i rke2-images-cilium.linux-amd64.tar.zst
docker tag Image-Name:TAG local-REPOSITORY/Image-Name:TAG
docker push local-REPOSITORY/Image-Name:TAG

```
#### 8-2) Backing up CoreDNS
Since during the RKE2 cluster version update, the contents of the CoreDNS module ConfigMap are automatically deleted, and only if the CoreDNS and nginx-ingress config files exist in the following path on all Master nodes:
```bash
ls -ltrh /var/lib/rancher/rke2/server/manifests/rke2-*-config.yaml
-rw------- 1 root root 7422 Oct 24 11:25 /var/lib/rancher/rke2/server/manifests/rke2-coredns-config.yaml
-rw-r--r-- 1 root root  593 Oct  7 13:45 /var/lib/rancher/rke2/server/manifests/rke2-ingress-nginx-config.yaml
```
Back up CoreDNS with the following commands:
```bash
cd /root/rke2_v1.33.8+rke2r1
kubectl get cm -n kube-system rke2-coredns-rke2-coredns -o yaml | sed -e '/creationTimestamp/d' -e '/helm.sh\/chart/d' -e '/resourceVersion/d' -e '/uid:/d' > bkp_cm_rke2-coredns-rke2-coredns.yaml
```
After completing the update operation, check the ConfigMap information and ensure CoreDNS is working properly.

```bash

cd /root/rke2_v1.33.8+rke2r1
kubectl -n kube-system rollout status deployments.apps rke2-coredns-rke2-coredns
```
Expected output:
```bash
Waiting for deployment "rke2-coredns-rke2-coredns" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "rke2-coredns-rke2-coredns" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "rke2-coredns-rke2-coredns" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "rke2-coredns-rke2-coredns" rollout to finish: 1 of 2 updated replicas are available...
deployment "rke2-coredns-rke2-coredns" successfully rolled out
```
```bash
kubectl -n kube-system get deployments.apps rke2-coredns-rke2-coredns
NAME                       READY   UP-TO-DATE   AVAILABLE   AGE
rke2-coredns-rke2-coredns  2/2     2            2           150d
```
#### 8-3) Scheduling Master Servers
Remove the NoSchedule taint from Master nodes and after successful completion of the update operation, place them back in NoSchedule mode.
```bash
# Schedule master nodes
kubectl taint nodes BankCluster-03 node-role.kubernetes.io/control-plane:NoSchedule-
kubectl taint nodes BankCluster-02 node-role.kubernetes.io/control-plane:NoSchedule-
kubectl taint nodes BankCluster-03 node-role.kubernetes.io/control-plane:NoSchedule-

# Unschedule master nodes
kubectl taint nodes BankCluster-01 node-role.kubernetes.io/control-plane:NoSchedule
kubectl taint nodes BankCluster-02 node-role.kubernetes.io/control-plane:NoSchedule
kubectl taint nodes BankCluster-03 node-role.kubernetes.io/control-plane:NoSchedule
```
#### 8-4) Checking Pod Status
Before and during the update operation, check and monitor the status of all pods in all Namespaces, for example using k9s with the !Running filter.

#### 8-5) Controlling Rook-Ceph and OSD Disks Status
To prevent additional load and shorten the update operation time, in the Rook-Ceph cluster, apply the following commands before updating the servers containing OSD disks, and monitor the Rook-Ceph cluster status during the operation.

```bash
kubectl -n rook-ceph exec -it deployments/rook-ceph-tools -- bash
bash-5.1$ ceph osd set noout
noout is set
bash-5.1$ ceph osd set norebalance
norebalance is set
bash-5.1$ ceph osd set nobackfill
nobackfill is set
bash-5.1$ ceph osd set norecover
norecover is set
bash-5.1$ watch ceph -s
```
Expected output:
```bash
cluster:
  id:     9929e026-bc08-4afd-8ff4-faa58779161b
  health: HEALTH_WARN
          noout,nobackfill,norebalance,norecover flag(s) set
services:
  mon: 3 daemons, quorum a,b,c (age 2h)
  mgr: a(active, since 2h), standbys: b
  mds: 1/1 daemons up, 1 hot standby
  osd: 8 osds: 8 up (since 2h), 8 in (since 3w)
  flags noout,nobackfill,norebalance,norecover
data:
  volumes: 1/1 healthy
  pools:   4 pools, 97 pgs
  objects: 3.80k objects, 305 MiB
  usage:   1.4 GiB used, 124 GiB / 125 GiB avail
  pgs:     97 active+clean
io:
  client:   852 B/s rd, 1 op/s rd, 0 op/s wr
```
After completing the update of each server containing OSD disks, apply the following commands and check the Rook-Ceph cluster status.
```bash
kubectl -n rook-ceph exec -it deployments/rook-ceph-tools -- bash
bash-5.1$ ceph osd unset noout
noout is unset
bash-5.1$ ceph osd unset norebalance
norebalance is unset
bash-5.1$ ceph osd unset nobackfill
nobackfill is unset
bash-5.1$ ceph osd unset norecover
norecover is unset
bash-5.1$ ceph -s
```
Expected output:
```bash
cluster:
  id:     9929e026-bc08-4afd-8ff4-faa58779161b
  health: HEALTH_OK
services:
  mon: 3 daemons, quorum a,b,c (age 2h)
  mgr: a(active, since 2h), standbys: b
  mds: 1/1 daemons up, 1 hot standby
  osd: 8 osds: 8 up (since 2h), 8 in (since 3w)
data:
  volumes: 1/1 healthy
  pools:   4 pools, 97 pgs
  objects: 3.80k objects, 305 MiB
  usage:   1.4 GiB used, 124 GiB / 125 GiB avail
  pgs:     97 active+clean
io:
  client:   1.2 KiB/s rd, 85 B/s wr, 2 op/s rd, 0 op/s wr
```
**Note:** Be sure to verify the health of the Rook-Ceph cluster before starting the operation.

#### 8-6) Updating Master Servers
The RKE2 cluster update must be performed from the Master servers one by one as follows.
```bash
# take backup from rke2 artifacts
mkdir /root/bkp_rke2_1.32.6
mv /var/lib/rancher/rke2/agent/images/rke2-images* /root/bkp_rke2_1.32.6/
mv /usr/local/bin/rke2* /root/bkp_rke2_1.32.6/
ls -ltrh /root/bkp_rke2_1.32.6
```
Expected output:
```bash
total 1.4G
-rwxr-xr-x 1 root root 5.5K Feb 18 07:28 rke2-uninstall.sh
-rwxr-xr-x 1 root root 3.4K Feb 18 07:28 rke2-killall.sh
-rwxr-xr-x 1 root root 119M Feb 18 07:28 rke2
-rw-r--r-- 1 root root 425M Feb 18 07:29 rke2-images-cilium.linux-amd64.tar.zst
-rw-r--r-- 1 root root 793M Feb 18 07:29 rke2-images.linux-amd64.tar.zst
```
```bash
# uncompress tar file
tar -xvf rke2_<new version>.tar
# copy needed new artifacts
cd /root/rke2_<new version>_full
cp rke2_<new version>_images/* /var/lib/rancher/rke2/agent/images/
ls -ltrh /var/lib/rancher/rke2/agent/images/
```
Expected output:
```bash
total 1.3G
-rw-r--r-- 1 root root 557M Feb 18 11:28 rke2-images-cilium.linux-amd64.tar.zst
-rw-r--r-- 1 root root 719M Feb 18 11:28 rke2-images.linux-amd64.tar.zst
```
```bash
cd rke2<new version>
tar xvfz rke2.linux-amd64.tar.gz
cp bin/rke2-uninstall.sh bin/rke2-killall.sh bin/rke2 /usr/local/bin/
chmod +x /usr/local/bin/*
ls -ltrh /usr/local/bin/rke2*
```
Expected output:
```bash
-rwxr-xr-x 1 root root 5.5K Feb 18 11:23 /usr/local/bin/rke2-uninstall.sh
-rwxr-xr-x 1 root root 3.3K Feb 18 11:23 /usr/local/bin/rke2-killall.sh
-rwxr-xr-x 1 root root 119M Feb 18 11:23 /usr/local/bin/rke2
```
```bash
rke2-killall.sh ; systemctl restart rke2-server
```
**Note** that the rke2-server service may take time to become ready, and the service log should be checked if needed.  
 After the update is complete, the cluster status is as follows.  
 **Note** that the mentioned versions are examples only.
```bash
kubectl get nodes -o wide
NAME            STATUS   ROLES                       AGE    VERSION          INTERNAL-IP    EXTERNAL-IP   OS-IMAGE                KERNEL-VERSION                 CONTAINER-RUNTIME
BankCluster-01  Ready    control-plane,etcd,master   150d   v1.33.8+rke2r1   192.168.10.11  <none>        Oracle Linux Server 9.6  6.12.0-105.51.5.el9uek.x86_64  containerd://2.1.5-k3s1
BankCluster-02  Ready    control-plane,etcd,master   150d   v1.32.6+rke2r1   192.168.10.12  <none>        Oracle Linux Server 9.6  6.12.0-105.51.5.el9uek.x86_64  containerd://2.0.5-k3s1
BankCluster-03  Ready    control-plane,etcd,master   150d   v1.32.6+rke2r1   192.168.10.13  <none>        Oracle Linux Server 9.6  6.12.0-105.51.5.el9uek.x86_64  containerd://2.0.5-k3s1
BankCluster-04  Ready    <none>                      123d   v1.32.6+rke2r1   192.168.10.14  <none>        Oracle Linux Server 9.6  6.12.0-105.51.5.el9uek.x86_64  containerd://2.0.5-k3s1
BankCluster-05  Ready    <none>                      123d   v1.32.6+rke2r1   192.168.10.15  <none>        Oracle Linux Server 9.6  6.12.0-105.51.5.el9uek.x86_64  containerd://2.0.5-k3s1
BankCluster-06  Ready    <none>                      123d   v1.32.6+rke2r1   192.168.10.16  <none>        Oracle Linux Server 9.6  6.12.0-105.51.5.el9uek.x86_64  containerd://2.0.5-k3s1
```

Follow the above steps to upgrade the other Master Nodes one by one and ensure cluster health and other Pod status at each stage.

**Note:** After updating all Master servers, section 8-2 must be checked.

#### 8-7) Updating Worker Servers
After successfully updating all Master servers, update the Worker servers as follows, considering section 8-5.
```bash
# take backup from rke2 artifacts
mkdir /root/bkp_rke2_1.32.6
mv /var/lib/rancher/rke2/agent/images/rke2-images* /root/bkp_rke2_1.32.6/
mv /usr/local/bin/rke2* /root/bkp_rke2_1.32.6/
ls -ltrh /root/bkp_rke2_1.32.6
```
Expected output:
```bash
total 1.4G
-rwxr-xr-x 1 root root 5.5K Feb 18 07:28 rke2-uninstall.sh
-rwxr-xr-x 1 root root 3.4K Feb 18 07:28 rke2-killall.sh
-rwxr-xr-x 1 root root 119M Feb 18 07:28 rke2
-rw-r--r-- 1 root root 425M Feb 18 07:29 rke2-images-cilium.linux-amd64.tar.zst
-rw-r--r-- 1 root root 793M Feb 18 07:29 rke2-images.linux-amd64.tar.zst
```
```bash
# uncompress tar file
tar -xvf rke2_<new version>.tar
# copy needed new artifacts
cd /root/rke2_v<new version>_full
cp rke2_<new version>_images/* /var/lib/rancher/rke2/agent/images/
ls -ltrh /var/lib/rancher/rke2/agent/images/
```
Expected output:
```bash
total 1.3G
-rw-r--r-- 1 root root 557M Feb 18 11:28 rke2-images-cilium.linux-amd64.tar.zst
-rw-r--r-- 1 root root 719M Feb 18 11:28 rke2-images.linux-amd64.tar.zst
```

```bash
cd rke2<new version>
tar xvfz rke2.linux-amd64.tar.gz
cp bin/rke2-uninstall.sh bin/rke2-killall.sh bin/rke2 /usr/local/bin/
chmod +x /usr/local/bin/*
ls -ltrh /usr/local/bin/rke2*

```
Expected output:
```bash
-rwxr-xr-x 1 root root 5.5K Feb 18 11:23 /usr/local/bin/rke2-uninstall.sh
-rwxr-xr-x 1 root root 3.3K Feb 18 11:23 /usr/local/bin/rke2-killall.sh
-rwxr-xr-x 1 root root 119M Feb 18 11:23 /usr/local/bin/rke2
```
```bash
rke2-killall.sh ; systemctl restart rke2-agent
```
After successful update completion, the cluster status is as follows.
```bash
kubectl get nodes -o wide
NAME            STATUS   ROLES                       AGE    VERSION          INTERNAL-IP    EXTERNAL-IP   OS-IMAGE                KERNEL-VERSION                 CONTAINER-RUNTIME
BankCluster-01  Ready    control-plane,etcd,master   150d   v1.33.8+rke2r1   192.168.10.11  <none>        Oracle Linux Server 9.6  6.12.0-105.51.5.el9uek.x86_64  containerd://2.1.5-k3s1
BankCluster-02  Ready    control-plane,etcd,master   150d   v1.33.8+rke2r1   192.168.10.12  <none>        Oracle Linux Server 9.6  6.12.0-105.51.5.el9uek.x86_64  containerd://2.1.5-k3s1
BankCluster-03  Ready    control-plane,etcd,master   150d   v1.33.8+rke2r1   192.168.10.13  <none>        Oracle Linux Server 9.6  6.12.0-105.51.5.el9uek.x86_64  containerd://2.1.5-k3s1
BankCluster-04  Ready    <none>                      123d   v1.33.8+rke2r1   192.168.10.14  <none>        Oracle Linux Server 9.6  6.12.0-105.51.5.el9uek.x86_64  containerd://2.1.5-k3s1
BankCluster-05  Ready    <none>                      123d   v1.32.6+rke2r1   192.168.10.15  <none>        Oracle Linux Server 9.6  6.12.0-105.51.5.el9uek.x86_64  containerd://2.0.5-k3s1
BankCluster-06  Ready    <none>                      123d   v1.32.6+rke2r1   192.168.10.16  <none>        Oracle Linux Server 9.6  6.12.0-105.51.5.el9uek.x86_64  containerd://2.0.5-k3s1
```
Follow the above steps to upgrade the other Worker Nodes one by one and ensure RKE2, Rook-Ceph, and other Pod health at each stage.

#### 8-8) Rollback to Previous RKE2 Version
If needed to rollback and return to the previous version, perform the following commands.

```bash
# copy needed new artifacts
cd /root/bkp_rke2_1.32.6/
rm -rf /var/lib/rancher/rke2/agent/images/rke2-images*
cp rke2-images* /var/lib/rancher/rke2/agent/images/
rm -rf /usr/local/bin/rke2*
cp rke2-uninstall.sh rke2-killall.sh rke2 /usr/local/bin/

# Restart Master Nodes
rke2-killall.sh ; systemctl restart rke2-server

# Restart Worker Nodes
rke2-killall.sh ; systemctl restart rke2-agent
```

