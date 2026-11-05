# One-off hand-over to Argo CD. These were managed by OpenTofu before Argo CD
# took them over; `destroy = false` makes OpenTofu forget them without
# deleting anything, so Argo CD adopts the running resources in place. Delete
# this file once it has been applied.

removed {
  from = helm_release.metallb
  lifecycle {
    destroy = false
  }
}

removed {
  from = helm_release.metallb_config
  lifecycle {
    destroy = false
  }
}

removed {
  from = helm_release.metrics_server
  lifecycle {
    destroy = false
  }
}

removed {
  from = helm_release.snapshot_controller
  lifecycle {
    destroy = false
  }
}

removed {
  from = helm_release.truenas_csi
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_storage_class_v1.truenas_nvmeof
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_namespace_v1.headlamp
  lifecycle {
    destroy = false
  }
}

removed {
  from = helm_release.headlamp
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubectl_manifest.headlamp_gateway_readonly
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubectl_manifest.headlamp_gateway_readonly_binding
  lifecycle {
    destroy = false
  }
}

removed {
  from = helm_release.victoria_metrics_k8s_stack
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_config_map_v1.grafana_dashboards
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubectl_manifest.cert_manager_service_scrape
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubectl_manifest.cert_manager_rules
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubectl_manifest.traefik_pod_scrape
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubectl_manifest.traefik_rules
  lifecycle {
    destroy = false
  }
}

removed {
  from = module.apps
  lifecycle {
    destroy = false
  }
}

removed {
  from = helm_release.traefik
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_namespace_v1.traefik
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubectl_manifest.gateway_api_crds
  lifecycle {
    destroy = false
  }
}

removed {
  from = helm_release.cert_manager
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_namespace_v1.step_ca
  lifecycle {
    destroy = false
  }
}

removed {
  from = helm_release.step_ca
  lifecycle {
    destroy = false
  }
}

removed {
  from = helm_release.step_issuer
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubectl_manifest.step_cluster_issuer
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubectl_manifest.certificates
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubectl_manifest.http_routes
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubectl_manifest.basic_auth
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_service_v1.external_services
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_endpoint_slice_v1.external_services
  lifecycle {
    destroy = false
  }
}
