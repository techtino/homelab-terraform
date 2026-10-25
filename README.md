# Kubernetes Homelab (WIP)

Use OpenTofu to build a Kubernetes cluster on Proxmox.

The cluster uses:

- Debian VMs on Proxmox
- Cilium networking
- MetalLB for LAN load balancer IPs
- Traefik with Kubernetes Gateway API
- TrueNAS NVMe-oF storage through the TrueNAS CSI driver
- Portainer for web management

## Before You Start

You need:

- A working Proxmox host
- A Debian 13 cloud image
- TrueNAS with the `FastNAS` pool and NVMe-oF enabled
- OPNsense/Unbound for local DNS
- OpenTofu, `kubectl`, and SSH on your workstation
- An SSH key authorized on Proxmox and the Kubernetes VMs (ssh-keygen + ssh-copy-id to proxmox)

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
tofu apply -parallelism=1
```

The Proxmox VMs use TrueNAS-backed NVMe/TCP storage. Apply with parallelism
set to `1` so the storage plugin handles VM operations sequentially; the
default OpenTofu parallelism can overwhelm it when several VMs are created at
once. This setting applies only to this Proxmox apply; the Kubernetes project
can use the default parallelism.

The Proxmox project:

1. Creates the control-plane and worker VMs.
2. Installs containerd and Kubernetes packages.
3. Runs `kubeadm init` on the control node without installing kube-proxy.
4. Joins the workers automatically.
5. Copies the control-plane kubeconfig for the `techtino` user.

Cilium is installed by the Kubernetes project after the workers have joined and
replaces kube-proxy for Kubernetes Service routing. Cilium reads the current
control-plane IP from the Proxmox project state and connects to the API server
on port `6443`. Apply the Proxmox project before the Kubernetes project.

## Install Kubernetes Services

Copy the control-plane kubeconfig to the machine where you will run `kubectl`
and OpenTofu. Replace `<control-plane-ip>` with the control-plane VM's current
IP address:

```bash
mkdir -p ~/.kube
scp techtino@<control-plane-ip>:/home/techtino/.kube/config ~/.kube/config
chmod 600 ~/.kube/config
```

If `~/.kube/config` already exists, back it up or merge the new cluster
configuration instead of overwriting it. Keep kubeconfig private and do not
commit it. Confirm that `kubectl` can reach the new cluster, then run:

```bash
kubectl get nodes
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
- Metrics Server with CA-verified kubelet connections
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

## Kubelet serving certificates

Kubeadm is configured to request CA-signed kubelet serving certificates through
the Kubernetes CSR API. Metrics Server trusts the kubeadm cluster CA and uses
node IPs, so cluster DNS does not need node records.

For an existing cluster, apply the kubelet ConfigMap and Metrics Server changes
from the `kubernetes` directory:

```bash
cd ~/homelab-terraform/kubernetes
tofu apply -target=helm_release.metrics_server
```

On each existing node, enable serving-certificate requests in the local kubelet
configuration and restart kubelet:

```bash
sudo sed -i '/^serverTLSBootstrap:/d' /var/lib/kubelet/config.yaml
printf '\nserverTLSBootstrap: true\n' | sudo tee -a /var/lib/kubelet/config.yaml
sudo systemctl restart kubelet
```

Inspect each `kubernetes.io/kubelet-serving` CSR. Check its requested node
identity and IP SANs before approving it:

```bash
kubectl get csr
kubectl describe csr <csr-name>
kubectl get csr <csr-name> -o jsonpath='{.spec.request}' | base64 -d | openssl req -noout -text
kubectl certificate approve <csr-name>
```

Kubernetes does not automatically approve serving CSRs. New CSRs for certificate
rotation also require approval unless a policy-aware approver is installed.

Verify Metrics Server and the aggregated API are ready:

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/instance=metrics-server
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl top nodes
```

The Portainer namespace should finish deleting after the Metrics API becomes
available.

Check storage with:

```bash
kubectl get pods -n truenas-csi
kubectl get storageclass
kubectl get pvc -A
kubectl get pv
```

PVCs use `Retain`, so deleting a claim may leave data behind in TrueNAS. Treat PVC and PV deletion as data-destructive operations and check the corresponding TrueNAS volume first.

App modules can also mount existing node directories as host paths. Set
`extra_volumes` to map each node path to its container mount path:

```hcl
extra_volumes = {
  "/mnt/media" = "/media"
}
```

The node path must already exist on whichever node runs the app.

## DNS And Gateway API

MetalLB uses this LAN address range:

```text
192.168.1.240-192.168.1.250
```

Traefik uses:

```text
192.168.1.241
```

Terraform downloads and manages the Gateway API standard CRDs at the pinned
version declared in `kubernetes/providers.tf`; the Gateway and HTTPRoutes wait
for those CRDs to be installed.

Add these host overrides in OPNsense/Unbound:

```text
whoami.home.arpa     -> 192.168.1.241
portainer.home.arpa  -> 192.168.1.241
```

Test routing without DNS:

```bash
curl -H 'Host: portainer.home.arpa' http://192.168.1.241/
```

Traefik serves HTTPS using per-application certificates issued by the in-cluster
step-ca through cert-manager and step-issuer. Install step-ca's root certificate on each client
that should trust these internal certificates. Export the root PEM with:

```bash
kubectl get configmap step-certificates-certs -n step-ca \
  -o jsonpath='{.data.root_ca\.crt}' > step-ca-root.crt
```

Test HTTPS without DNS after trusting that root:

```bash
curl --cacert step-ca-root.crt \
  --resolve portainer.home.arpa:443:192.168.1.241 \
  https://portainer.home.arpa/
```

Headlamp is available at `https://headlamp.home.arpa`. It uses a read-only
Kubernetes `view` role, extended to include Gateway API resources. Generate a
login token when needed with:

```bash
kubectl create token headlamp -n headlamp
```

## Check The Cluster

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get svc -A
kubectl get gateways,httproutes -A
```

A healthy cluster has all nodes `Ready`, Cilium and CSI pods running, PVCs `Bound`, the Traefik Gateway accepted, and Traefik assigned `192.168.1.241`.

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
kubectl get pods,pvc,svc,httproute -n portainer
```

Portainer uses one replica and persistent storage. It is designed to restart on another node, not to run multiple active replicas against the same database.
