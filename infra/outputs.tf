output "vpc" {
  description = "Name of the VPC"
  value = module.vpc.name
}
output "vpc_id" {
  description = "ID of the VPC"
  value = module.vpc.vpc_id
}
output "azs" {
  description = "VPC availability zones"
  value = module.vpc.azs
}
output "public_subnets" {
  description = "VPC public subnets"
  value = module.vpc.public_subnets
}
output "private_subnets" {
  description = "VPC private subnets"
  value = module.vpc.private_subnets
}