# HTTPS endpoints for Digital Human for Customer Service on GKE

Deploying HTTPS endpoints for the digital human blueprint on GKE.

## Table of Contents

- [Prerequisetes](#prerequisites)
- [Setup](#setup)

## Prerequisites

- **kubectl:**  kubectl command-line tool installed and configured.
- **GKE credentials** Ensure you have the credentials to access the GKE cluster.
- **Certificates**  Privileges to create certificates.
- **IP Reservation** Privileges to reserve IP addresses.

## Setup

1. **Cluster update**: You'll need to update the cluster by enabling GKE Gateway controller and addon for HTTP LoadBalancing
    ```bash

    gcloud container clusters update "${CLUSTER_NAME}" \
      --location="${ZONE}"  \
      --gateway-api=standard

    gcloud container clusters update "${CLUSTER_NAME}" \
      --location="${ZONE}"  \
      --update-addons=HttpLoadBalancing=ENABLED

    ```

2. **Environment setup**: You'll set up one environment variable "${NIMS}" to make the following steps easier and more flexible. If you want to include more NIMs, remember to change the port (8000) if required.

    ```bash

    export NIMS="dighum-embedqa-e5v5 dighum-llama3-8b dighum-rerankqa-mistral4bv3"

    ```

3. **Static IP Reservation**:

    ```bash

    for NIM in ${NIMS}; do
      gcloud compute addresses create ${NIM}-ip --global;
    done

    ```

4. **DNS**: Configure the DNS subdomains for each NIM. Our sub-domains for this example will be in this format <YOUR IP>.nip.io

5. **Creating the SSL Certs**: Based on the previous global external IP(s) reserved on the step 3

    ```bash

    for NIM in ${NIMS}; do
      NIM_DNS="`gcloud compute addresses list --filter=name=${NIM}-ip --format='value(address)'`.nip.io"
      gcloud compute ssl-certificates create ${NIM}-cert --domains=${NIM_DNS};
    done

    ```

6. **Create k8s service, gateway and http-route and healthcheck**
  
    ```bash

    for NIM in ${NIMS}; do
      NIM_DNS="`gcloud compute addresses list --filter=name=${NIM}-ip --format='value(address)'`.nip.io"

    kubectl apply -f - <<EOF
    apiVersion: v1
    kind: Service
    metadata:
      name: ${NIM}-svc
    spec:
      selector:
        app: ${NIM}
      ports:
      - protocol: TCP
        port: 8000
        targetPort: 8000
    ---
    kind: Gateway
    apiVersion: gateway.networking.k8s.io/v1beta1
    metadata:
      name: ${NIM}-gw
    spec:
      gatewayClassName: gke-l7-global-external-managed
      listeners:
      - name: https
        protocol: HTTPS
        port: 443
        tls:
          mode: Terminate
          options:
            networking.gke.io/pre-shared-certs: ${NIM}-cert
      addresses:
      - type: NamedAddress
        value: ${NIM}-ip
    ---
    kind: HTTPRoute
    apiVersion: gateway.networking.k8s.io/v1beta1
    metadata:
      name: ${NIM}-httpr
    spec:
      parentRefs:
      - kind: Gateway
        name: ${NIM}-gw
      hostnames:
      - "${NIM_DNS}"
      rules:
      - backendRefs:
        - name: ${NIM}-svc
          port: 8000
    ---
    apiVersion: networking.gke.io/v1
    kind: HealthCheckPolicy
    metadata:
      name: ${NIM}-hcheck
    spec:
      default:
        checkIntervalSec: 15
        timeoutSec: 1
        healthyThreshold: 1
        unhealthyThreshold: 2
        config:
          type: TCP
          httpHealthCheck:
            port: 8000
            requestPath: /v1/health/ready
      targetRef:
        group: ""
        kind: Service
        name: ${NIM}-svc
    EOF

    done

    ```

### Check certificates

The certificate can take 15 minutes to be attached to the LB

1. **To check**

    ```bash

    gcloud compute ssl-certificates list

    ```

## Remove LB services

Ensure that your HTTPS connection is working before remove the LB services

1. **Delete the old LB services for the HTTPS NIMs**

    ```bash

    for NIM in ${NIMS}; do
      kubectl delete svc ${NIM}-lb
    done

    ```
