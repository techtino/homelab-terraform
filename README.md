# Kubernetes Homelab (WIP)

Use OpenTofu to build a Kubernetes cluster on Proxmox.

The cluster uses:

- Debian VMs on Proxmox
- Cilium networking
- MetalLB for LAN load balancer IPs
- Traefik for ingress
- TrueNAS NVMe-oF storage through the TrueNAS CSI driver
- Portainer for web management

## Before You Start

You need:

- A working Proxmox host
- A Debian 13 cloud image
- TrueNAS with the `FastNAS` pool and NVMe-oF enabled
- OPNsense/Unbound for local DNS
- OpenTofu, `kubectl`, and SSH on your workstation
- An SSH key authorized on Proxmox and the Kubernetes VMs

The Proxmox datastore `truenas-nvme` must already exist. Set it up before
running the Proxmox project as described below.

## Secrets

Create one ignored `.env` file in the repository root. It must contain
`TF_VAR_` names so OpenTofu can use the values in every project:

```bash
cp .env.example .env
source .env
```

Set the real values for the SSH password hash, Proxmox API token, and TrueNAS
API key. Keep `.env` private and never commit it.

Create a password hash with:

```bash
openssl passwd -6
```

Never commit secrets, kubeconfig files, or OpenTofu state.

## Proxmox TrueNAS Storage

Proxmox uses the TrueNAS storage plugin over NVMe/TCP. This is a manual
Proxmox prerequisite because the bpg provider does not manage the custom
`truenasplugin` storage type.

On the Proxmox node:

```bash
apt update
apt install nvme-cli truenas-proxmox-plugin
```

In TrueNAS:

1. Create the dataset `FastNAS/proxmox`.
2. Enable and start the NVMe-oF Target service.
3. Ensure the TrueNAS API key used below can manage datasets and NVMe-oF.

Add this entry to `/etc/pve/storage.cfg` on the Proxmox node. Proxmox shares
this file across the cluster, so it only needs to be added once:

```text
truenasplugin: truenas-nvme
    tn_api_host 192.168.1.118
    tn_api_key YOUR_TRUENAS_API_KEY
    tn_api_insecure 1
    tn_transport_mode nvme-tcp
    tn_subsystem_nqn nqn.2005-10.org.freenas.ctl:proxmox-nvme
    tn_dataset FastNAS/proxmox
    tn_discovery_portal 192.168.1.118:4420
    content images
    shared 1
```

Check it before running OpenTofu:

```bash
pvesm status
nvme list-subsys
```

The plugin creates and manages the Proxmox volume objects on TrueNAS. Do not
manually create those per-VM ZVOLs or NVMe namespaces.

## Build The Cluster

Load the SSH key used by the Proxmox provider and worker join step:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

Create the VMs and bootstrap Kubernetes:

```bash
cd ~/homelab-terraform/proxmox
tofu init
tofu plan
tofu apply
```

The Proxmox project:

1. Creates the control-plane and worker VMs.
2. Installs containerd and Kubernetes packages.
3. Runs `kubeadm init` on the control node.
4. Joins the workers automatically.
5. Copies the control-plane kubeconfig for the `techtino` user.

Cilium is installed by the Kubernetes project after the workers have joined.

## Install Kubernetes Services

Make sure `~/.kube/config` points to the new cluster, then run:

```bash
cd ~/homelab-terraform/kubernetes
tofu init
tofu plan
tofu apply
```

This installs and manages:

- Cilium
- MetalLB
- Traefik
- TrueNAS CSI
- StorageClasses and PVCs
- Portainer
- The example `hello` application

## Storage

TrueNAS CSI uses:

```text
TrueNAS:       192.168.1.118
Pool:          FastNAS
NVMe-oF:       192.168.1.118:4420
StorageClass:  truenas-nvmeof
```

The Kubernetes nodes need `open-iscsi` and `nvme-cli`. Cloud-init installs them automatically.

Check storage with:

```bash
kubectl get pods -n truenas-csi
kubectl get storageclass
kubectl get pvc -A
kubectl get pv
```

PVCs use `Retain`, so deleting a claim may leave data behind in TrueNAS. Treat PVC and PV deletion as data-destructive operations and check the corresponding TrueNAS volume first.

## DNS And Ingress

MetalLB uses this LAN address range:

```text
192.168.1.240-192.168.1.250
```

Traefik uses:

```text
192.168.1.241
```

Add these host overrides in OPNsense/Unbound:

```text
hello.home.arpa      -> 192.168.1.241
portainer.home.arpa  -> 192.168.1.241
```

Test ingress without DNS:

```bash
curl -H 'Host: portainer.home.arpa' http://192.168.1.241/
```

## Check The Cluster

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get svc -A
kubectl get ingress -A
```

A healthy cluster has all nodes `Ready`, Cilium and CSI pods running, PVCs `Bound`, and Traefik assigned `192.168.1.241`.

## Common Recovery Commands

Return a node to scheduling after a maintenance test:

```bash
kubectl uncordon k8s-worker3
```

Watch Portainer move between nodes:

```bash
kubectl get pods -n portainer -o wide -w
```

Check Portainer:

```bash
kubectl get pods,pvc,svc,ingress -n portainer
```

Portainer uses one replica and persistent storage. It is designed to restart on another node, not to run multiple active replicas against the same database.
