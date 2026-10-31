# Kubernetes Homelab (WIP)

Use OpenTofu to build a Kubernetes cluster on Proxmox.

The cluster uses:

- Debian VMs on Proxmox
- Cilium networking
- MetalLB for LAN load balancer IPs
- Traefik with Kubernetes Gateway API
- TrueNAS NVMe-oF storage through the TrueNAS CSI driver
- cert-manager with an in-cluster step-ca for internal TLS
- Headlamp for web management
- VictoriaMetrics, VictoriaLogs and Grafana for observability
- vmalert and Alertmanager for alerts sent to Pushover

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

Set the real values for the SSH password hash, Proxmox API token, TrueNAS
API key, and Pushover user key and application token. Keep `.env` private and never commit it.

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
- Traefik, the Gateway, HTTPRoutes and OPNsense DNS overrides
- cert-manager, step-ca and step-issuer
- TrueNAS CSI and the `truenas-nvmeof` StorageClass
- Metrics Server with CA-verified kubelet connections
- Headlamp
- VictoriaMetrics, VictoriaLogs and Grafana
- vmalert and Alertmanager, sending alerts to Pushover
- The apps in `kubernetes/apps.tf` (`whoami`, `test`)

## Storage

TrueNAS CSI uses:

```text
TrueNAS:       192.168.1.118
Pool:          FastNAS
NVMe-oF:       192.168.1.118:4420
StorageClass:  truenas-nvmeof
```

The Kubernetes nodes need `open-iscsi` and `nvme-cli`. Cloud-init installs them automatically.

PVCs can be snapshotted. `snapshot-controller` in `kube-system` provides the
VolumeSnapshot API, and `truenas-snapshotclass` is the default
VolumeSnapshotClass. Each VolumeSnapshot is a ZFS snapshot on TrueNAS, and
deleting the VolumeSnapshot deletes it. To snapshot a PVC:

```bash
kubectl apply -f - <<'EOF'
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: test-data-before-upgrade
  namespace: homelab-apps
spec:
  source:
    persistentVolumeClaimName: <pvc-name>
EOF
kubectl get volumesnapshot -n homelab-apps
```

To restore, create a new PVC with `dataSource` pointing at the VolumeSnapshot
(`kind: VolumeSnapshot`, `apiGroup: snapshot.storage.k8s.io`).

## Kubelet serving certificates

Kubeadm is configured (through cloud-init) to request CA-signed kubelet serving
certificates through the Kubernetes CSR API. Metrics Server trusts the kubeadm
cluster CA and uses node IPs, so cluster DNS does not need node records.

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

Check storage with:

```bash
kubectl get pods -n truenas-csi
kubectl get storageclass
kubectl get pvc -A
kubectl get pv
```

PVCs use `Retain`, so deleting a claim may leave data behind in TrueNAS. Treat PVC and PV deletion as data-destructive operations and check the corresponding TrueNAS volume first.

## Adding An App

Everything served through the gateway gets `<name>.home.arpa`, a certificate
in a `<name>-tls` secret, an HTTPRoute and an OPNsense DNS override, all derived
from the name:

- Simple container apps: add an entry to `local.apps` in `kubernetes/apps.tf`.
- Devices outside the cluster: add an IP and port to `local.external_services`
  in `kubernetes/external.tf`.
- Any other in-cluster Service (for example from a Helm chart): add
  `name = { namespace, port }` to `local.routed_apps` in `kubernetes/routes.tf`.
  The Service must be called `name`.

Set `auth = true` on an entry to put it behind basic auth (Traefik's basicAuth
middleware, `kubernetes/auth.tf`). It is on for whoami, test and headlamp, and
off for apps that have their own login. Set or change the credentials with
`scripts/set-basic-auth.sh [username]`, which writes
`TF_VAR_basic_auth_htpasswd` to `.env`, then re-apply.

Apps in `apps.tf` are stateless unless they set `data_size`. A stateless app can
set `replicas` above 1; it then gets one replica per node where possible and a
PodDisruptionBudget. An app with `data_size` gets a ReadWriteOnce PVC and always
runs a single replica.

```hcl
whoami = {
  image    = "traefik/whoami:v1.11.0"
  port     = 80
  replicas = 2
}
```

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

OpenTofu creates an OPNsense/Unbound host override pointing each app's
`<name>.home.arpa` at `192.168.1.241`. Clients must use OPNsense for DNS to
resolve them.

Test routing without DNS:

```bash
curl -H 'Host: whoami.home.arpa' http://192.168.1.241/
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
  --resolve whoami.home.arpa:443:192.168.1.241 \
  https://whoami.home.arpa/
```

Headlamp is available at `https://headlamp.home.arpa`. It uses the Kubernetes
`view` role plus an extra role (`headlamp-gateway-readonly`) that adds read access
to Gateway API, storage, networking and other cluster resources, including
Secrets, and permission to delete events. Generate a login token when needed
with:

```bash
kubectl create token headlamp -n headlamp
```

## Alerts

vmalert evaluates the default alert rules from `victoria-metrics-k8s-stack`
against VictoriaMetrics. Alertmanager sends firing and resolved alerts to
Pushover:

- `critical` alerts are sent with high priority.
- `warning` alerts are sent with normal priority, unless the same alert is
  already critical.
- `info` alerts and `InfoInhibitor` are not sent.

`kubernetes/traefik-monitoring.tf` collects Traefik's metrics and adds two
alerts: `TraefikRouteErrorRateHigh` (over 10% of a route's requests returning
5xx for 10 minutes) and `TraefikCertificateNotRenewed` (a served certificate has
under 4 hours left, critical under 1 hour; step-ca certificates last 24 hours
and renew with 8 hours left).

### Dead man's switch

`Watchdog` always fires. Alertmanager sends it to a healthchecks.io check every
minute, so healthchecks.io alerts you if the pings stop because vmalert,
Alertmanager or the cluster is down. Create a check at https://healthchecks.io
with a 5 minute period and 5 minute grace time, add your Pushover integration to
it, and set its ping URL as `TF_VAR_healthchecks_ping_url` in `.env`. If it is
empty, `Watchdog` is dropped.

Create a Pushover application at https://pushover.net/apps/build for the API
token. Set `TF_VAR_pushover_user_key` and `TF_VAR_pushover_api_token` in `.env`.

Send a test alert to Pushover. It resolves on its own a few minutes later:

```bash
scripts/test-alert.sh            # normal priority
scripts/test-alert.sh critical   # high priority
```

List the alerts that are currently firing:

```bash
kubectl port-forward -n observability svc/vmalertmanager-alertmanager 9093
curl -s localhost:9093/api/v2/alerts | jq -r '.[].labels.alertname'
```

## Logs Dashboard

The Grafana dashboard "Service logs" shows container logs from VictoriaLogs.
Pick namespaces and services (container names), and optionally add a LogsQL
filter in Search, such as `timeout` or `"connection refused"`. It shows log lines
and errors per service over time, and the matching log lines.

Dashboards are JSON files in `kubernetes/dashboards/`; each one is loaded into
Grafana through the `homelab-dashboards` ConfigMap.

## Check The Cluster

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get svc -A
kubectl get gateways,httproutes -A
```

A healthy cluster has all nodes `Ready`, Cilium and CSI pods running, PVCs `Bound`, the Traefik Gateway accepted, and Traefik assigned `192.168.1.241`.

## Availability

With two workers, a stateless app with `replicas = 2` keeps serving through pod
restarts, node drains and a worker crash:

- Traefik reloads endpoints within 200ms, so a pod that is shutting down stops
  receiving traffic almost immediately.
- Traefik retries requests that couldn't reach a backend (1s connect timeout,
  3 attempts), so a pod on a crashed node is retried on another pod.
- The controller manager marks a dead node `NotReady` after 20s
  (`node-monitor-grace-period`, set in cloud-init).
- The Traefik Service uses `externalTrafficPolicy: Local`: apps see the real
  client IP, and MetalLB moves `192.168.1.241` to another node if its Traefik
  pod or node goes away. That move takes about 6 seconds.

In a hard-stop test of the worker holding `192.168.1.241`, `whoami` lost 2
requests while the IP moved, then served everything from the other worker.

Single points of failure remain: the Proxmox host, TrueNAS, the single
control-plane node (and its etcd) and step-ca. Apps with persistent data run one
replica and are unavailable until rescheduled.

The current cluster was created before cloud-init set the controller-manager,
scheduler and etcd flags, so they were added to the live static-pod manifests
and the `kubeadm-config` ConfigMap by hand. `kubeadm upgrade diff` should show
no changes; if it does, update `kubeadm-config` before upgrading.

## Common Recovery Commands

Return a node to scheduling after a maintenance test:

```bash
kubectl uncordon k8s-worker1
```

Watch app replicas move between nodes:

```bash
kubectl get pods -n homelab-apps -o wide -w
```
