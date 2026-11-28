## Rook Ceph Installation:
Assuming the Rook files have been obtained from the official GitHub at:
```bash
text
https://github.com/rook/rook/archive/refs/tags/v1.19.0.tar.gz
```
Go to the following path and execute the commands:
```bash
bash
cd /root/
tar -xvzf rook-1.19.0.tar.gz
PWD=/root/rook-1.19.0/deploy/examples
sed -i 's/^\(\s*ROOK_ENABLE_DISCOVERY_DAEMON:\s*\)"true"\s*$/\1"false"/' $PWD/operator.yaml
sed -i 's/^\(\s*ROOK_CSI_ENABLE_RBD:\s*\)"true"\s*$/\1"false"/' $PWD/operator.yaml
kubectl apply -f crds.yaml -f common.yaml -f operator.yaml -f csi-operator.yaml
```
Verify that the Pods are up with the following command:
```bash
text
NAME                                          READY   STATUS    RESTARTS   AGE
ceph-csi-controller-manager-67d9b997c9-p22w6  1/1     Running   0          2d5h
rook-ceph-tools-7fd479bdc5-ltmtb              1/1     Running   0          2d22h
```
Configure the cluster.yaml file with the following commands:
```bash
bash
awk '
BEGIN{added=0}
/^[[:space:]]*osd:[[:space:]]*$/ { added=1 }
{
  print
  if (!added && $0 ~ /^[[:space:]]*resources:[[:space:]]*$/) {
    print "    osd:"
    print "      limits:"
    print "        memory: \"4096Mi\""
    print "      requests:"
    print "        memory: \"512Mi\""
    added=1
  }
}
' $PWD/cluster.yaml > $PWD/cluster.yaml.tmp && mv -f cluster.yaml.tmp cluster.yaml

sed -i \
  -e 's/^\(\s*useAllNodes:\s*\)true/\1false/' \
  -e 's/^\(\s*useAllDevices:\s*\)true/\1false/' \
  $PWD/cluster.yaml
```
Then introduce OSDs to cluster.yaml.  
**Note** that the OSD name is synonymous with the Worker name in the RKE2 cluster (must be defined in DNS).  
Also, the created symlink is synonymous with the device.
```bash
bash
root@second-cluster-master]# kubectl get nodes
NAME            STATUS   ROLES                       AGE    VERSION
BankCluster-01  Ready    control-plane,etcd,master   121d   v1.32.6+rke2r1
BankCluster-02  Ready    control-plane,etcd,master   121d   v1.32.6+rke2r1
BankCluster-03  Ready    control-plane,etcd,master   121d   v1.32.6+rke2r1
BankCluster-04  Ready    <none>                      121d   v1.32.6+rke2r1
BankCluster-05  Ready    <none>                      121d   v1.32.6+rke2r1
BankCluster-06  Ready    <none>                      121d   v1.32.6+rke2r1
BankCluster-07  Ready    <none>                      121d   v1.32.6+rke2r1
BankCluster-08  Ready    <none>                      121d   v1.32.6+rke2r1
BankCluster-09  Ready    <none>                      121d   v1.32.6+rke2r1
```
Here, 3 Worker Nodes are shown as an example.  
In the bank cluster, configure 6 Worker Nodes in this file.
```bash
bash
vim $PWD/cluster.yaml
```
```bash
yaml
...
priorityClassNames:
  #all: rook-ceph-default-priority-class
  mon: system-node-critical
  osd: system-node-critical
  mgr: system-cluster-critical
  #crashcollector: rook-ceph-crashcollector-priority-class
storage:
  useAllNodes: false
  useAllDevices: false
  #deviceFilter:
  config:
    # crushRoot: "custom-root"
    # metadataDevice: "md0"
    # databaseSizeMB: "1024"
    # osdsPerDevice: "1"
    # encryptedDevice: "true"
    # deviceClass: "myclass"
  allowDeviceClassUpdate: false
  allowOsdCrushWeightUpdate: false
  nodes:
    - name: "BankCluster-04"
      devices:
        - name: "/dev/rook-data-disk1"
    - name: "BankCluster-05"
      devices:
        - name: "/dev/rook-data-disk1"
    - name: "BankCluster-06"
      devices:
        - name: "/dev/rook-data-disk1"
    ...
```
Then apply cluster.yaml in the cluster and wait for mon, mgr, osd, and csi pods to reach Running status.
```bash
bash
kubectl apply -f $PWD/cluster.yaml
```
#### Introducing Storage Class to RKE2:

With the following commands, first add CephFileSystem to the Cluster and then introduce a StorageClass with the FileSystem role to RKE2.
```bash
bash
sed -i 's/reclaimPolicy:[[:space:]]*[Dd]elete/reclaimPolicy: Retain/g' $PWD/csi/cephfs/storageclass.yaml
kubectl apply -f $PWD/filesystem.yaml
kubectl apply -f $PWD/csi/cephfs/storageclass.yaml
```
After completing all the above steps, your pods should be in Running state in the cluster as shown below.
```bash
bash
[root@rook-ceph]# kubectl get pods -n rook-ceph
NAME                                                              READY   STATUS      RESTARTS   AGE
ceph-csi-controller-manager-67d9b997c9-p22w6                      1/1     Running     0          2d
rook-ceph-crashcollector-worker1-56545f94bf-hk4bk                 1/1     Running     0          8h
rook-ceph-crashcollector-worker2-56545f94bf-x2k8p                 1/1     Running     0          8h
rook-ceph-crashcollector-worker3-56545f94bf-9m6j4                 1/1     Running     0          8h
rook-ceph-crashcollector-worker4-56545f94bf-vs2qt                 1/1     Running     0          8h
rook-ceph-crashcollector-worker5-56545f94bf-fk8d2                 1/1     Running     0          8h
rook-ceph-crashcollector-worker6-56545f94bf-h6wz5                 1/1     Running     0          8h
rook-ceph-exporter-worker1-7cb8bbfc6b-4srg5                       1/1     Running     0          8h
rook-ceph-exporter-worker2-7cb8bbfc6b-4srg5                       1/1     Running     0          8h
rook-ceph-exporter-worker3-7cb8bbfc6b-4srg5                       1/1     Running     0          8h
rook-ceph-exporter-worker4-7cb8bbfc6b-4srg5                       1/1     Running     0          8h
rook-ceph-exporter-worker5-7cb8bbfc6b-4srg5                       1/1     Running     0          8h
rook-ceph-exporter-worker6-7cb8bbfc6b-4srg5                       1/1     Running     0          8h
rook-ceph-mds-myfs-a-57cc74698b-gjl59                             2/2     Running     0          8h
rook-ceph-mds-myfs-b-7498dd4584-p28k5                             2/2     Running     0          2d
rook-ceph-mgr-a-75864bc749-xq5gw                                  3/3     Running     0          2d
rook-ceph-mgr-b-659cddc4d9-q494s                                  3/3     Running     0          2d
rook-ceph-mon-a-6469d89d79-7vqrr                                  2/2     Running     0          2d
rook-ceph-mon-b-d96b6b4cc-m5st4                                   2/2     Running     0          2d
rook-ceph-mon-c-87f7b7667-w47gx                                   2/2     Running     0          2d
rook-ceph-operator-6d5ff5d6b9-t7zl9                               1/1     Running     0          2d
rook-ceph-osd-0-7457579959-66x9s                                  2/2     Running     0          2d
rook-ceph-osd-1-7457579959-9v9zz                                  2/2     Running     0          2d
rook-ceph-osd-2-7457579959-r8m77                                  2/2     Running     0          2d
rook-ceph-osd-3-7457579959-j7qqm                                  2/2     Running     0          2d
rook-ceph-osd-4-7457579959-tcsct                                  2/2     Running     0          2d
rook-ceph-osd-5-7457579959-5mw54                                  2/2     Running     0          2d
rook-ceph-osd-prepare-worker1-6kng9                               0/1     Completed   0          2d
rook-ceph-osd-prepare-worker2-2qs8r                               0/1     Completed   0          2d
rook-ceph-osd-prepare-worker3-nz5tg                               0/1     Completed   0          2d
rook-ceph-osd-prepare-worker4-9v9zz                               0/1     Completed   0          2d
rook-ceph-osd-prepare-worker5-kth8t                               0/1     Completed   0          2d
rook-ceph-osd-prepare-worker6-gh982                               0/1     Completed   0          2d
rook-ceph.cephfs.csi.ceph.com-ctrlplugin-6c9b8d66b4-qjfk4         5/5     Running     0          2d
rook-ceph.cephfs.csi.ceph.com-ctrlplugin-6c9b8d66b4-sm4qp         5/5     Running     0          2d
rook-ceph.cephfs.csi.ceph.com-nodeplugin-9hj8n                    2/2     Running     0          2d
rook-ceph.cephfs.csi.ceph.com-nodeplugin-4rfz6                    2/2     Running     0          2d
rook-ceph.cephfs.csi.ceph.com-nodeplugin-pp45n                    2/2     Running     0          2d
rook-ceph.cephfs.csi.ceph.com-nodeplugin-xbw8f                    2/2     Running     0          2d
rook-ceph.cephfs.csi.ceph.com-nodeplugin-zdjb4                    2/2     Running     0          2d
rook-ceph.cephfs.csi.ceph.com-nodeplugin-z5kxf                    2/2     Running     0          2d
```
If you need to remove and reinstall, be sure to use the official Ceph-Rook instructions.

#### Installing Toolbox Pod:
```bash
bash
kubectl apply -f toolbox.yaml
```
#### Testing Rook Ceph Performance:

Check cluster status with toolbox:
```bash
bash
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
Check cluster status by creating PVC and Pod:
```
```bash
bash
kubectl apply -f $PWD/csi/cephfs/pvc.yaml
kubectl get pvc
```
Expected output:
```bash
text
NAME         STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS      VOLUMEATTRIBUTESCLASS   AGE
cephfs-pvc   Bound    pvc-1622...                                1Gi        RWX            rook-cephfs       <unset>                 1m
```bash
bash
k get pv | grep default
pvc-1622ab7c-d9c6-4399-a841-dc994af8cc2b   1Gi        RWO            Delete           Bound    default/cephfs-pvc   rook-cephfs             <unset>                 1m
```
**Note** that Status must be Bound.

Finally, create a Pod:
```bash
bash
kubectl apply -f $PWD/csi/cephfs/pod.yaml
kubectl get pod -n default
```
Expected output:
```bash
text
NAME                 READY   STATUS    RESTARTS   AGE
csicephfs-demo-pod   1/1     Running   0          59s
```
#### 9-3) Rook-Ceph Cluster Update
This section has been prepared for updating and upgrading the Rook-Ceph cluster of the Borna digital Rial system. Note that upgrading to the next version is similar, and the cluster version upgrade must be done step by step (one Minor upgrade per step) and in coordination with Informatics Services Company.

**Note 1:** For a better understanding of cluster update conditions, it is recommended to study the following official document:
**https://rook.io/docs/rook/latest-release/Upgrade/rook-upgrade/**

**Note 2:** According to this document, updating from v1.18.x to v1.18.9 or v1.19.1 (direct update from v1.18.x to v1.19.1 is possible). Therefore, if using previous versions, the update must be done step by step according to the official document mentioned above, for example from v1.16 to v1.17, v1.17 to v1.18, and finally v1.18 to v1.19.1.

**Note 3:** During the update, the cluster may be damaged, disrupted, or even data may be lost. Therefore, be sure to back up.

**Note 4:** During the update, in short time intervals, the cluster may be unavailable for Read/Write operations.

##### 9-3-1) Obtaining Rook-Ceph Version
Obtain version v1.19.1 using the following command:
```bash
bash
## Version 1.19.1
git clone --single-branch --depth=1 --branch v1.19.1 https://github.com/rook/rook.git
cd rook/deploy/examples
```
**Note 1:** If you need to update from v1.18.x to v1.18.9, use the following command:
```bash
bash
## Version 1.18.9
git clone --single-branch --depth=1 --branch v1.18.9 https://github.com/rook/rook.git
cd rook/deploy/examples
```
**Note 2:** If any changes were made to any of the following files in previous versions (e.g., OSD Disk definition in cluster.yaml), to prevent errors and incidents, the previous changes must also be applied in this version:

- common.yaml

- crds.yaml

- operator.yaml

- csi-operator.yaml

- cluster.yaml

- filesystem.yaml

- csi/cephfs/storageclass.yaml

##### 9-3-2) Verifying Rook-Ceph Cluster and Infrastructure Health
Before starting the update, ensure the health of the cluster and that all Rook-Ceph cluster Pods and all Pods, PVs, and PVCs using the relevant Storage Class are running.
```bash
bash
## Rook-Ceph status
kubectl get cephcluster -n $ROOK_CLUSTER_NAMESPACE
NAME        DATADIRHOSTPATH   MONCOUNT   AGE    PHASE   MESSAGE                        HEALTH      EXTERNAL   FSID
rook-ceph   /var/lib/rook     3          137d   Ready   Cluster created successfully   HEALTH_WARN             9929e026-bc08-4afd-8ff4-faa58779161b
```
```bash
bash
## Ceph status
kubectl -n rook-ceph exec -it deployments/rook-ceph-tools -- bash
bash-5.1$ ceph -s
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
  client:   881 B/s rd, 1 op/s rd, 0 op/s wr
```
```bash
bash
## Rook-Ceph OSD status
kubectl -n rook-ceph exec -it deployments/rook-ceph-tools -- bash
bash-5.1$ ceph osd status
ID  HOST            USED   AVAIL   WR OPS  WR DATA  RD OPS  RD DATA  STATE
0   BankCluster-06  1003M  16.0G   0       9.76k    0       0        exists,up
1   BankCluster-05  890M   16.1G   0       0        0       0        exists,up
2   BankCluster-04  1185M  15.8G   0       0        0       0        exists,up
3   BankCluster-05  1177M  15.8G   1       7594     1       3610     exists,up
4   BankCluster-04  261M   16.7G   0       0        0       0        exists,up
5   BankCluster-04  791M   16.2G   0       0        0       0        exists,up
6   BankCluster-06  1177M  15.8G   0       0        0       0        exists,up
```
```bash
bash
## Rook-Ceph Pod status
kubectl get pods -n rook-ceph
NAME                                                              READY   STATUS      RESTARTS   AGE
ceph-csi-controller-manager-67d9b997c9-gb5br                      1/1     Running     0          141m
rook-ceph-crashcollector-BankCluster-04-54b87f8b96-284zk          1/1     Running     0          22h
rook-ceph-crashcollector-BankCluster-05-7655584b98-69264          1/1     Running     0          141m
rook-ceph-crashcollector-BankCluster-06-557b69fcc5-p6922          1/1     Running     0          139m
rook-ceph-exporter-BankCluster-04-858f4b6b9c-x5mwn                1/1     Running     0          22h
rook-ceph-exporter-BankCluster-05-7cf477c97f-99k86                1/1     Running     0          141m
rook-ceph-exporter-BankCluster-06-54f6f6d94d-r4csj                1/1     Running     0          139m
rook-ceph-mds-cephfs-a-6c9c7f994b-m5prp                           2/2     Running     0          22h
rook-ceph-mds-cephfs-b-6d8c78f6c9-np4ln                           2/2     Running     0          141m
rook-ceph-mgr-a-5b9d96455b-d6s7h                                  3/3     Running     0          146m
rook-ceph-mgr-b-6675b7d66d-b7bkb                                  3/3     Running     0          141m
rook-ceph-mon-b-69c7c7f9f-rnxmx                                   2/2     Running     0          141m
rook-ceph-mon-c-664db4fb4b-p7jsf                                  2/2     Running     0          22h
rook-ceph-mon-d-6d4464bcd6-sr728                                  2/2     Running     0          146m
rook-ceph-operator-5d46d7d965-bfqj4                               1/1     Running     0          141m
rook-ceph-osd-0-76794877df-pcmqp                                  2/2     Running     0          141m
rook-ceph-osd-1-6b75b4d9dd-qj89n                                  2/2     Running     0          146m
rook-ceph-osd-2-55df544596-zh78k                                  2/2     Running     0          22h
rook-ceph-osd-3-6f79fc6878-q5qkb                                  2/2     Running     0          146m
rook-ceph-osd-4-6944cf9555-2cgw9                                  2/2     Running     0          141m
rook-ceph-osd-5-65669bf4d5-26dnh                                  2/2     Running     0          22h
rook-ceph-osd-prepare-BankCluster-04-v8dc6                        0/1     Completed   0          140m
rook-ceph-osd-prepare-BankCluster-05-sh5nc                        0/1     Completed   0          140m
rook-ceph-tools-7b75b967db-qls54                                  1/1     Running     0          141m
rook-ceph.cephfs.csi.ceph.com-ctrlplugin-6c9b8d66b4-9m6tp         5/5     Running     0          146m
rook-ceph.cephfs.csi.ceph.com-ctrlplugin-6c9b8d66b4-nkd77         5/5     Running     0          141m
rook-ceph.cephfs.csi.ceph.com-nodeplugin-2grcd                    2/2     Running     2          22h
rook-ceph.cephfs.csi.ceph.com-nodeplugin-pktp2                    2/2     Running     1          22h
rook-ceph.cephfs.csi.ceph.com-nodeplugin-x2lrh                    2/2     Running     2          22h
```bash
bash
## Borna Pod status
# replace isc with your org id
kubectl get pods -n isc
NAME                              READY   STATUS    RESTARTS   AGE
fabric-operator-75fd94874-fssjh   1/1     Running   0          136m
isc-ca-bf77588f4-zrshr            1/1     Running   0          136m
isc-peer1-758b967fdc-pwh78        2/2     Running   0          141m
isc-peer2-6657fd4bb7-lchld        2/2     Running   0          20h
isc-peer3-6989bfb89-bhkmb         2/2     Running   0          136m
```
```bash
bash
## Borna PV status
# replace isc with your org id
kubectl get pv | egrep "NAME|isc"
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                           STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
pvc-020d42fe-4853-4ce4-bfc0-2214ac30dbf6   100Gi      RWO            Retain           Bound    isc/isc-peer1-pvc               rook-cephfs    <unset>                          20h
pvc-08184053-1fc7-4c20-b59a-cc6fa6f60311   100Gi      RWO            Retain           Bound    isc/isc-peer3-statedb-pvc       rook-cephfs    <unset>                          20h
pvc-5849d8e8-901b-4ba5-9987-38629e1c2da9   100Gi      RWO            Retain           Bound    isc/isc-peer2-pvc               rook-cephfs    <unset>                          20h
pvc-597f821e-4e2c-4162-ab4b-322f35c7cf64   1Gi        RWO            Retain           Bound    isc/isc-ca-pvc                  rook-cephfs    <unset>                          20h
pvc-9cd69666-d5fe-4432-8073-7226d074e511   100Gi      RWO            Retain           Bound    isc/isc-peer3-pvc               rook-cephfs    <unset>                          20h
pvc-f2362e88-f10a-46a7-8aac-69739db06e93   100Gi      RWO            Retain           Bound    isc/isc-peer2-statedb-pvc       rook-cephfs    <unset>                          20h
pvc-fe693550-2f3a-4034-a043-b7ac421d82a7   100Gi      RWO            Retain           Bound    isc/isc-peer1-statedb-pvc       rook-cephfs    <unset>                          20h
```
```bash
bash
## Borna PVC status
# replace isc with your org id
kubectl get pvc -n isc
NAME                     STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
isc-ca-pvc               Bound    pvc-597f821e-4e2c-4162-ab4b-322f35c7cf64   1Gi        RWO            rook-cephfs    <unset>                 20h
isc-peer1-pvc            Bound    pvc-020d42fe-4853-4ce4-bfc0-2214ac30dbf6   100Gi      RWO            rook-cephfs    <unset>                 20h
isc-peer1-statedb-pvc    Bound    pvc-fe693550-2f3a-4034-a043-b7ac421d82a7   100Gi      RWO            rook-cephfs    <unset>                 20h
isc-peer2-pvc            Bound    pvc-5849d8e8-901b-4ba5-9987-38629e1c2da9   100Gi      RWO            rook-cephfs    <unset>                 20h
isc-peer2-statedb-pvc    Bound    pvc-f2362e88-f10a-46a7-8aac-69739db06e93   100Gi      RWO            rook-cephfs    <unset>                 20h
isc-peer3-pvc            Bound    pvc-9cd69666-d5fe-4432-8073-7226d074e511   100Gi      RWO            rook-cephfs    <unset>                 20h
isc-peer3-statedb-pvc    Bound    pvc-08184053-1fc7-4c20-b59a-cc6fa6f60311   100Gi      RWO            rook-cephfs    <unset>                 20h
```
##### 9-3-3) Checking Current Cluster Version
View the current Ceph Image and Rook Image versions using the following commands.
```bash
bash
## Ceph Image Version
ROOK_CLUSTER_NAMESPACE=rook-ceph
POD_NAME=$(kubectl -n $ROOK_CLUSTER_NAMESPACE get pod -o custom-columns=name:.metadata.name --no-headers | grep rook-ceph-mon-a)
kubectl -n $ROOK_CLUSTER_NAMESPACE get pod ${POD_NAME} -o jsonpath='{.spec.containers[0].image}'
quay.io/ceph/ceph:v19.2.3
```
**Note:** If your current version is v19.2.3, there is no need to execute sections 9-3-5 and 9-3-6.
```bash
bash
## Rook Image Version
ROOK_CLUSTER_NAMESPACE=rook-ceph
POD_NAME=$(kubectl -n $ROOK_CLUSTER_NAMESPACE get pod -o custom-columns=name:.metadata.name --no-headers | grep rook-ceph-operator)
kubectl -n $ROOK_CLUSTER_NAMESPACE get pod ${POD_NAME} -o jsonpath='{.spec.containers[0].image}'
rook/ceph:v1.18.8
```
##### 9-3-4) Applying Rook Operator Changes
Update new changes such as CRD and Rook Image version of the Rook Operator pod with the following command.
```bash
bash
## Version 1.19.1
kubectl apply -f crds.yaml -f common.yaml -f operator.yaml -f csi-operator.yaml
kubectl -n rook-ceph set image deploy/rook-ceph-operator rook-ceph-operator=rook/ceph:v1.19.1
deployment.apps/rook-ceph-operator image updated
```
**Note 1:** If you need to update from v1.18.x to v1.18.9, use the following command:
```bash
bash
## Version 1.18.9
kubectl -n rook-ceph set image deploy/rook-ceph-operator rook-ceph-operator=rook/ceph:v1.18.9
deployment.apps/rook-ceph-operator image updated
```
**Note 2:** To monitor the update process, use the following command:
```bash
bash
## Change Rook image version process
ROOK_CLUSTER_NAMESPACE=rook-ceph
watch --exec kubectl -n $ROOK_CLUSTER_NAMESPACE get deployments -l rook_cluster=$ROOK_CLUSTER_NAMESPACE -o jsonpath='{range .items[*]}{.metadata.name}{"\treq/upd/avl: "}{.spec.replicas}{"/"}{.status.updatedReplicas}{"/"}{.status.readyReplicas}{"\trook-version="}{.metadata.labels.rook-version}{"\n"}{end}'
```
Expected output:
```bash
text
rook-ceph-crashcollector-BankCluster-04 req/upd/avl: 1/1/1 rook-version=v1.19.1
rook-ceph-crashcollector-BankCluster-05 req/upd/avl: 1/1/1 rook-version=v1.19.1
rook-ceph-crashcollector-BankCluster-04 req/upd/avl: 1/1/1 rook-version=v1.19.1
rook-ceph-crashcollector-BankCluster-06 req/upd/avl: 1/1/1 rook-version=v1.19.1
rook-ceph-exporter-BankCluster-04 req/upd/avl: 1/1/1 rook-version=v1.19.1
rook-ceph-exporter-BankCluster-05 req/upd/avl: 1/1/1 rook-version=v1.19.1
rook-ceph-exporter-BankCluster-04 req/upd/avl: 1/1/1 rook-version=v1.19.1
rook-ceph-exporter-BankCluster-06 req/upd/avl: 1/1/1 rook-version=v1.19.1
rook-ceph-mds-cephfs-a req/upd/avl: 1/1/1 rook-version=v1.18.9
rook-ceph-mds-cephfs-b req/upd/avl: 1/1/1 rook-version=v1.18.9
rook-ceph-mgr-a req/upd/avl: 1/1/1 rook-version=v1.18.9
rook-ceph-mgr-b req/upd/avl: 1/1/1 rook-version=v1.18.9
rook-ceph-mon-a req/upd/avl: 1/1/1 rook-version=v1.18.9
rook-ceph-mon-b req/upd/avl: 1/1/1 rook-version=v1.18.9
rook-ceph-mon-c req/upd/avl: 1/1/1 rook-version=v1.18.9
rook-ceph-osd-0 req/upd/avl: 1/1/1 rook-version=v1.18.9
rook-ceph-osd-1 req/upd/avl: 1/1/1 rook-version=v1.18.9
rook-ceph-osd-15 req/upd/avl: 1/1/ rook-version=v1.18.9
rook-ceph-osd-16 req/upd/avl: 1/1/ rook-version=v1.18.9
rook-ceph-osd-17 req/upd/avl: 1/1/1 rook-version=v1.18.9
rook-ceph-osd-2 req/upd/avl: 1/1/1 rook-version=v1.18.9
rook-ceph-osd-3 req/upd/avl: 1/1/1 rook-version=v1.18.9
rook-ceph-osd-4 req/upd/avl: 1/1/1 rook-version=v1.18.9
rook-ceph-osd-5 req/upd/avl: 1/1/1 rook-version=v1.18.9
rook-ceph-osd-6 req/upd/avl: 1/1/1 rook-version=v1.18.9
```
**Note 3:** Check cluster health with the following command. At this stage, it must be HEALTH_OK.
```bash
bash
## Ceph status
kubectl -n rook-ceph exec -it deployments/rook-ceph-tools -- bash
watch ceph -s
```
Expected output:
```bash
text
cluster:
  id:     9929e026-bc08-4afd-8ff4-faa58779161b
  health: HEALTH_OK
services:
  mon: 3 daemons, quorum a,b,c (age 29s)
  mgr: a(active, since 3m), standbys: b
  mds: 1/1 daemons up, 1 hot standby
  osd: 8 osds: 8 up (since 71m), 8 in (since 3d)
data:
  volumes: 1/1 healthy
  pools:   4 pools, 97 pgs
  objects: 5.57k objects, 2.4 GiB
  usage:   8.5 GiB used, 117 GiB / 125 GiB avail
  pgs:     97 active+clean
io:
  client:   12 MiB/s rd, 8.1 KiB/s wr, 4 op/s rd, 0 op/s wr
```
**Note 4:** To ensure the update process is complete and the Rook image has changed, use the following command:
```bash
bash
## Check Rook image
kubectl -n $ROOK_CLUSTER_NAMESPACE get deployment -l rook_cluster=$ROOK_CLUSTER_NAMESPACE -o jsonpath='{range .items[*]}{"rook-version="}{.metadata.labels.rook-version}{"\n"}{end}' | sort | uniq
rook-version=v1.19.1
```
**Note 5:** If monitoring with Prometheus is enabled, use the following command to update Prometheus RBAC:
```bash
bash
kubectl apply -f monitoring/rbac.yaml
```
##### 9-3-5) Applying Ceph Image Change
Update the Ceph Image version with the following command.
```bash
bash
## Check Rook image
ROOK_CLUSTER_NAMESPACE=rook-ceph
NEW_CEPH_IMAGE='quay.io/ceph/ceph:v19.2.3'
kubectl -n $ROOK_CLUSTER_NAMESPACE patch CephCluster $ROOK_CLUSTER_NAMESPACE --type=merge -p "{\"spec\": {\"cephVersion\": {\"image\": \"$NEW_CEPH_IMAGE\"}}}"
```
**Note 1:** Due to Rook-Ceph v1.18.x and v1.19.x using Ceph Image v19.2.3, the following output will be received and no update will be performed:
```bash
text
cephcluster.ceph.rook.io/rook-ceph patched (no change)
```
**Note 2:** If the Rook-Ceph version differs, monitor the update process with the following command:
```bash
bash
watch --exec kubectl -n $ROOK_CLUSTER_NAMESPACE get deployments -l rook_cluster=$ROOK_CLUSTER_NAMESPACE -o jsonpath='{range .items[*]}{.metadata.name}{"\treq/upd/avl: "}{.spec.replicas}{"/"}{.status.updatedReplicas}{"/"}{.status.readyReplicas}{"\tceph-version="}{.metadata.labels.ceph-version}{"\n"}{end}'
```
**Note 3:** Due to the Ceph Image version change and restart of related pods, observing temporary HEALTH_WARN, OSD Down, Degraded data, and Recovery operations in the following command output is normal:
```bash
bash
## Ceph status
kubectl -n rook-ceph exec -it deployments/rook-ceph-tools -- bash
watch ceph -s
```
Expected output:
```bash
text
cluster:
  id:     9929e026-bc08-4afd-8ff4-faa58779161b
  health: HEALTH_WARN
          1 osds down
          1 host (1 osds) down
          Reduced data availability: 1 pg peering
          Degraded data redundancy: 3004/16773 objects degraded (17.910%), 38 pgs degraded
services:
  mon: 3 daemons, quorum a,b,c (age 5m)
  mgr: a(active, since 4m), standbys: b
  mds: 1/1 daemons up, 1 hot standby
  osd: 8 osds: 7 up (since 11s), 8 in (since 3d); 9 remapped pgs
data:
  volumes: 1/1 healthy
  pools:   4 pools, 97 pgs
  objects: 5.59k objects, 2.5 GiB
  usage:   8.7 GiB used, 116 GiB / 125 GiB avail
  pgs:     4.124% pgs not active
           3004/16773 objects degraded (17.910%)
           218/16773 objects misplaced (1.300%)
           40 active+clean
           36 active+undersized+degraded
           13 active+undersized
           2 peering
           2 remapped+peering
           2 active+clean+remapped
           1 active+undersized+degraded+remapped+backfilling
           1 active+undersized+degraded+remapped+backfill_wait
io:
  client:   42 KiB/s wr, 0 op/s rd, 1 op/s wr
  recovery: 682 KiB/s, 9 keys/s, 2 objects/s
```
**Note 4:** To ensure the update process is complete and the Ceph image has changed, use the following command:
```bash
bash
kubectl -n $ROOK_CLUSTER_NAMESPACE get deployment -l rook_cluster=$ROOK_CLUSTER_NAMESPACE -o jsonpath='{range .items[*]}{"ceph-version="}{.metadata.labels.ceph-version}{"\n"}{end}' | sort | uniq
ceph-version=19.2.3-0
```
```bash
bash
## Ceph status
kubectl -n rook-ceph exec -it deployments/rook-ceph-tools -- bash
ceph -s
```
Expected output:
```bash
text
cluster:
  id:     9929e026-bc08-4afd-8ff4-faa58779161b
  health: HEALTH_OK
services:
  mon: 3 daemons, quorum a,b,c (age 15m)
  mgr: a(active, since 14m), standbys: b
  mds: 1/1 daemons up, 1 hot standby
  osd: 8 osds: 8 up (since 50s), 8 in (since 3d)
data:
  volumes: 1/1 healthy
  pools:   4 pools, 97 pgs
  objects: 5.48k objects, 2.0 GiB
  usage:   6.6 GiB used, 118 GiB / 125 GiB avail
  pgs:     97 active+clean
io:
  client:   4.0 KiB/s rd, 77 KiB/s wr, 2 op/s rd, 1 op/s wr
```
```bash
bash
## Check Ceph version
kubectl -n rook-ceph exec -it deployments/rook-ceph-tools -- bash
ceph versions
{
  "mon": {
    "ceph version 19.2.3 (c92aebb279828e9c3c1f5d24613efca272649e62) squid (stable)": 3
  },
  "mgr": {
    "ceph version 19.2.3 (c92aebb279828e9c3c1f5d24613efca272649e62) squid (stable)": 2
  },
  "osd": {
    "ceph version 19.2.3 (c92aebb279828e9c3c1f5d24613efca272649e62) squid (stable)": 8
  },
  "mds": {
    "ceph version 19.2.3 (c92aebb279828e9c3c1f5d24613efca272649e62) squid (stable)": 2
  },
  "overall": {
    "ceph version 19.2.3 (c92aebb279828e9c3c1f5d24613efca272649e62) squid (stable)": 15
  }
}
```
##### 9-3-6) Applying Ceph-Tools Change
To change the Ceph Image for the Ceph-Tools pod, use the following command.
```bash
bash
NEW_CEPH_IMAGE='quay.io/ceph/ceph:v19.2.3'
kubectl -n $ROOK_CLUSTER_NAMESPACE set image deploy/rook-ceph-tools rook-ceph-tools=$NEW_CEPH_IMAGE
deployment.apps/rook-ceph-tools image updated
```
To check the Ceph-tools pod update, use the following command.
```bash
bash
kubectl -n rook-ceph describe deployments rook-ceph-tools | grep -i image: | awk '{print $NF}'
quay.io/ceph/ceph:v19.2.3-0
```
##### 9-3-7) Checking Infrastructure Status
According to section 9-3-2, verify the cluster health and that all Rook-Ceph cluster Pods and all Pods, PVs, and PVCs using the relevant Storage Class are running.

**Note:** To ensure proper re-Bound operation, restart some of the Pods related to the Storage Class and check their status.
