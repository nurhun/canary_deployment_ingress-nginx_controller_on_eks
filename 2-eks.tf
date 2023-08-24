variable "cluster_name" {
  default = "my-eks"
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "18.29.0"

  cluster_name    = "my-eks"
  cluster_version = "1.25"

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  # Determines whether to create an OpenID Connect Provider for EKS to enable IAM roles for service accounts (IRSA).	
  enable_irsa = true

  eks_managed_node_group_defaults = {
    disk_size = 50
  }

  eks_managed_node_groups = {
    general = {
      desired_size = 2
      min_size     = 2
      max_size     = 2

      labels = {
        role = "general"
      }

      instance_types = ["t3.small"]
      capacity_type  = "ON_DEMAND"

    }

    # spot = {
    #   desired_size = 1
    #   min_size     = 1
    #   max_size     = 5

    #   labels = {
    #     role = "spot"
    #   }

    #   #   taints = [{
    #   #     key    = "market"
    #   #     value  = "spot"
    #   #     effect = "NO_SCHEDULE"
    #   #   }]

    #   instance_types = ["t3.micro"]
    #   capacity_type  = "SPOT"
    # }
  }

  #   # Fargate Profile(s)
  #   fargate_profiles = {
  #     default = {
  #       name = "default"
  #       selectors = [
  #         {
  #           namespace = "kube-system"
  #           labels = {
  #             k8s-app = "kube-dns"
  #           }
  #         },
  #         {
  #           namespace = "default"
  #         }
  #       ]

  #       tags = {
  #         Owner = "test"
  #       }

  #       timeouts = {
  #         create = "20m"
  #         delete = "20m"
  #       }
  #     }
  #   }


  #   # aws-auth configmap
  #   manage_aws_auth_configmap = true

  #   aws_auth_roles = [
  #     {
  #       rolearn  = "arn:aws:iam::111122223333:role/eks-admin"
  #       username = "eks-admin"
  #       groups   = ["system:masters"]
  #     },
  #   ]

  #   aws_auth_users = [
  #     {
  #       userarn  = "arn:aws:iam::426363595269:user/admin"
  #       username = "admin"
  #       groups   = ["system:masters"]
  #     },
  #     {
  #       userarn  = "arn:aws:iam::66666666666:user/user2"
  #       username = "user2"
  #       groups   = ["system:masters"]
  #     },
  #   ]

  #   aws_auth_accounts = [
  #     "777777777777",
  #     "888888888888",
  #   ]

  # Allow access from the EKS control plane to the webhook port of the AWS loadbalancer controller.
  node_security_group_additional_rules = {
    ingress_allow_access_from_control_plane = {
      type                          = "ingress"
      protocol                      = "tcp"
      from_port                     = 9443
      to_port                       = 9443
      source_cluster_security_group = true
      description                   = "Allow access from control plane to webhook port of AWS load balancer controller"
    }

    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }

    egress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      self        = true
    }

    # EKS node shared security group -- my-eks-node-xxxxxxx

    # By default EKS compute mode group, will have the default cluster Security Group attached which is created by AWS.
    # Even if you provide additional security group to EKS cluster during the creation, that additional security group will not be attached to compute instances.
    # So, to get this working, you have to use Launch Templates.

  }

  tags = {
    Environment = "devops-test"
  }
}


# You need to authorize terraform to access Kubernetes API and modify aws-auth configmap. To do that, you need to define terraform kubernetes provider.

# https://github.com/terraform-aws-modules/terraform-aws-eks/issues/2009
data "aws_eks_cluster" "default" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "default" {
  name = module.eks.cluster_id
}
provider "kubernetes" {
  host                   = data.aws_eks_cluster.default.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.default.certificate_authority[0].data)
  # token                  = data.aws_eks_cluster_auth.default.token

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.default.id]
    command     = "aws"
  }
}

output "eks_managed_node_groups" {
  description = "Map of attribute maps for all EKS managed node groups created"
  value       = module.eks.eks_managed_node_groups
}

output "eks_managed_node_groups_arns" {
  description = "Map of attribute maps for all EKS managed node groups created"
  value = [for group_key, group_value in module.eks.eks_managed_node_groups :
  group_value.iam_role_arn]
}