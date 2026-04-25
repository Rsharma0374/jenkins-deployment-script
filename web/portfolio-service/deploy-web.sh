#!/bin/bash
set -e  # Exit on any error

echo "=== Starting Portfolio Web Service ==="

PASSWORD=$1  # First argument passed to the script
BRANCH=$2
SERVER_IP="80.225.218.113"
REPO_NAME="rahul_portfolio_reactjs"

# Run everything on the remote Kubernetes server
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no ubuntu@$SERVER_IP <<EOF
set -e
echo "=== Connected to Web Server ($SERVER_IP) ==="

cd /home/ubuntu/deployment/repo/web

echo "=== Cloning or updating repository ==="
if [ -d "$REPO_NAME" ]; then
    git -C $REPO_NAME reset --hard
    git -C $REPO_NAME checkout $BRANCH
    git -C $REPO_NAME pull origin $BRANCH
else
    git clone git@github.com:Rsharma0374/rahul-portfolio.git
    git -C $REPO_NAME checkout $BRANCH
fi

echo "Install the dependencies"
npm install --prefix $REPO_NAME

echo "Build the project"
npm run build --prefix $REPO_NAME

echo "Restart the nginx"
sudo systemctl restart nginx

echo "=== Deployment Completed Successfully ==="
EOF

