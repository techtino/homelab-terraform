# Homelab infrastructure

```mermaid
flowchart TB
  subgraph Physical["Proxmox host"]
    PVE["Proxmox VE"]
    subgraph VMs["Kubernetes VMs"]
      CP["k8s-control<br/>Control plane"]
      W1["k8s-worker1<br/>Worker"]
      W2["k8s-worker2<br/>Worker"]
    end
    PVE --> CP
    PVE --> W1
    PVE --> W2
  end

  subgraph LAN["Home LAN"]
    Client["Browser / client"]
    DNS["OPNsense Unbound<br/>app.home.arpa → 192.168.1.241"]
    MetalLB["MetalLB L2<br/>192.168.1.240–250 pool"]
    NAS["TrueNAS<br/>NVMe-oF storage"]
  end

  Client -->|"DNS lookup"| DNS
  DNS -->|"returns 192.168.1.241"| Client
  Client -->|"HTTP :80 redirects to HTTPS :443"| LB

  subgraph K8s["Kubernetes cluster · Cilium CNI and kube-proxy replacement"]
    subgraph Edge["Ingress edge · traefik namespace"]
      LB["Traefik Service<br/>LoadBalancer 192.168.1.241<br/>2 replicas"]
      GW["Traefik Gateway<br/>HTTP :8000 · HTTPS :8443"]
      Routes["HTTPRoutes<br/>hostname and path routing"]
      LB --> GW --> Routes
    end

    subgraph TLS["TLS issuance"]
      CM["cert-manager"]
      Certs["Certificate per app<br/>Secrets in traefik namespace"]
      Issuer["StepClusterIssuer<br/>step-issuer"]
      StepCA["step-ca<br/>private CA"]
      CM --> Certs --> Issuer --> StepCA
      Certs -. "Gateway listener certificateRefs" .-> GW
    end

    subgraph AppNS["homelab-apps namespace · app module"]
      Who["whoami Service → Pod"]
      Test["test Service :8000 → Pod"]
      WhoPVC[("whoami PVC")]
      TestPVC[("test PVC")]
      Who --- WhoPVC
      Test --- TestPVC
    end

    subgraph HeadlampNS["headlamp namespace"]
      Head["Headlamp Service → Pod"]
    end

    subgraph Obs["observability namespace"]
      Grafana["Grafana Service → Pod"]
      VMA["vmagent<br/>scrapes cluster metrics"]
      VM["VictoriaMetrics<br/>100 Gi PVC"]
      VLA["vlagent<br/>collects Kubernetes logs"]
      VL["VictoriaLogs<br/>100 Gi PVC"]
      Dash["Dashboard ConfigMaps<br/>loaded by Grafana sidecar"]
      Grafana -->|"metrics queries"| VM
      Grafana -->|"log queries"| VL
      Dash --> Grafana
      VMA -->|"remote write"| VM
      VLA -->|"remote write"| VL
    end

    Metrics["Kubernetes metrics targets<br/>node exporter, kube-state-metrics,<br/>control-plane endpoints"]
    PodLogs["Container and Kubernetes logs"]
    Metrics --> VMA
    PodLogs --> VLA

    Routes -->|"whoami.home.arpa"| Who
    Routes -->|"test.home.arpa"| Test
    Routes -->|"headlamp.home.arpa"| Head
    Routes -->|"grafana.home.arpa"| Grafana
  end

  MetalLB -. "advertises LoadBalancer IP" .-> LB
  W1 --- NAS
  W2 --- NAS
  CP --- NAS
  NAS -. "CSI NVMe-oF PVC volumes" .-> WhoPVC
  NAS -.-> TestPVC
  NAS -.-> VM
  NAS -.-> VL

  Trust["Install step-ca root certificate<br/>in client trust store"]
  StepCA -. "root CA certificate" .-> Trust
  Trust -. "trusts app certificates" .-> Client
```

## Request and data paths

- Clients resolve each `*.home.arpa` app name through OPNsense to the Traefik LoadBalancer IP.
- Traefik redirects HTTP to HTTPS. The Gateway selects a certificate and HTTPRoute, then sends traffic to the app Service.
- cert-manager requests an individual certificate through the StepClusterIssuer and step-ca. The resulting Secrets are referenced by the Traefik Gateway listener.
- vmagent scrapes cluster metrics and writes them to VictoriaMetrics; vlagent collects Kubernetes logs and writes them to VictoriaLogs. Grafana queries both stores and loads dashboards from ConfigMaps.
- Proxmox runs one control-plane VM and two worker VMs. Cilium provides cluster networking and replaces kube-proxy. TrueNAS supplies persistent volumes through its NVMe-oF CSI driver.
