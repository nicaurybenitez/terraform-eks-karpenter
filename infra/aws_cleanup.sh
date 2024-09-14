#!/bin/bash
#https://repost.aws/knowledge-center/troubleshoot-dependency-error-delete-vpc
# In case, some resources are spared from deleting, and Terraform fails to
# clean up the AWS resources, run the below commands to inspect which resources
# are left and the dependencies, then remove them in order to clean up AWS.
# set the VPC ID you want to clean up in the next line
vpc=""
aws elbv2 describe-load-balancers
#aws elbv2 delete-load-balancer <ALB_ARN_from_above_command>
aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=${vpc}" | grep InternetGatewayId
aws ec2 describe-subnets --filters "Name=vpc-id,Values=${vpc}" | grep SubnetId
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=${vpc}" | grep RouteTableId
aws ec2 describe-network-acls --filters "Name=vpc-id,Values=${vpc}" | grep NetworkAclId
aws ec2 describe-vpc-peering-connections --filters "Name=requester-vpc-info.vpc-id,Values=${vpc}" | grep VpcPeeringConnectionId
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=${vpc}" | grep VpcEndpointId
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=${vpc}" | grep NatGatewayId
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${vpc}" | grep GroupId
aws ec2 describe-instances --filters "Name=vpc-id,Values=${vpc}" | grep InstanceId
aws ec2 describe-vpn-connections --filters "Name=vpc-id,Values=${vpc}" | grep VpnConnectionId
aws ec2 describe-vpn-gateways --filters "Name=attachment.vpc-id,Values=${vpc}" | grep VpnGatewayId
aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=${vpc}" | grep NetworkInterfaceId