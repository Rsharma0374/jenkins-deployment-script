#!/bin/bash
set -euo pipefail

echo "======================================================"
echo "🚀 Starting Screening Room Node.js Deployment"
echo "    Build on Jenkins, Run with PM2 on Server"
echo "======================================================"

# -------------------------------------------------------
# Jenkins parameters
# -------------------------------------------------------

PASSWORD="${1:-}"
BRANCH="${2:-}"
SCAN_VULNERABILITIES="${3:-}"

if [ -z "$PASSWORD" ] || [ -z "$BRANCH" ]; then
    echo "❌ Usage: $0 <server-password> <branch> [YES|NO]"
    exit 1
fi

# -------------------------------------------------------
# Server configuration
# -------------------------------------------------------

SERVER_IP="140.238.230.44"
REMOTE_USER="opc"

# -------------------------------------------------------
# Git configuration
# -------------------------------------------------------

REPO_URL="git@github.com:Rsharma0374/watch-together.git"
REPO_NAME="watch-together"

# Node.js application is inside this directory
APP_SOURCE_DIR="screening-room-backend"

# -------------------------------------------------------
# Application configuration
# -------------------------------------------------------

APP_NAME="screening-room-backend"
APP_PORT="10002"

# Change this if your Node.js file has a different name.
# For example: app.js, index.js, server.js
NODE_ENTRY="server.js"

# -------------------------------------------------------
# Jenkins workspace
# -------------------------------------------------------

WORKDIR="${WORKSPACE:-$PWD}"

LOCAL_REPO_DIR="${WORKDIR}/${REPO_NAME}"
LOCAL_APP_DIR="${LOCAL_REPO_DIR}/${APP_SOURCE_DIR}"

# -------------------------------------------------------
# Remote application paths
# -------------------------------------------------------

REMOTE_APP_DIR="/opt/${APP_NAME}"
REMOTE_LOG_DIR="${REMOTE_APP_DIR}/log"

REMOTE_LOG_FILE="${REMOTE_LOG_DIR}/${APP_NAME}.log"

# -------------------------------------------------------
# Validate tools
# -------------------------------------------------------

echo ""
echo "=== Checking Jenkins tools ==="

command -v git >/dev/null 2>&1 || {
    echo "❌ git is not installed"
    exit 1
}

command -v npm >/dev/null 2>&1 || {
    echo "❌ npm is not installed"
    exit 1
}

command -v sshpass >/dev/null 2>&1 || {
    echo "❌ sshpass is not installed"
    exit 1
}

echo "✅ Git found"
echo "✅ npm found"
echo "✅ sshpass found"

# -------------------------------------------------------
# Clone / update repository
# -------------------------------------------------------

echo ""
echo "======================================================"
echo "📥 Jenkins: Cloning / Updating repository"
echo "======================================================"

if [ -d "${LOCAL_REPO_DIR}/.git" ]; then

    echo "🔄 Existing repository found"

    git -C "$LOCAL_REPO_DIR" fetch --all --prune

    echo "🌿 Checking out branch: $BRANCH"

    git -C "$LOCAL_REPO_DIR" checkout "$BRANCH"

    git -C "$LOCAL_REPO_DIR" reset --hard "origin/$BRANCH"

    git -C "$LOCAL_REPO_DIR" clean -fd

else

    echo "📥 Cloning repository..."

    rm -rf "$LOCAL_REPO_DIR"

    git clone "$REPO_URL" "$LOCAL_REPO_DIR"

    git -C "$LOCAL_REPO_DIR" checkout "$BRANCH"

fi

echo "✅ Repository ready"

# -------------------------------------------------------
# Validate application directory
# -------------------------------------------------------

if [ ! -d "$LOCAL_APP_DIR" ]; then
    echo "❌ Application directory not found:"
    echo "$LOCAL_APP_DIR"
    exit 1
fi

cd "$LOCAL_APP_DIR"

echo ""
echo "📁 Application directory:"
pwd

echo ""
echo "📂 Application files:"
ls -la

# -------------------------------------------------------
# Validate Node.js application
# -------------------------------------------------------

if [ ! -f "package.json" ]; then
    echo "❌ package.json not found in:"
    echo "$LOCAL_APP_DIR"
    exit 1
fi

if [ ! -f "$NODE_ENTRY" ]; then
    echo "❌ Node.js entry file not found:"
    echo "$LOCAL_APP_DIR/$NODE_ENTRY"
    echo ""
    echo "Change NODE_ENTRY in this script to your actual file."
    exit 1
fi

echo "✅ package.json found"
echo "✅ Node.js entry file found: $NODE_ENTRY"

# -------------------------------------------------------
# Install dependencies
# -------------------------------------------------------

echo ""
echo "======================================================"
echo "📦 Installing Node.js dependencies"
echo "======================================================"

if [ -f "package-lock.json" ]; then

    echo "📦 package-lock.json found"
    echo "Running npm ci..."

    npm ci

else

    echo "⚠️ package-lock.json not found"
    echo "Running npm install..."

    npm install

fi

echo "✅ Node.js dependencies installed"

# -------------------------------------------------------
# Vulnerability scan
# -------------------------------------------------------

if [ "$SCAN_VULNERABILITIES" = "YES" ]; then

    echo ""
    echo "======================================================"
    echo "🔐 Running vulnerability scan"
    echo "======================================================"

    /opt/trivy/trivy-scan.sh \
        "$LOCAL_APP_DIR" \
        "${APP_NAME}-trivy-report"

    echo "✅ Vulnerability scan completed"

else

    echo ""
    echo "=== Vulnerability scanning skipped ==="

fi

# -------------------------------------------------------
# Prepare remote server
# -------------------------------------------------------

echo ""
echo "======================================================"
echo "🖥️ Preparing remote server"
echo "======================================================"

sshpass -p "$PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    "${REMOTE_USER}@${SERVER_IP}" << EOF

set -e

echo "=== Connected to ${SERVER_IP} ==="

echo "=== Creating application directory ==="

sudo mkdir -p "${REMOTE_APP_DIR}"
sudo mkdir -p "${REMOTE_LOG_DIR}"

sudo chown -R "${REMOTE_USER}:${REMOTE_USER}" "${REMOTE_APP_DIR}"

EOF

echo "✅ Remote directories ready"

# -------------------------------------------------------
# Copy Node.js application
# -------------------------------------------------------

echo ""
echo "======================================================"
echo "📤 Copying Node.js application to server"
echo "======================================================"

sshpass -p "$PASSWORD" rsync \
    -az \
    --delete \
    --exclude=".git" \
    --exclude="node_modules" \
    --exclude=".env" \
    -e "ssh -o StrictHostKeyChecking=no" \
    "${LOCAL_APP_DIR}/" \
    "${REMOTE_USER}@${SERVER_IP}:${REMOTE_APP_DIR}/"

echo "✅ Application copied to server"

# -------------------------------------------------------
# Install production dependencies on server
# -------------------------------------------------------

echo ""
echo "======================================================"
echo "📦 Installing production dependencies on server"
echo "======================================================"

sshpass -p "$PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    "${REMOTE_USER}@${SERVER_IP}" << EOF

set -e

cd "${REMOTE_APP_DIR}"

echo "=== Installing production dependencies ==="

if [ -f package-lock.json ]; then
    npm ci --omit=dev
else
    npm install --omit=dev
fi

echo "✅ Production dependencies installed"

EOF

# -------------------------------------------------------
# Start / Restart application using PM2
# -------------------------------------------------------

echo ""
echo "======================================================"
echo "🚀 Starting application with PM2"
echo "======================================================"

sshpass -p "$PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    "${REMOTE_USER}@${SERVER_IP}" << EOF

set -e

cd "${REMOTE_APP_DIR}"

echo "=== Checking PM2 ==="

if ! command -v pm2 >/dev/null 2>&1; then
    echo "❌ PM2 is not installed"
    echo "Install it with:"
    echo "npm install -g pm2"
    exit 1
fi

echo "✅ PM2 found"

echo "=== Stopping existing application ==="

pm2 delete "${APP_NAME}" 2>/dev/null || true

echo "=== Starting Node.js application ==="

PORT="${APP_PORT}" \
pm2 start "${NODE_ENTRY}" \
    --name "${APP_NAME}" \
    --time \
    --update-env

echo "=== Saving PM2 process list ==="

pm2 save

echo "=== PM2 process status ==="

pm2 status

EOF

# -------------------------------------------------------
# Configure PM2 startup
# -------------------------------------------------------

echo ""
echo "======================================================"
echo "⚙️ Configuring PM2 startup"
echo "======================================================"

sshpass -p "$PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    "${REMOTE_USER}@${SERVER_IP}" << EOF

set -e

echo "=== Configuring PM2 system startup ==="

sudo env PATH=\$PATH:/usr/bin pm2 startup systemd \
    -u "${REMOTE_USER}" \
    --hp "/home/${REMOTE_USER}" \
    >/tmp/pm2-startup-command.txt 2>&1 || true

STARTUP_COMMAND=\$(grep -E '^sudo ' /tmp/pm2-startup-command.txt | tail -n 1 || true)

if [ -n "\$STARTUP_COMMAND" ]; then
    echo "Executing PM2 startup command..."
    eval "\$STARTUP_COMMAND"
else
    echo "PM2 startup may already be configured."
fi

pm2 save

echo "=== PM2 startup configuration completed ==="

EOF

# -------------------------------------------------------
# Application health check
# -------------------------------------------------------

echo ""
echo "======================================================"
echo "🏥 Application Health Check"
echo "======================================================"

sleep 10

sshpass -p "$PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    "${REMOTE_USER}@${SERVER_IP}" << EOF

set -e

echo "=== PM2 Status ==="

pm2 status

echo ""
echo "=== Checking application port ${APP_PORT} ==="

if ! ss -lnt | grep -q ":${APP_PORT} "; then
    echo "❌ Application is not listening on port ${APP_PORT}"
    pm2 logs "${APP_NAME}" --lines 50 --nostream
    exit 1
fi

echo "✅ Application is listening on port ${APP_PORT}"

echo ""
echo "=== HTTP Health Check ==="

if curl -f --max-time 10 \
    "http://127.0.0.1:${APP_PORT}/api/health"; then

    echo ""
    echo "✅ Health check successful"

else

    echo ""
    echo "❌ Health check failed"

    echo ""
    echo "=== PM2 Logs ==="

    pm2 logs "${APP_NAME}" --lines 50 --nostream

    exit 1

fi

EOF

# -------------------------------------------------------
# Deployment complete
# -------------------------------------------------------

echo ""
echo "======================================================"
echo "✅ DEPLOYMENT SUCCESSFUL"
echo "======================================================"
echo "Application : ${APP_NAME}"
echo "Server      : ${SERVER_IP}"
echo "Port        : ${APP_PORT}"
echo "Branch      : ${BRANCH}"
echo "PM2 Name    : ${APP_NAME}"
echo "Health URL  : http://${SERVER_IP}:${APP_PORT}/api/health"
echo "======================================================"