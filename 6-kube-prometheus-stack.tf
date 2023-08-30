##################### 6-kube-prometheus-stack #####################

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  namespace        = "prometheus"
  create_namespace = true

  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "49.2.0"

  atomic = true

  set {
    name  = "prometheus.prometheusSpec.ruleNamespaceSelector.matchLabels.prometheus"
    value = "true"
    type  = "string"
  }

  set {
    name  = "prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues"
    value = false
  }

  set {
    name  = "prometheus.prometheusSpec.podMonitorNamespaceSelector.matchLabels.prometheus"
    value = "true"
    type  = "string"
  }

  set {
    name  = "prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues"
    value = false
  }

  set {
    name  = "prometheus.prometheusSpec.serviceMonitorNamespaceSelector.matchLabels.prometheus"
    value = "true"
    type  = "string"
  }

  set {
    name  = "prometheus.prometheusSpec.probeNamespaceSelector.matchLabels.prometheus"
    value = "true"
    type  = "string"
  }

  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "7d"
  }

  set {
    name  = "prometheus.prometheusSpec.scrapeInterval"
    value = "15s"
  }

  set {
    name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.accessModes[0]"
    value = "ReadWriteOnce"
  }

  set {
    name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage"
    value = "20Gi"
  }


  # Grafana dashboard
  set {
    name  = "grafana.dashboardProviders.dashboardproviders.yaml.providers[0].name"
    value = "default"
  }

  set {
    name  = "grafana.dashboardProviders.dashboardproviders.yaml.providers[0].orgId"
    value = "1"
  }

  set {
    name  = "grafana.dashboardProviders.dashboardproviders.yaml.providers[0].type"
    value = "file"
  }
  set {
    name  = "grafana.dashboardProviders.dashboardproviders.yaml.providers[0].disableDeletion"
    value = false
  }

  set {
    name  = "grafana.dashboardProviders.dashboardproviders.yaml.providers[0].editable"
    value = true
  }

  set {
    name  = "grafana.dashboardProviders.dashboardproviders.yaml.providers[0].options.path"
    value = "/var/lib/grafana/dashboards/default"
  }
  
  set {
    name  = "grafana.dashboardsConfigMaps.default"
    value = "app-nginx-http-request-total"
  }

  depends_on = [
    kubectl_manifest.grafana_dashboard,
  ]
}