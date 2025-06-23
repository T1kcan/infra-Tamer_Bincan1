# Provision Kubernetes Nodes via Terraform on Proxmox Server
- Install terraform on deploy node:
```bash
sudo apt update && sudo apt install terraform
command -v terraform
mkdir terraform 
cd terraform
vim main.tf
```
# Create User, Role and Token for Terraform on Proxmox Server:
```bash
pveum role add TerraformProv -privs "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt SDN.Use"
pveum user add terraform-prov@pve --password password
pveum aclmod / -user terraform-prov@pve -role TerraformProv

pveum role modify TerraformProv -privs "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt SDN.Use"

pveum user token add terraform-prov@pve mytoken
```
- Take notes of your crendentials
```text
terraform-prov@pve!mytoken
a966a069-9b45-42fe-ba6b-804eacad730c
# use single quotes for the API token ID because of the exclamation mark
export PM_API_TOKEN_ID='terraform-prov@pve!mytoken'
export PM_API_TOKEN_SECRET="xxxx-xxx"
export PM_USER="terraform-prov@pve"
export PM_PASS="password"
```
- Create Cloud Teplate:
Use following cloud image to create ubuntu 24.04 VM template:
https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

- Give following commands on Proxmox Server to create cloud template:
```bash
qm create 5000 --memory 2048 --core 2 --name ubuntu-cloud --net0 virtio,bridge=vmbr0
cd /var/lib/vz/template/iso/
qm importdisk 5000 lunar-server-cloudimg-amd64-disk-kvm.img <YOUR STORAGE HERE>
qm set 5000 --scsihw virtio-scsi-pci --scsi0 <YOUR STORAGE HERE>:5000/vm-5000-disk-0.raw
qm set 5000 --ide2 <YOUR STORAGE HERE>:cloudinit
qm set 5000 --boot c --bootdisk scsi0
qm set 5000 --serial0 socket --vga serial0

```Text
Notes:
- balooning of memory
- change cpu type to host and numa enable
- hdd sdd emualation
- cloud init
- user ubuntu
- qm disk resize 199 scsi0 10G
- lvresize -l +100%FREE /dev/pve/root
- resize2fs /dev/mapper/pve-root
```

## Create VMs
- Clone Repo and create Kubernetes Control and Worker nodes via terraform on Proxmox with following commands:
```bash
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply --auto-approve
```

# Deploy Kubernetes via Kubespray

- Edit /etc/hosts file to add the IP addresses and hostnames of your Kubernetes cluster nodes. This is necessary for the nodes to resolve each other's hostnames correctly.
```bash
vi /etc/hosts
192.168.0.29 control1
192.168.0.28 control2
192.168.0.31 control3
192.168.0.30 worker1
192.168.0.32 worker2
192.168.0.51 deploy
```
- Generate SSH keys and copy them to the each worker and control nodes to enable passwordless SSH access
```bash
ssh-keygen -t rsa 
ssh-copy-id worker1
...
```
- Set the hostname for the control node and configure sudoers to allow passwordless sudo access
- Install necessary packages like vim and configure sudoers file
```bash
sudo apt install vim
sudo vi /etc/sudoers
```
- or edit with visudo:
```bash
sudo hostnamectl set-hostname control1
sudo visudo
%sudo ALL=(ALL) NOPASSWD:ALL
```

## Kubespray
- Clone Kubespray Repository:
```bash
sudo apt install git -y
git clone https://github.com/kubernetes-sigs/kubespray.git
cd kubespray
```
Note: Ansible playbook requires ping utils present on each machine, thence install the packet if necessary.
```bash
sudo apt-get install -y iputils-ping
```
Note: Ansible playbook uses root account as become user by default thence make sure public key present on each nodes' /root/.ssh/authorized_keys file:
```bash
ssh worker1
sudo cp /home/cluster/.ssh/authorized_keys /root/.ssh/authorized_keys
sudo cat /root/.ssh/authorized_keys
```
## Install Docker for running Kubespray:
### Add Docker's official GPG key:
```bash
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
# Add the repository to Apt sources:
echo   "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" |   sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo docker run hello-world                                                
sudo usermod -aG docker $USER
sudo usermod -aG docker cluster
newgrp docker
docker run hello-world
```
## Create/Edit Invertory File

~/kubespray/inventory/sample/inventory.ini
```ini
# This inventory describe a HA typology with stacked etcd (== same nodes as control plane)
# and 3 worker nodes
# See https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html
# for tips on building your # inventory

# Configure 'ip' variable to bind kubernetes services on a different ip than the default iface
# We should set etcd_member_name for etcd cluster. The node that are not etcd members do not need to set the value,
# or can set the empty string value.
[kube_control_plane]
node1 ansible_host=192.168.0.29  # ip=10.3.0.1 etcd_member_name=etcd1
node2 ansible_host=192.168.0.28  # ip=10.3.0.2 etcd_member_name=etcd2
node3 ansible_host=192.168.0.31  # ip=10.3.0.3 etcd_member_name=etcd3

[etcd:children]
kube_control_plane

[kube_node]
node4 ansible_host=192.168.0.30  # ip=10.3.0.4
node5 ansible_host=192.168.0.32  # ip=10.3.0.5
# node6 ansible_host=95.54.0.17  # ip=10.3.0.6
```
## Run Kubespray
```bash
docker run --rm -it --mount type=bind,source="$(pwd)"/inventory/sample,dst=/inventory \
  --mount type=bind,source="${HOME}"/.ssh/id_rsa,dst=/root/.ssh/id_rsa \
  quay.io/kubespray/kubespray:v2.28.0 bash

# Inside the container you may now run the kubespray playbooks:
ansible-playbook -i /inventory/inventory.ini --private-key /root/.ssh/id_rsa cluster.yml
```

## Install kubectl
- On deploy node install kubectl to gather cluster information:
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```
## Gather Cluster Config
```bash
ssh control1 sudo cp /etc/kubernetes/admin.conf /home/cluster/config
ssh control1 sudo chmod +r ~/config
scp control1:~/config .
mkdir .kube
mv config .kube
```
