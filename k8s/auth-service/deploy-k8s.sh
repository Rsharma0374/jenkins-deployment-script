#!/bin/bash
set -e  # Exit on any error

echo "=== Starting Document Utility Service Kubernetes Deployment ==="

PASSWORD=$1  # First argument passed to the script
BRANCH=$2
SERVER_IP="80.225.218.113"
REPO_NAME="userAuthentication"
DOCKER_IMAGE_NAME="auth-service"
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
        git checkout $BRANCH
        git pull origin $BRANCH
    else
        git clone git@github.com:Rsharma0374/userAuthentication.git
        cd $REPO_NAME
        git checkout $BRANCH
    fi

    echo "=== Building Docker image ==="
    docker build -t $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG .

    docker tag $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG rsharma0374/$DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG

    echo "=== Logging in to Docker Hub ==="
    docker login

    echo "=== Pushing Docker image to Docker Hub ==="
    docker push rsharma0374/$DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG

    echo "=== Applying Kubernetes manifests ==="
    
    # Create or update the secret (idempotent)
    if kubectl get secret infisical-secret -n default >/dev/null 2>&1; then
        echo "Updating existing infisical-secret..."
        kubectl delete secret infisical-secret -n default
    fi
    kubectl create secret generic infisical-secret --from-file=infisical.properties=/opt/configs/infisical.properties -n default
    echo "✅ Secret created/updated successfully"
    
    # Apply deployment and service
    kubectl apply -f auth-deployment.yaml
    kubectl apply -f auth-service.yaml
    echo "✅ Kubernetes manifests applied successfully"

    echo "=== Waiting for deployment rollout ==="
    kubectl rollout status deployment/$DOCKER_IMAGE_NAME

    echo "=== Current pod status ==="
    kubectl get pods

    echo "=== Restarting Nginx ==="
    sudo systemctl restart nginx
EOF

echo "=== Deployment Completed Successfully ==="
