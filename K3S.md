# Install K3s in an Air-Gapped environment
#### This guide walks you through installing K3s in an air-gapped environment using a three-step process.


The K3s binary matching the version of your image tarball. Download it from the K3s Releases page.

The K3s install script, available from get.k3s.io

## 1. Load Images 

#### a) Manually Deploy Images:
I Used this method:
```bash
wget http://192.168.227.138:8081/repository/github/k3s-io/k3s/releases/download/v1.37.1%2Bk3s1/k3s-airgap-images-amd64.tar.gz

sudo mkdir -p /var/lib/rancher/k3s/agent/images/

sudo cp k3s-airgap-images-amd64.tar /var/lib/rancher/k3s/agent/images/
```
#### b) Private Registry Method
```bash

sudo mkdir -p /etc/rancher/k3s

sudo tee /etc/rancher/k3s/registries.yaml >/dev/null <<'EOF'

mirrors:
  "192.168.227.138:8089":
    endpoint:
      - "http://192.168.227.138:8089"
EOF
```

## 2.  Install the K3s Binary
#### Configuration with binary

```bash
curl -LO  "http://192.168.227.138:8081/repository/github/k3s-io/k3s/releases/download/v1.37.1+k3s1/k3s"
chmod a+x k3s
cp k3s /usr/local/bin/.
K3S_KUBECONFIG_MODE="644" k3s server
```

## 3. 4. Run the Installer
#### Place the install script anywhere on each air-gapped node, and name it. copy this script to install.sh file (  https://get.k3s.io )
```bash
vim install.sh
chmod a+x  install.sh
INSTALL_K3S_SKIP_DOWNLOAD=true ./install.sh
```
## Verify the Installation
```bash
sudo systemctl enable --now k3s
sudo systemctl status k3s
```
```bash
sudo kubectl get nodes
```
