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

  depends_on = [
    helm_release.ingress_nginx,
  ]
}