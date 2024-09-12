# terraform-eks-karpenter

Step-by-step guide to set and use AWS EKS with Karpenter by Terraform.

## Steps

Install below tools before starting

- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [eksctl](https://eksctl.io/installation/) [Use [this script](./eksctl_install.sh) to install on Ubuntu]
- [Helm](https://helm.sh/docs/intro/install/) (the package manager for Kubernetes)

Configure your AWS profile with appropriate credentials with `Admin` access.
Set the aws profile in your CLI, i.e.

```
$ export AWS_DEFAULT_PROFILE=<your_aws_profile_name>
```

Clone this repository to your local machine

```
$ git clone https://github.com/ahmadalsajid/terraform-eks-karpenter.git
```

Change directory to [infra](./infra) and update the
[variables.tf](./infra/variables.tf) and [local.tf](./infra/local.tf)
accordingly. Check the plan and initiate apply to create the VPC, and the EKS
cluster, along with Karpenter to scale the node pool.

Before you continue, you need to enable your AWS account to launch Spot
instances if you haven't launched any yet. To do so, create the
[service-linked role for Spot](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-requests.html#service-linked-roles-spot-instance-requests)
by running the following command:

```
$ aws iam create-service-linked-role --aws-service-name spot.amazonaws.com || true
```

You might see the following error if the role has already been successfully
created. You don't need to worry about this error, you simply had to run the
above command to make sure you have the service-linked role to launch Spot
instances:

```
An error occurred (InvalidInput) when calling the CreateServiceLinkedRole operation: Service role name AWSServiceRoleForEC2Spot has been taken in this account, please try a different suffix.
```

To create the cluster, run the following commands:

```
$ terraform init
$ terraform plan
$ terraform apply --auto-approve
```

Or, if you want to create the cluster module by module to have a better
understanding, remove `depends_on` from
[eks_cluster.tf](./infra/eks_cluster.tf) file and run the following commands:

```
$ terraform init
$ terraform plan

$ terraform apply -target="module.vpc" -auto-approve
$ terraform apply -target="module.eks" -auto-approve
$ terraform apply --auto-approve
```

Check the AWS console for the newly created VPC **[VPC ID from the Terraform
output]**

```
$ aws ec2 describe-vpcs --vpc-ids "vpc-0ae0071a560b7a269" --region=us-east-2
{
    "Vpcs": [
        {
            "CidrBlock": "10.0.0.0/16",
            "DhcpOptionsId": "dopt-0b0d0955f7a6e6f89",
            "State": "available",
            "VpcId": "vpc-0ae0071a560b7a269",
            "OwnerId": "53xxxxxxxx44",
            "InstanceTenancy": "default",
            "CidrBlockAssociationSet": [
                {
                    "AssociationId": "vpc-cidr-assoc-0f08fa04c7809dbe6",
                    "CidrBlock": "10.0.0.0/16",
                    "CidrBlockState": {
                        "State": "associated"
                    }
                }
            ],
            "IsDefault": false,
            "Tags": [
                {
                    "Key": "blueprint",
                    "Value": "eks-cluster"
                },
                {
                    "Key": "Name",
                    "Value": "eks-cluster"
                }
            ]
        }
    ]
}    
```

Once completed (**after waiting about 15 minutes**), run the following command
to update the kube.config file to interact with the cluster through kubectl:

```
$ aws eks --region $AWS_REGION update-kubeconfig --name $CLUSTER_NAME
```

Then, check the EKS cluster, i.e.

```
$ eksctl get cluster --name=eks-cluster --region=us-east-2
NAME            VERSION STATUS  CREATED                 VPC                     SUBNETS                                                                         SECURITYGROUPS  PROVIDER
eks-cluster     1.30    ACTIVE  2024-09-10T14:19:44Z    vpc-0ae0071a560b7a269   subnet-022e5f6ce1670fe14,subnet-02e1475b6290fcba6,subnet-0c62df535bc954c1f                      EKS
```

You need to make sure you can interact with the cluster and that the `Karpenter`
pods are running, i.e.:

```
$ kubectl get pods -n karpenter
NAME                        READY   STATUS    RESTARTS   AGE
karpenter-c5447bdf5-7kp6j   1/1     Running   0          19m
karpenter-c5447bdf5-qc7lf   1/1     Running   0          19m
```

List the nodes available after creating the cluster.

```
$ kubectl get nodes          
NAME                                        STATUS   ROLES    AGE   VERSION
ip-10-0-101-90.us-east-2.compute.internal   Ready    <none>   35m   v1.30.2-eks-1552ad0 
```

Now, move to [EKS](./EKS) directory and deploy `Nginx` with
[nginx-deployment.yml](./EKS/nginx-deployment.yml) file.

```
$ kubectl apply -f nginx-deployment.yml 
deployment.apps/nginx-deployment created
$ kubectl get pods                      
NAME                               READY   STATUS    RESTARTS   AGE
nginx-deployment-576c6b7b6-6blkw   1/1     Running   0          22s
nginx-deployment-576c6b7b6-7nnd7   1/1     Running   0          22s
nginx-deployment-576c6b7b6-b4f8p   1/1     Running   0          22s
```

There are `3` pods running, as mentioned in the `YAML` file.

Change it to `30` in the [nginx-deployment.yml](./EKS/nginx-deployment.yml)
file, and apply again.

```
$ kubectl apply -f nginx-deployment.yml
deployment.apps/nginx-deployment configured
$ kubectl get pods --output name | wc -l
30
```

We still have `1` worker node, as it is sufficient to accommodate all the `30` pods.

```
$ kubectl get nodes                     
NAME                                        STATUS   ROLES    AGE   VERSION
ip-10-0-101-90.us-east-2.compute.internal   Ready    <none>   48m   v1.30.2-eks-1552ad0 
```

We want to see `Karpenter` in action, right? To achieve that, increase the
replica from `30` to `150`, and apply the change. Wait for a couple of minutes,
and check for the nodes again.

```
$ kubectl apply -f nginx-deployment.yml 
deployment.apps/nginx-deployment configured
$ kubectl get pods --output name | wc -l
150
$ kubectl get nodes 
NAME                                        STATUS   ROLES    AGE   VERSION
ip-10-0-101-90.us-east-2.compute.internal   Ready    <none>   51m   v1.30.2-eks-1552ad0
ip-10-0-55-209.us-east-2.compute.internal   Ready    <none>   24s   v1.30.2-eks-1552ad0
```

YES!! Now we have `2` worker nodes, and `150` pods deployed. `Karpenter` scaled
out based on the settings and needs of the resources to accommodate the
desired pod counts.

Now, set the replica count to `3` again, and check for the results.

```
$ kubectl apply -f nginx-deployment.yml
deployment.apps/nginx-deployment configured
$ kubectl get pods --output name | wc -l
3
$ kubectl get nodes                                                             
NAME                                        STATUS   ROLES    AGE   VERSION
ip-10-0-101-90.us-east-2.compute.internal   Ready    <none>   60m   v1.30.2-eks-1552ad0
```

Also, you can check the `Karpenter` logs to have a better understanding.

```
$kubectl logs -f -n karpenter -l app.kubernetes.io/name=karpenter -c controller
 {"level":"INFO","time":"2024-09-10T14:45:22.231Z","logger":"controller","message":"discovered ssm parameter","commit":"62a726c","controller":"nodeclass.status","controllerGroup":"karpenter.k8s.aws","controllerKind":"EC2NodeClass
","EC2NodeClass":{"name":"default"},"namespace":"","name":"default","reconcileID":"bd9523a7-6456-4de3-9b32-3f9293425866","parameter":"/aws/service/eks/optimized-ami/1.30/amazon-linux-2-gpu/recommended/image_id","value":"ami-033b66e831e2c5f86"}
{"level":"ERROR","time":"2024-09-10T14:45:23.152Z","logger":"controller","message":"failed listing instance types for default","commit":"62a726c","controller":"disruption","namespace":"","name":"","reconcileID":"4bfd4c2f-61f3-4cc9-829d-930350fd859d","error":"no subnets found"}
{"level":"INFO","time":"2024-09-10T15:21:13.076Z","logger":"controller","message":"found provisionable pod(s)","commit":"62a726c","controller":"provisioner","namespace":"","name":"","reconcileID":"2033d0c2-e63a-4176-8b47-99d331d
df61f","Pods":"default/nginx-deployment-576c6b7b6-c4c2d, default/nginx-deployment-576c6b7b6-xhl9m, default/nginx-deployment-576c6b7b6-trkf4, default/nginx-deployment-576c6b7b6-gnb75, default/nginx-deployment-576c6b7b6-j2qwx and 47 other(s)","duration":"229.528995ms"}
{"level":"INFO","time":"2024-09-10T15:21:13.076Z","logger":"controller","message":"computed new nodeclaim(s) to fit pod(s)","commit":"62a726c","controller":"provisioner","namespace":"","name":"","reconcileID":"2033d0c2-e63a-4176-8b47-99d331ddf61f","nodeclaims":1,"pods":52}
{"level":"INFO","time":"2024-09-10T15:21:13.098Z","logger":"controller","message":"created nodeclaim","commit":"62a726c","controller":"provisioner","namespace":"","name":"","reconcileID":"2033d0c2-e63a-4176-8b47-99d331ddf61f","NodePool":{"name":"default"},"NodeClaim":{"name":"default-wgbwq"},"requests":{"cpu":"260m","memory":"290Mi","pods":"57"},"instance-types":"c4.xlarge, c5.xlarge, c5a.xlarge, c5ad.xlarge, c5d.xlarge and 17 other(s)"}
{"level":"INFO","time":"2024-09-10T15:21:15.752Z","logger":"controller","message":"launched nodeclaim","commit":"62a726c","controller":"nodeclaim.lifecycle","controllerGroup":"karpenter.sh","controllerKind":"NodeClaim","NodeClai
m":{"name":"default-wgbwq"},"namespace":"","name":"default-wgbwq","reconcileID":"509fbe1c-f406-471f-bf82-71b96f0a0245","provider-id":"aws:///us-east-2a/i-0f4fe866297af566d","instance-type":"t4g.xlarge","zone":"us-east-2a","capacity-type":"spot","allocatable":{"cpu":"3920m","ephemeral-storage":"17Gi","memory":"14103Mi","pods":"58"}}
{"level":"INFO","time":"2024-09-10T15:21:41.702Z","logger":"controller","message":"registered nodeclaim","commit":"62a726c","controller":"nodeclaim.lifecycle","controllerGroup":"karpenter.sh","controllerKind":"NodeClaim","NodeClaim":{"name":"default-wgbwq"},"namespace":"","name":"default-wgbwq","reconcileID":"31fab340-d7d4-4d84-9664-d6efe47eebf0","provider-id":"aws:///us-east-2a/i-0f4fe866297af566d","Node":{"name":"ip-10-0-55-209.us-east-2.compute.internal"}}
{"level":"INFO","time":"2024-09-10T15:21:54.762Z","logger":"controller","message":"initialized nodeclaim","commit":"62a726c","controller":"nodeclaim.lifecycle","controllerGroup":"karpenter.sh","controllerKind":"NodeClaim","NodeClaim":{"name":"default-wgbwq"},"namespace":"","name":"default-wgbwq","reconcileID":"6914e0ef-f121-4163-b757-cc87c84f3218","provider-id":"aws:///us-east-2a/i-0f4fe866297af566d","Node":{"name":"ip-10-0-55-209.us-east-2.compute.internal"},"allocatable":{"cpu":"3920m","ephemeral-storage":"18233774458","hugepages-1Gi":"0","hugepages-2Mi":"0","hugepages-32Mi":"0","hugepages-64Ki":"0","memory":"15136204Ki","pods":"58"}}
{"level":"INFO","time":"2024-09-10T15:28:12.725Z","logger":"controller","message":"disrupting nodeclaim(s) via delete, terminating 1 nodes (3 pods) ip-10-0-55-209.us-east-2.compute.internal/t4g.xlarge/spot","commit":"62a726c","controller":"disruption","namespace":"","name":"","reconcileID":"f167a15a-0515-479f-b9e1-5ecb273c3697","command-id":"5c4c0606-c72a-4602-860f-feb31101a5c5","reason":"underutilized"}
{"level":"INFO","time":"2024-09-10T15:28:13.262Z","logger":"controller","message":"tainted node","commit":"62a726c","controller":"node.termination","controllerGroup":"","controllerKind":"Node","Node":{"name":"ip-10-0-55-209.us-east-2.compute.internal"},"namespace":"","name":"ip-10-0-55-209.us-east-2.compute.internal","reconcileID":"b36e33e1-3deb-44b8-9ac6-6eaa2c10267c","taint.Key":"karpenter.sh/disrupted","taint.Value":"","taint.Effect":"NoSchedule"}  
{"level":"INFO","time":"2024-09-10T15:29:12.708Z","logger":"controller","message":"deleted node","commit":"62a726c","controller":"node.termination","controllerGroup":"","controllerKind":"Node","Node":{"name":"ip-10-0-55-209.us-east-2.compute.internal"},"namespace":"","name":"ip-10-0-55-209.us-east-2.compute.internal","reconcileID":"ccd91aa6-4fed-48f5-97fd-d117d8a989cd"}
{"level":"INFO","time":"2024-09-10T15:29:12.953Z","logger":"controller","message":"deleted nodeclaim","commit":"62a726c","controller":"nodeclaim.termination","controllerGroup":"karpenter.sh","controllerKind":"NodeClaim","NodeClaim":{"name":"default-wgbwq"},"namespace":"","name":"default-wgbwq","reconcileID":"0dea1bc7-8bd6-4a51-98d4-c771c0909529","Node":{"name":"ip-10-0-55-209.us-east-2.compute.internal"},"provider-id":"aws:///us-east-2a/i-0f4fe866297af566d"}

```

Now, let's deploy [echoserver_full.yaml](./EKS/echoserver_full.yaml) and access
it via the DNS we get from the AWS ALB. BTW, it will be an `Application Load
Balancer`, as we have an `Ingress` between the `ALB` and the `Service`.

```
$ kubectl apply -f echoserver_full.yaml 
namespace/echoserver created
deployment.apps/echoserver created
service/echoserver created
ingress.networking.k8s.io/echoserver created
$ kubectl get ing -n echoserver echoserver
NAME         CLASS   HOSTS   ADDRESS                                                                   PORTS   AGE
echoserver   alb     *       k8s-echoserv-echoserv-0c6afc926b-2140404222.us-east-2.elb.amazonaws.com   80      75m
```

## Monitoring with Prometheus & Grafana 

```
$  kubectl create namespace prometheus
namespace/prometheus created
$ helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
"prometheus-community" already exists with the same configuration, skipping
$ helm upgrade -i prometheus prometheus-community/prometheus \
    --namespace prometheus \
    --set alertmanager.persistentVolume.storageClass="gp2",server.persistentVolume.storageClass="gp2"

WARNING: Kubernetes configuration file is group-readable. This is insecure. Location: /home/sajid/.kube/config
WARNING: Kubernetes configuration file is world-readable. This is insecure. Location: /home/sajid/.kube/config
Release "prometheus" does not exist. Installing it now.
NAME: prometheus
LAST DEPLOYED: Thu Sep 12 04:37:51 2024
NAMESPACE: prometheus
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
The Prometheus server can be accessed via port 80 on the following DNS name from within your cluster:
prometheus-server.prometheus.svc.cluster.local


Get the Prometheus server URL by running these commands in the same shell:
  export POD_NAME=$(kubectl get pods --namespace prometheus -l "app.kubernetes.io/name=prometheus,app.kubernetes.io/instance=prometheus" -o jsonpath="{.items[0].metadata.name}")
  kubectl --namespace prometheus port-forward $POD_NAME 9090


The Prometheus alertmanager can be accessed via port 9093 on the following DNS name from within your cluster:
prometheus-alertmanager.prometheus.svc.cluster.local


Get the Alertmanager URL by running these commands in the same shell:
  export POD_NAME=$(kubectl get pods --namespace prometheus -l "app.kubernetes.io/name=alertmanager,app.kubernetes.io/instance=prometheus" -o jsonpath="{.items[0].metadata.name}")
  kubectl --namespace prometheus port-forward $POD_NAME 9093
#################################################################################
######   WARNING: Pod Security Policy has been disabled by default since    #####
######            it deprecated after k8s 1.25+. use                        #####
######            (index .Values "prometheus-node-exporter" "rbac"          #####
###### .          "pspEnabled") with (index .Values                         #####
######            "prometheus-node-exporter" "rbac" "pspAnnotations")       #####
######            in case you still need it.                                #####
#################################################################################


The Prometheus PushGateway can be accessed via port 9091 on the following DNS name from within your cluster:
prometheus-prometheus-pushgateway.prometheus.svc.cluster.local


Get the PushGateway URL by running these commands in the same shell:
  export POD_NAME=$(kubectl get pods --namespace prometheus -l "app=prometheus-pushgateway,component=pushgateway" -o jsonpath="{.items[0].metadata.name}")
  kubectl --namespace prometheus port-forward $POD_NAME 9091

For more information on running Prometheus, visit:
https://prometheus.io/

```













**Always delete the AWS resources to save money after you are done.**

```
$ kubectl delete --all nodeclaim
$ kubectl delete --all nodepool
$ kubectl delete --all ec2nodeclass
$ kubectl config  delete-cluster arn:aws:eks:<region>:<account_id>:cluster/<cluster_name>
$ terraform destroy --auto-approve
```

## Tasks

| **Task ID** | **Details**                                             | **Status**         | **Comment(s)** |
|-------------|---------------------------------------------------------|--------------------|----------------|
| Task-1      | Create VPC for EKS cluster                              | :white_check_mark: |                |
| Task-2      | Create EKS Cluster with Karpenter for node scaling      | :white_check_mark: |                |
| Task-3      | Deploy Stateless application                            | :white_check_mark: |                |
| Task-4      | ALB Ingress for access from the internet                | :white_check_mark: |                |
| Task-5      | Prometheus Grafana integration for monitoring           | :x:                |                |
| Task-6      | ConfigMap and Secrets                                   | :x:                |                |
| Task-7      | ConfigMap and Secrets [with AWS parameter store]        | :x:                |                |
| Task-8      | Deploy DaemonSet                                        | :x:                |                |
| Task-9      | Deploy Stateful Application                             | :x:                |                |
| Task-10     | Create Admin and Developer accounts for granular access | :x:                |                |
| Task-11     | To be amended in the future                             | :x:                |                |

## References

- [terraform-aws-eks-blueprints](https://aws-ia.github.io/terraform-aws-eks-blueprints/getting-started/)
- [Karpenter getting started](https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/)
- [karpenter-blueprints](https://github.com/aws-samples/karpenter-blueprints/tree/main)
- [terraform-aws-eks-blueprints-addons](https://github.com/aws-ia/terraform-aws-eks-blueprints-addons/blob/main/docs/addons/aws-load-balancer-controller.md)
- [aws-load-balancer-controller](https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/main/helm/aws-load-balancer-controller/values.yaml)
- [terraform-aws-eks-blueprints-addon readme](https://github.com/aws-ia/terraform-aws-eks-blueprints-addon#readme)
- [deploy-prometheus](https://archive.eksworkshop.com/intermediate/240_monitoring/deploy-prometheus/)
- https://navyadevops.hashnode.dev/setting-up-prometheus-and-grafana-on-amazon-eks-for-kubernetes-monitoring
- https://github.com/aws-ia/terraform-aws-eks-blueprints-addons/blob/main/main.tf