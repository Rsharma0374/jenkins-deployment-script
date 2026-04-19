#!/bin/bash
set -e

echo "=== Starting API Gateway Service Deployment (Maven) ==="

PASSWORD=$1
BRANCH=$2

SERVER_IP="80.225.218.113"
REPO_NAME="API-Gateway"
APP_NAME="API-Gateway"
APP_PORT="10008"
JAR_PATH="target/*.jar"
LOG_DIR="/var/log/API-Gateway"
LOG_FILE="$LOG_DIR/API-Gateway.log"

if [ -z "$PASSWORD" ] || [ -z "$BRANCH" ]; then
    echo "Usage: $0 <server-password> <branch>"
    exit 1
fi

sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no ubuntu@$SERVER_IP << EOF
    set -e

    echo "=== Connected to Server ($SERVER_IP) ==="

    cd /home/ubuntu/deployment/repo/core

    echo "=== Cloning or Updating Repository ==="
    if [ -d "$REPO_NAME" ]; then
        git -C $REPO_NAME reset --hard
        git -C $REPO_NAME checkout $BRANCH
        git -C $REPO_NAME pull origin $BRANCH
    else
        git clone git@github.com:Rsharma0374/API-Gateway.git
        git -C $REPO_NAME checkout $BRANCH
    fi

    cd $REPO_NAME

    echo "=== Building Application with Maven ==="
    mvn clean install -DskipTests

    echo "=== Preparing Log Directory ==="
    sudo mkdir -p $LOG_DIR
    sudo touch $LOG_FILE
    sudo chown ubuntu:ubuntu $LOG_DIR $LOG_FILE

    echo "=== Stopping Existing Application (NOT NGINX) ==="
    PID=\$(lsof -t -i:$APP_PORT || true)
    if [ ! -z "\$PID" ]; then
        echo "Killing APP on port $APP_PORT (PID: \$PID)"
        kill -9 \$PID
    fi

    echo "=== Starting Application on port $APP_PORT ==="
    JAR_FILE=\$(ls $JAR_PATH | head -n 1)

    nohup java -jar \$JAR_FILE --server.port=$APP_PORT > $LOG_FILE 2>&1 &

    echo "=== Waiting for app to boot ==="
    sleep 5

    echo "=== Health Check ==="
    curl -f http://127.0.0.1:$APP_PORT || echo "Health check failed"

    echo "=== Deployment Finished on Server ==="
EOF

echo "=== Deployment Completed Successfully ==="