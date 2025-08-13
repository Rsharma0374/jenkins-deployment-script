#!/bin/bash
set -e  # Exit on any error

echo "=== Starting Document Utility Web Service ==="

PASSWORD=$1  # First argument passed to the script
BRANCH=$2
SERVER_IP="80.225.213.153"
REPO_NAME="rahul_portfolio_reactjs"

# Run everything on the remote Kubernetes server
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no ubuntu@$SERVER_IP <<EOF
set -e
echo "=== Connected to Web Server ($SERVER_IP) ==="

cd /var/lib/jenkins/repository/web

echo "=== Cloning or updating repository ==="
if [ -d "$REPO_NAME" ]; then
    sudo -u jenkins git -C $REPO_NAME reset --hard
    sudo -u jenkins git -C $REPO_NAME checkout $BRANCH
    sudo -u jenkins git -C $REPO_NAME pull origin $BRANCH
else
    sudo -u jenkins git clone git@github.com:Rsharma0374/rahul_portfolio_reactjs.git $REPO_NAME
    sudo -u jenkins git -C $REPO_NAME checkout $BRANCH
fi

echo "Install the dependencies"
sudo -u jenkins npm install --prefix $REPO_NAME

echo "Build the project"
sudo -u jenkins npm run build --prefix $REPO_NAME

echo "Restart the nginx"
sudo systemctl restart nginx

echo "=== Deployment Completed Successfully ==="
EOF

