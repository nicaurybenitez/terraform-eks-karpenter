variable "admin_users" {
  description = "List of admin users"
  type        = set(string)
  default     = ["admin_1", "admin_3"]
}

module "eks_admins" {
  for_each = toset(var.admin_users)

  source  = "terraform-aws-modules/iam/aws//modules/iam-user"
  version = "5.44.0"

  name                          = each.key
  create_user                   = true
  create_iam_access_key         = false
  create_iam_user_login_profile = true
  force_destroy                 = true

  password_length         = 8
  password_reset_required = false
}

output "iam_user_arns" {
  description = "The user(s) details"
  value       = [for user in module.eks_admins : user.iam_user_arn]
}

module "admin_team" {
  source = "aws-ia/eks-blueprints-teams/aws"

  name = "${var.project_name}-admin-team"

  # Enables elevated, admin privileges for this team
  enable_admin = true
  users        = [for user in module.eks_admins : user.iam_user_arn]
  cluster_arn  = module.eks.cluster_arn

  tags = local.tags

  depends_on = [
    module.eks.cluster_arn,
    module.eks_admins
  ]
}

################################################################################
# K8s Namespace
################################################################################

output "namespaces" {
  description = "Map of Kubernetes namespaces created and their attributes"
  value       = module.admin_team.namespaces
}

################################################################################
# K8s RBAC
################################################################################

output "rbac_group" {
  description = "The name of the Kubernetes RBAC group"
  value       = module.admin_team.rbac_group
}

output "aws_auth_configmap_role" {
  description = "Dictionary containing the necessary details for adding the role created to the `aws-auth` configmap"
  value       = module.admin_team.aws_auth_configmap_role
}

################################################################################
# IAM Role
################################################################################

output "iam_role_name" {
  description = "The name of the IAM role"
  value       = module.admin_team.iam_role_name
}

output "iam_role_arn" {
  description = "The Amazon Resource Name (ARN) specifying the IAM role"
  value       = module.admin_team.iam_role_arn
}

output "iam_role_unique_id" {
  description = "Stable and unique string identifying the IAM role"
  value       = module.admin_team.iam_role_unique_id
}