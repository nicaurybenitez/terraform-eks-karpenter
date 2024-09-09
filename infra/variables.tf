variable "name" {
  description = "Project name"
  type        = string
  default     = "eks-cluster"
}
variable "vpc_cidr" {
  description = "CIDR for the custom VPC"
  type        = string
  default     = "10.0.0.0/16"
}
variable "region" {
  description = "Region to deploy the resources"
  type        = string
  default     = "us-east-1"
}