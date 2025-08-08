#!/bin/bash
set -e  # Exit on any error

echo "=== Starting Eureka Service Kubernetes Deployment ==="

PASSWORD=$1  # First argument passed to the script
SERVER_IP="129.154.238.85"

REPO_NAME="euruka-service-registry"
DOCKER_IMAGE_NAME="eureka-service"
DOCKER_IMAGE_TAG="latest"

# Run everything on the remote Kubernetes server
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no ubuntu@$SERVER_IP << EOF
    set -e
    echo "=== Connected to Kubernetes Server ($SERVER_IP) ==="

    cd /home/ubuntu/deployment/repo/core

    echo "=== Cleaning up old Kubernetes resources ==="
    if kubectl get deployment $DOCKER_IMAGE_NAME >/dev/null 2>&1; then
        echo "Deleting existing deployment..."
        kubectl delete deployment $DOCKER_IMAGE_NAME
    fi

    if kubectl get service $DOCKER_IMAGE_NAME >/dev/null 2>&1; then
        echo "Deleting existing service..."
        kubectl delete service $DOCKER_IMAGE_NAME
    fi

    echo "Deleting pods with label app=$DOCKER_IMAGE_NAME..."
    kubectl delete pods -l app=$DOCKER_IMAGE_NAME --ignore-not-found

    echo "=== Removing old Docker image if exists ==="
    if docker images | grep -q "$DOCKER_IMAGE_NAME"; then
        docker rmi -f \$(docker images "$DOCKER_IMAGE_NAME" -q)
    fi

    echo "=== Cloning or updating repository ==="
    if [ -d "$REPO_NAME" ]; then
        cd $REPO_NAME
        git reset --hard
        git checkout main
        git pull origin main
    else
        git clone git@github.com:Rsharma0374/euruka-service-registry.git
        cd $REPO_NAME
        git checkout main
    fi

    echo "=== Building Docker image ==="
    docker build -t $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG .

    docker tag $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG rsharma0374/$DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG

    echo "=== Logging in to Docker Hub ==="
    docker login

    echo "=== Pushing Docker image to Docker Hub ==="
    docker push rsharma0374/$DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG

    echo "=== Applying Kubernetes manifests ==="
    kubectl apply -f eureka-deployment.yaml
    kubectl apply -f eureka-service.yaml

    echo "=== Waiting for deployment rollout ==="
    kubectl rollout status deployment/$DOCKER_IMAGE_NAME

    echo "=== Current pod status ==="
    kubectl get pods

    echo "=== Port Forwarding ==="
    nohup kubectl port-forward service/eureka-service 8761:8761 >/dev/null 2>&1 &

    echo "=== Restarting Nginx ==="
    sudo systemctl restart nginx
EOF

echo "=== Deployment Completed Successfully ==="
