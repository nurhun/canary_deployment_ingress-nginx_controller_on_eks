##################### 2-eks #####################

variable "cluster_name" {
  default = "my-eks"
}

variable "cluster_version" {
  default = "1.25"
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "18.29.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

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
      min_size     = 1
      max_size     = 5

      labels = {
        role = "general"
      }

      instance_types = ["t3.small"]
      capacity_type  = "ON_DEMAND"

    }

    spot = {
      desired_size = 1
      min_size     = 1
      max_size     = 5

      labels = {
        role = "spot"
      }

      instance_types = ["t3.micro"]
      capacity_type  = "SPOT"
    }
  }

  # List of additional security group rules to add to the node security group created.
  # Set "source_cluster_security_group = true" inside rules to set the cluster_security_group as source
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
      description = "Node to Node all ports/protocols ingress allowed for the node SG"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }

    egress_self_all = {
      description = "Node to Node all ports/protocols egress allowed for the node SG"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      self        = true
    }

    cluster_to_node = {
      description                   = "Allow access from control plane to nodes to communicate with the ingress controller for webhook admission."
      protocol                      = "tcp"
      from_port                     = 8443
      to_port                       = 8443
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  tags = {
    Environment = "devops-test"
  }

  depends_on = [
    module.vpc
  ]
}


# Enabling EKS CSI driver to enable prometheus PVC to be processed. 
data "aws_iam_policy_document" "csi" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    principals {
      identifiers = [module.eks.oidc_provider_arn]
      type        = "Federated"
    }
  }

  depends_on = [
    module.eks
  ]
}

resource "aws_iam_role" "eks_ebs_csi_driver" {
  assume_role_policy = data.aws_iam_policy_document.csi.json
  name               = "eks-ebs-csi-driver"
}

resource "aws_iam_role_policy_attachment" "amazon_ebs_csi_driver" {
  role       = aws_iam_role.eks_ebs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "csi_driver" {
  cluster_name             = module.eks.cluster_id
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.22.0-eksbuild.1"
  service_account_role_arn = aws_iam_role.eks_ebs_csi_driver.arn
}