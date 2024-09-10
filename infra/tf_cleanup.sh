#!/usr/bin/bash
start=$(date +%s)
kubectl delete --all nodeclaim
kubectl delete --all nodepool
kubectl delete --all ec2nodeclass
cluster_arn=$(kubectl config get-clusters | grep "arn:aws:eks:")
kubectl config  delete-cluster "${cluster_arn}"
terraform destroy --auto-approve
end=$(date +%s)
echo Execution time was "$((end - start))" seconds.