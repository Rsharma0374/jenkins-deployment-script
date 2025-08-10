#!/bin/bash
set -e  # Exit on any error

echo "=== Starting Email Connector Service Kubernetes Deployment ==="

PASSWORD=$1  # First argument passed to the script
SERVER_IP="161.118.166.22"
REPO_NAME="emailConnecter-core"
DOCKER_IMAGE_NAME="email-connector-service"
DOCKER_IMAGE_TAG="latest"
#INGRESS_REPO_NAME="jenkins-deployment-script"

# Run everything on the remote Kubernetes server
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no ubuntu@$SERVER_IP << EOF
    set -e
    echo "=== Connected to Kubernetes Server ($SERVER_IP) ==="

    cd /home/ubuntu/deployment/repo/core

    echo "=== Killing old port forwarding ==="
    PIDS=$(ps aux | grep "kubectl port-forward service/email-connector-service" | grep -v grep | awk '{print $2}')
    if [ -n "$PIDS" ]; then
        echo "Found PIDs: $PIDS"
        kill $PIDS
    else
        echo "No existing port-forward process found for email-connector-service."
    fi
    
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
        git clone git@github.com:Rsharma0374/emailConnecter-core.git
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
    kubectl create secret generic infisical-secret --from-file=infisical.properties=/opt/configs/infisical.properties -n default
    kubectl apply -f email-connector-deployment.yaml
    kubectl apply -f email-connector-service.yaml



    # echo "=== Applying Ingress ==="
    # cd /home/ubuntu/deployment/repo/core

    # if [ -d "$INGRESS_REPO_NAME" ]; then
    #     cd $INGRESS_REPO_NAME
    #     git reset --hard
    #     git checkout main
    #     git pull origin main
    # else
    #     git clone git@github.com:Rsharma0374/jenkins-deployment-script.git
    #     cd $INGRESS_REPO_NAME
    #     git checkout main
    # fi
    # cd jenkins-deployment-script/ingress
    # kubectl apply -f ingress.yaml

    echo "=== Waiting for deployment rollout ==="
    kubectl rollout status deployment/$DOCKER_IMAGE_NAME

    echo "=== Current pod status ==="
    kubectl get pods

    echo "=== Port forwarding ==="
    nohup kubectl port-forward service/email-connector-service 10002:10002 > /dev/null 2>&1 &

    echo "=== Restarting Nginx ==="
    sudo systemctl restart nginx
EOF

echo "=== Deployment Completed Successfully ==="
