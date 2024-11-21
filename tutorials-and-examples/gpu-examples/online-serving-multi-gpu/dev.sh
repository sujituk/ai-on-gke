gcloud config set project "isv-coe-skhas-nvidia"
export PROJECT_ID=$(gcloud config get project)
export CLUSTER_NAME="gke-mx-gpu-triton"
export NODE_POOL_NAME="gpu-nodepool"
export HF_TOKEN="<HF Token>"

export ZONE="us-west1-b"
export MACHINE_TYPE="a3-highgpu-8g"
export ACCELERATOR_TYPE="nvidia-h100-80gb"
export ACCELERATOR_COUNT="8"
export NODE_POOL_NODES=1

export ZONE="us-west1-b"
export MACHINE_TYPE="g2-standard-4"
export ACCELERATOR_TYPE="nvidia-l4"
export ACCELERATOR_COUNT="1"
export NODE_POOL_NODES=2

gcloud container clusters create "${CLUSTER_NAME}" \
	--project="${PROJECT_ID}" \
	--num-nodes="${NODE_POOL_NODES}" \
	--location="${ZONE}" \
	--machine-type=e2-standard-16 \
	--addons=GcpFilestoreCsiDriver

gcloud container node-pools create "${NODE_POOL_NAME}" \
	--cluster="${CLUSTER_NAME}" \
	--location="${ZONE}" \
	--node-locations="${ZONE}" \
	--num-nodes="${NODE_POOL_NODES}" \
	--machine-type="${MACHINE_TYPE}" \
	--accelerator="type=${ACCELERATOR_TYPE},count=${ACCELERATOR_COUNT},gpu-driver-version=LATEST" \
	--placement-type="COMPACT" \
	--labels gpu=true

gcloud container clusters get-credentials "${CLUSTER_NAME}" \
	--location="${ZONE}"

alias k=kubectl

VERSION=v0.4.0
kubectl apply --server-side -f https://github.com/kubernetes-sigs/lws/releases/download/$VERSION/manifests.yaml

kubectl create secret generic hf-secret \
	--from-literal=hf_api_token=${HF_TOKEN} \
	--dry-run=client -o yaml | kubectl apply -f -

k apply -f fs-sc.yaml && k apply -f pvc.yaml

k apply -f job_conv_checkpoint.yaml

POD_TRITON_NAME=$(kubectl get pods -o go-template --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' | grep '^triton-trtllm-0-1')

k exec -it ${POD_TRITON_NAME} -- bash

python3 server.py leader \
	--triton_model_repo_dir=/var/run/models/tensorrtllm_backend/triton_model_repo \
	--namespace=default \
	--pp=2 \
	--tp=8 \
	--gpu_per_node=8 \
	--stateful_set_group_key=e2978b7f633b338484dadb9485246b6cc19220d3 \
	--verbose
