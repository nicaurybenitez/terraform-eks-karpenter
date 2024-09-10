variable "project_name" {
  description = "Project name that the EKS cluster will use"
  type        = string
  default     = "eks-cluster"
}
variable "eks_cluster_version" {
  description = "Kubernetes `<major>.<minor>` version to use for the EKS cluster (i.e.: `1.27`)"
  type        = string
  default     = "1.30"
}
variable "node_group_name" {
  description = "Kubernetes node group name"
  type        = string
  default     = "managed-ondemand"
}
variable "vpc_cidr" {
  description = "CIDR for the VPC that the EKS cluster will use"
  type        = string
  default     = "10.0.0.0/16"
}

variable "deploy_region" {
  description = "The AWS region to deploy into (e.g. us-east-1)"
  type        = string
  default     = "us-east-2"
}

variable "aws_alb_controller_name" {
  description = "AWS ALB controller name"
  type        = string
  default     = "aws-load-balancer-controller"
}