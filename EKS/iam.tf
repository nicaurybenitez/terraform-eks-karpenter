terraform {
  required_version = ">= 1.0.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
provider "aws" {
  region = "us-east-2"
  alias  = "ohio"
}

variable "admin_users" {
  description = "List of admin users"
  type        = set(string)
  default     = ["admin_1", "admin_3"]
}

module "eks_admin" {
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



output "iam_user_names" {
  description = "The user(s) details"
  value       = module.eks_admin
}