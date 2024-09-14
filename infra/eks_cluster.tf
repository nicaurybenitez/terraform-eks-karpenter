## THIS TO AUTHENTICATE TO ECR, DON'T CHANGE IT
## IF DEFAULT REGION IS ``, NO NEED TO SET ALIAS FOR THIS
## IT IS ONLY USED FOR KARPENTER INSTALLATION
provider "aws" {
  region = "us-east-1"
  alias  = "virginia"
}

provider "aws" {
  region = var.deploy_region
  alias  = "ohio"
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubectl" {
  apply_retry_count      = 10
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false
  token                  = data.aws_eks_cluster_auth.this.token
}

###############################################################################
# EKS Cluster
###############################################################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.24.0"

  cluster_name                   = var.project_name
  cluster_version                = var.eks_cluster_version
  cluster_endpoint_public_access = true

  cluster_addons = {
    kube-proxy = { most_recent = true }
    coredns    = { most_recent = true }

    vpc-cni = {
      most_recent    = true
      before_compute = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  create_cloudwatch_log_group              = false
  create_cluster_security_group            = false
  create_node_security_group               = false
  authentication_mode                      = "API_AND_CONFIG_MAP"
  enable_cluster_creator_admin_permissions = true

  node_security_group_additional_rules = {
    ingress_allow_access_from_control_plane = {
      type                          = "ingress"
      protocol                      = "tcp"
      from_port                     = 9443
      to_port                       = 9443
      source_cluster_security_group = true
      description                   = "Allow access from control plane to webhook port of AWS load balancer controller"
    }
  }

  eks_managed_node_groups = {
    managed_nodes = {
      node_group_name       = var.node_group_name
      instance_types        = var.eks_managed_nodes_instance_types
      capacity_type         = var.eks_managed_nodes_capacity_type
      create_security_group = false

      subnet_ids   = module.vpc.private_subnets
      max_size     = 2
      desired_size = 1
      min_size     = 1

      # Launch template configuration
      create_launch_template = true # false will use the default launch template

      labels = {
        intent = "control-apps"
      }
    }
  }

  tags = merge(local.tags, {
    "karpenter.sh/discovery" = var.project_name
  })

  depends_on = [
    module.vpc.vpc_id
  ]
}

## BELOW IS A SUBMODULE FROM terraform-aws-modules/iam/aws/
module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.44.0"

  role_name = "${module.eks.cluster_name}-ebs-csi-controller-sa"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags

  depends_on = [
    module.eks.cluster_id
  ]
}

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "1.16.3"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  create_delay_dependencies = [for prof in module.eks.eks_managed_node_groups : prof.node_group_arn]

  # enable and configure ALB for load balancing
  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    set = [
      {
        name  = "vpcId"
        value = module.vpc.vpc_id
      },
      {
        name  = "image.tag"
        value = var.aws_load_balancer_controller_image_tag
      },
      {
        name  = "serviceAccount.name"
        value = var.aws_alb_controller_name
      },
      {
        name  = "podDisruptionBudget.maxUnavailable"
        value = 1
      },
      {
        name  = "enableServiceMutatorWebhook"
        value = "false"
      }
    ]
  }

  enable_metrics_server = true

  eks_addons = {
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
  }

  enable_aws_for_fluentbit = true
  aws_for_fluentbit = {
    set = [
      {
        name  = "cloudWatchLogs.region"
        value = var.deploy_region
      }
    ]
  }

  # Enable Karpenter for node autoscaling
  enable_karpenter = true
  karpenter = {
    chart_version       = var.karpenter_chart_version
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
    timeouts = {
      create = "15m"
      delete = "15m"
    }
  }
  karpenter_enable_spot_termination          = true
  karpenter_enable_instance_profile_creation = true
  karpenter_node = {
    iam_role_use_name_prefix = false
  }

#   # Enable Prometheus and Grafana, not working properly
#   enable_kube_prometheus_stack = true
#   kube_prometheus_stack = {
#     name          = "monitoring"
#     chart         = "kube-prometheus-stack"
#     chart_version = "62.6.0"
#     repository    = "https://prometheus-community.github.io/helm-charts"
#     namespace     = "monitoring"
#   }

  # https://github.com/aws-ia/terraform-aws-eks-blueprints-addons/blob/main/docs/helm-release.md
  helm_releases = {
    prometheus-adapter = {
      description      = "A Helm chart for k8s prometheus"
      namespace        = "monitoring"
      create_namespace = true
      chart            = "kube-prometheus-stack"
      chart_version    = "62.6.0"
      repository       = "https://prometheus-community.github.io/helm-charts"
    }
#     gpu-operator = {
#       description      = "A Helm chart for NVIDIA GPU operator"
#       namespace        = "gpu-operator"
#       create_namespace = true
#       chart            = "gpu-operator"
#       chart_version    = "v23.3.2"
#       repository       = "https://nvidia.github.io/gpu-operator"
#       values = [
#         <<-EOT
#           operator:
#             defaultRuntime: containerd
#         EOT
#       ]
#     }
  }

  tags = local.tags

  depends_on = [
    module.eks.cluster_id
  ]
}

module "aws-auth" {
  source  = "terraform-aws-modules/eks/aws//modules/aws-auth"
  version = ">= 20.24"

  manage_aws_auth_configmap = true

  aws_auth_roles = [
    {
      rolearn  = module.eks_blueprints_addons.karpenter.node_iam_role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups   = ["system:bootstrappers", "system:nodes"]
    },
  ]

  depends_on = [
    module.eks.cluster_id
  ]
}

##############################################################################################
# Karpenter settings
# https://github.com/aws-samples/karpenter-blueprints/blob/main/cluster/terraform/karpenter.tf
##############################################################################################
resource "kubectl_manifest" "karpenter_default_ec2_node_class" {
  yaml_body = <<-YAML
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  role: "${local.node_iam_role_name}"
  amiSelectorTerms:
  - alias: al2@latest
  securityGroupSelectorTerms:
  - tags:
      karpenter.sh/discovery: ${var.project_name}
  subnetSelectorTerms:
  - tags:
      karpenter.sh/discovery: ${var.project_name}
  tags:
    IntentLabel: apps
    KarpenterNodePoolName: default
    NodeType: default
    intent: apps
    karpenter.sh/discovery: ${var.project_name}
    project: karpenter-blueprints
YAML

  depends_on = [
    module.eks.cluster_id,
    module.eks_blueprints_addons.karpenter,
  ]
}

resource "kubectl_manifest" "karpenter_default_node_pool" {
  yaml_body = <<-YAML
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    metadata:
      labels:
        intent: apps
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64", "arm64"]
        - key: "karpenter.k8s.aws/instance-cpu"
          operator: In
          values: ["2", "4"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "t"]
      nodeClassRef:
        name: default
        group: karpenter.k8s.aws
        kind: EC2NodeClass
      kubelet:
        containerRuntime: containerd
        systemReserved:
          cpu: 100m
          memory: 100Mi
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m

YAML

  depends_on = [
    module.eks.cluster_id,
    module.eks_blueprints_addons.karpenter,
    kubectl_manifest.karpenter_default_ec2_node_class,
  ]
}