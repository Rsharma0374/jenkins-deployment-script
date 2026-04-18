#!/bin/bash
set -e

echo "=== Starting Email Connector Service Deployment (Maven) ==="

PASSWORD=$1
BRANCH=$2

SERVER_IP="80.225.218.113"
REPO_NAME="emailConnecter-core"
APP_NAME="email-connector-service"
APP_PORT="10002"
JAR_PATH="target/*.jar"
LOG_DIR="/var/log/email-connector-service"
LOG_FILE="$LOG_DIR/email-service.log"

if [ -z "$PASSWORD" ] || [ -z "$BRANCH" ]; then
    echo "Usage: $0 <server-password> <branch>"
    exit 1
fi

sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no ubuntu@$SERVER_IP << EOF
    set -e

    echo "=== Connected to EC2 Server ($SERVER_IP) ==="

    cd /home/ubuntu/deployment/repo/core

    echo "=== Cloning or Updating Repository ==="
    if [ -d "$REPO_NAME" ]; then
        sudo -u jenkins git -C $REPO_NAME reset --hard
        sudo -u jenkins git -C $REPO_NAME checkout $BRANCH
        sudo -u jenkins git -C $REPO_NAME pull origin $BRANCH
    else
        sudo -u jenkins git clone git@github.com:Rsharma0374/emailConnecter-core.git
        sudo -u jenkins git -C $REPO_NAME checkout $BRANCH
    fi

    cd $REPO_NAME

    echo "=== Building Application with Maven ==="
    mvn clean install -DskipTests

    echo "=== Preparing Log Directory ==="
    sudo mkdir -p $LOG_DIR
    sudo touch $LOG_FILE
    sudo chown ubuntu:ubuntu $LOG_DIR $LOG_FILE

    echo "=== Stopping Existing Application (if running) ==="
    PID=\$(lsof -t -i:$APP_PORT || true)
    if [ ! -z "\$PID" ]; then
        echo "Killing process on port $APP_PORT (PID: \$PID)"
        kill -9 \$PID
    fi

    echo "=== Starting Application ==="
    JAR_FILE=\$(ls $JAR_PATH | head -n 1)

    nohup java -jar \$JAR_FILE > $LOG_FILE 2>&1 &

    echo "=== Application Started. Logs: $LOG_FILE ==="

    echo "=== Restarting Nginx ==="
    sudo systemctl restart nginx

    echo "=== Deployment Finished on Server ==="
EOF

echo "=== Deployment Completed Successfully ==="