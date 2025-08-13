#!/bin/bash
set -e  # Exit on any error

echo "=== Starting Document Utility Web Service ==="

PASSWORD=$1  # First argument passed to the script
BRANCH=$2
SERVER_IP="80.225.213.153"
REPO_NAME="document-utility-web"

# Run everything on the remote Kubernetes server
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no ubuntu@$SERVER_IP << EOF
sudo su - jenkins << 'EOF'
    set -e
    echo "=== Connected to Kubernetes Server ($SERVER_IP) ==="

    cd /var/lib/jenkins/repository/web

    echo "=== Cloning or updating repository ==="
    if [ -d "$REPO_NAME" ]; then
        cd $REPO_NAME
        git reset --hard
        git checkout $BRANCH
        git pull origin $BRANCH
    else
        git clone git@github.com:Rsharma0374/document-utility-web.git
        cd $REPO_NAME
        git checkout $BRANCH
    fi

echo "Install the dependencies"
npm install

echo "Build the project"
npm run build

echo "Restart the nginx"
sudo systemctl restart nginx

echo "=== Deployment Completed Successfully ==="
EOF

