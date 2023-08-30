##################### 5-ingress-nginx #####################

# resource "aws_eip" "elastic_ip" {
#   domain = "vpc"

#   depends_on = [
#     module.vpc,
#   ]
# }

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true

  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.7.1"

  atomic = true

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.service.externalTrafficPolicy"
    value = "Local"
  }

  # # Not working, checking with AWS if this feature is supported.
  # set {
  #   name  = "controller.service.loadBalancerIP"
  #   value = aws_eip.elastic_ip.public_ip
  #   type = "string"
  # }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-name"
    value = "apps-ingress"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
    value = "external"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-scheme"
    value = "internet-facing"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-nlb-target-type"
    value = "ip"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-healthcheck-protocol"
    value = "http"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-healthcheck-path"
    value = "/healthz"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-healthcheck-port"
    value = "10254"
  }

  depends_on = [
    helm_release.aws_load_balancer_controller,
    # aws_eip.elastic_ip,
  ]
}

# Get the IP address out of the assigned NLB DNS name record.
data "aws_lb" "ingress_loadbalancer" {
  tags = {
    "elbv2.k8s.aws/cluster" = var.cluster_name
  }
}

module "ingress_loadbalancer_ip" {
  source = "Invicton-Labs/shell-resource/external"

  command_unix = "dig +short ${data.aws_lb.ingress_loadbalancer.dns_name} | awk 'NR==1{print}'"
}

output "ingress_loadbalancer_ip" {
  value = module.ingress_loadbalancer_ip.stdout
}