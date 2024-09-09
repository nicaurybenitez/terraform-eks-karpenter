output "vpc" {
  description = "VPC name that the EKS cluster is using"
  value       = module.vpc.name
}
output "azs" {
  description = "VPC availability zones"
  value       = module.vpc.azs
}
output "public_subnets" {
  description = "VPC public subnets"
  value       = module.vpc.public_subnets
}
output "private_subnets" {
  description = "VPC private subnets"
  value       = module.vpc.private_subnets
}
output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${var.deploy_region} update-kubeconfig --name ${module.eks.cluster_name}"
}
output "cluster_name" {
  description = "Cluster name of the EKS cluster"
  value       = module.eks.cluster_name
}
output "vpc_id" {
  description = "VPC ID that the EKS cluster is using"
  value       = module.vpc.vpc_id
}

output "node_instance_role_name" {
  description = "IAM Role name that each Karpenter node will use"
  value       = module.eks_blueprints_addons.karpenter.node_iam_role_name
}