##################### 3-autoscaler #####################

module "cluster_autoscaler_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.3.1"

  role_name                        = "cluster-autoscaler"
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_ids   = [module.eks.cluster_id]

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:cluster-autoscaler"]
    }
  }
}

# Allow eks_managed_node_groups created by eks access on autoscaling resources.
resource "aws_iam_role_policy_attachment" "node-groups-autoscaling" {
  for_each = module.eks.eks_managed_node_groups

  policy_arn = "arn:aws:iam::aws:policy/AutoScalingFullAccess"
  role       = each.value.iam_role_name
}


resource "helm_release" "cluster_autoscalerr" {
  name      = "cluster-autoscaler"
  namespace = "kube-system"

  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = "9.29.2"

  set {
    name  = "autoDiscovery.clusterName"
    value = module.eks.cluster_id
  }

  set {
    name  = "awsRegion"
    value = var.region
  }

  set {
    name  = "serviceAccount.name"
    value = module.cluster_autoscaler_irsa_role.iam_role_name
  }

  depends_on = [
    module.eks,
  ]
}