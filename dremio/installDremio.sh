#!/usr/bin/env bash

if [ $# != 3 ]; then
  echo "Usage: $0 clustername azure_location k8s_node_count "
  exit 1
fi
clustername=$1
location=$2
nodecount=$3
vmSize=Standard_DS14_v2
k8sCluster=$clustername-dremio-k8s
image=dremio/dremio-oss:3.0.0
repo=https://raw.githubusercontent.com/Nirmalyasen/arm-templates/master/charts

sp=$(az ad sp create-for-rbac --skip-assignment)
appId=$(echo $sp | jq -r '.appId')
password=$(echo $sp | jq -r '.password')

az group show --name $clustername || az group create --name $clustername --location $location
echo "Creating K8S cluster..."
az aks create --resource-group $clustername \
 --name $k8sCluster \
 --location $location \
 --node-count=$nodecount \
 --node-vm-size $vmSize \
 --service-principal $appId \
 --client-secret $password \
 --generate-ssh-keys
[ $? != 0 ] && echo "K8S deployment failed. Please review the error." && exit 1
echo "Setting up K8S cluster..."
az aks get-credentials --overwrite-existing --resource-group $clustername --name $k8sCluster
kubectl create serviceaccount -n kube-system tiller
kubectl create clusterrolebinding tiller-binding --clusterrole=cluster-admin --serviceaccount kube-system:tiller
helm init --service-account tiller --wait
echo "Deploying Dremio..."
helm install dremio --set image=$image --name dremio-cluster --wait --timeout 900 --repo $repo
[ $? != 0 ] && echo "Dremio deployment failed. Please review the error." && exit 1
echo "Deployment complete."
echo "You can access Dremio using:"
dremioUIAddress=$(kubectl get services --output json dremio-client | jq -r .items[0].status.loadBalancer.ingress[0].ip)
echo "    http://$dremioUIAddress:9047"
echo "Enjoy using Dremio!"
