#!/bin/bash

# Exit on any error
set -e

echo "=== Starting Eureka Service Kubernetes Deployment ==="

PASSWORD=$1  # First argument passed to the script

echo "Using password: $PASSWORD"

sshpass -p '$PASSWORD' ssh -t ubuntu@129.154.238.85

# Configuration
REPO_NAME="euruka-service-registry"
DOCKER_IMAGE_NAME="eureka-service"
DOCKER_IMAGE_TAG="latest"
K8S_NAMESPACE="default"

echo "Change to Jenkins workspace directory"
cd /home/ubuntu/deployment/repo/core

echo "Check if repository already exists"
if [ -d "$REPO_NAME" ]; then
    echo "Repository already exists, updating..."
    cd $REPO_NAME
    git checkout main
    git pull origin main
else
    echo "Cloning repository..."
    git clone git@github.com:Rsharma0374/euruka-service-registry.git
    cd $REPO_NAME
    git checkout main
fi

echo "Building Docker image..."
docker build -t $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG .

echo "Applying Kubernetes deployment..."
kubectl apply -f eureka-deployment.yaml

echo "Applying Kubernetes service..."
kubectl apply -f eureka-service.yaml

echo "=== Deployment completed successfully ==="

echo "Checking pod status:"
kubectl get pods
