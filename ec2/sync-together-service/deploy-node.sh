#!/bin/bash
set -euo pipefail

echo "======================================================"
echo "🚀 Starting Screening Room Node.js Deployment"
echo "    Build on Jenkins, Run on Server with PM2"
echo "======================================================"

# ======================================================
# Jenkins Parameters
# ======================================================

PASSWORD="${1:-}"
BRANCH="${2:-}"
SCAN_VULNERABILITIES="${3:-NO}"

if [ -z "$PASSWORD" ] || [ -z "$BRANCH" ]; then
    echo "❌ Usage:"
    echo "   $0 <server-password> <branch> [YES|NO]"
    exit 1
fi

# ======================================================
# Jenkins Node.js / NVM Configuration
# ======================================================

export NVM_DIR="/var/lib/jenkins/.nvm"

echo ""
echo "======================================================"
echo "🔧 Loading Node.js / NVM"
echo "======================================================"

if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    echo "❌ NVM not found:"
    echo "$NVM_DIR/nvm.sh"
    exit 1
fi

# Load NVM
source "$NVM_DIR/nvm.sh"

# Use Node.js 20
nvm use 20

echo ""
echo "Node version : $(node --version)"
echo "npm version  : $(npm --version)"
echo "Node path    : $(command -v node)"
echo "npm path     : $(command -v npm)"

# ======================================================
# Jenkins Tool Validation
# ======================================================

echo ""
echo "======================================================"
echo "🔍 Checking Jenkins tools"
echo "======================================================"

command -v git >/dev/null 2>&1 || {
    echo "❌ git is not installed"
    exit 1
}

command -v node >/dev/null 2>&1 || {
    echo "❌ node is not available"
    exit 1
}

command -v npm >/dev/null 2>&1 || {
    echo "❌ npm is not available"
    exit 1
}

command -v sshpass >/dev/null 2>&1 || {
    echo "❌ sshpass is not installed"
    exit 1
}

command -v rsync >/dev/null 2>&1 || {
    echo "❌ rsync is not installed"
    exit 1
}

echo "✅ Git     : $(git --version)"
echo "✅ Node.js : $(node --version)"
echo "✅ npm     : $(npm --version)"
echo "✅ sshpass : $(command -v sshpass)"
echo "✅ rsync   : $(command -v rsync)"

# ======================================================
# Server Configuration
# ======================================================

SERVER_IP="140.238.230.44"
REMOTE_USER="opc"

# ======================================================
# Git Configuration
# ======================================================

REPO_URL="git@github.com:Rsharma0374/watch-together.git"
REPO_NAME="watch-together"

# Node application inside repository
APP_SOURCE_DIR="screening-room-backend"

# ======================================================
# Node Application Configuration
# ======================================================

APP_NAME="screening-room-backend"

# IMPORTANT:
# Change this if your Node entry file has another name.
#
# Example:
# NODE_ENTRY="index.js"
# NODE_ENTRY="app.js"
# NODE_ENTRY="server.js"

NODE_ENTRY="server.js"

APP_PORT="8001"

# ======================================================
# Jenkins Workspace
# ======================================================

WORKDIR="${WORKSPACE:-$PWD}"

LOCAL_REPO_DIR="${WORKDIR}/${REPO_NAME}"
LOCAL_APP_DIR="${LOCAL_REPO_DIR}/${APP_SOURCE_DIR}"

# ======================================================
# Remote Application Paths
# ======================================================

REMOTE_APP_DIR="/opt/${APP_NAME}"
REMOTE_LOG_DIR="${REMOTE_APP_DIR}/log"
REMOTE_LOG_FILE="${REMOTE_LOG_DIR}/${APP_NAME}.log"

# ======================================================
# Deployment Information
# ======================================================

echo ""
echo "======================================================"
echo "📋 Deployment Configuration"
echo "======================================================"
echo "Project              : Screening Room Backend"
echo "Repository           : ${REPO_URL}"
echo "Branch               : ${BRANCH}"
echo "Local repository     : ${LOCAL_REPO_DIR}"
echo "Local application    : ${LOCAL_APP_DIR}"
echo "Remote server        : ${SERVER_IP}"
echo "Remote user          : ${REMOTE_USER}"
echo "Remote application   : ${REMOTE_APP_DIR}"
echo "Application name     : ${APP_NAME}"
echo "Node entry           : ${NODE_ENTRY}"
echo "Application port     : ${APP_PORT}"
echo "Vulnerability scan   : ${SCAN_VULNERABILITIES}"
echo "======================================================"

# ======================================================
# Clone / Update Repository
# ======================================================

echo ""
echo "======================================================"
echo "📥 Jenkins: Clone / Update Repository"
echo "======================================================"

if [ -d "${LOCAL_REPO_DIR}/.git" ]; then

    echo "🔄 Existing Git repository found"

    cd "$LOCAL_REPO_DIR"

    echo "📡 Fetching latest branches..."

    git fetch --all --prune

    echo "🌿 Checking out branch: ${BRANCH}"

    git checkout "$BRANCH"

    echo "🔄 Resetting to origin/${BRANCH}"

    git reset --hard "origin/${BRANCH}"

    echo "🧹 Removing untracked files"

    git clean -fd

else

    echo "📥 Repository does not exist"
    echo "Cloning repository..."

    rm -rf "$LOCAL_REPO_DIR"

    git clone "$REPO_URL" "$LOCAL_REPO_DIR"

    cd "$LOCAL_REPO_DIR"

    git checkout "$BRANCH"

fi

echo ""
echo "✅ Repository ready"

echo "Current Git branch:"
git branch --show-current

echo "Current Git commit:"
git rev-parse --short HEAD

# ======================================================
# Validate Application Directory
# ======================================================

echo ""
echo "======================================================"
echo "📁 Validating Node.js Application"
echo "======================================================"

if [ ! -d "$LOCAL_APP_DIR" ]; then

    echo "❌ Application directory not found:"
    echo "$LOCAL_APP_DIR"

    echo ""
    echo "Repository contents:"
    ls -la "$LOCAL_REPO_DIR"

    exit 1
fi

cd "$LOCAL_APP_DIR"

echo "Application directory:"
pwd

echo ""
echo "Application files:"
ls -la

# ======================================================
# Validate package.json
# ======================================================

if [ ! -f "package.json" ]; then
    echo "❌ package.json not found"
    exit 1
fi

echo "✅ package.json found"

# ======================================================
# Validate Node Entry File
# ======================================================

if [ ! -f "$NODE_ENTRY" ]; then

    echo "❌ Node.js entry file not found:"
    echo "$LOCAL_APP_DIR/$NODE_ENTRY"

    echo ""
    echo "Files available:"
    ls -la

    echo ""
    echo "If your entry file is not server.js,"
    echo "change NODE_ENTRY in this script."

    exit 1
fi

echo "✅ Node entry file found:"
echo "$NODE_ENTRY"

# ======================================================
# Install Dependencies on Jenkins
# ======================================================

echo ""
echo "======================================================"
echo "📦 Installing Node.js Dependencies on Jenkins"
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

echo "✅ Jenkins dependencies installed"

# ======================================================
# Vulnerability Scan
# ======================================================

echo ""
echo "======================================================"
echo "🔐 Vulnerability Scan"
echo "======================================================"

if [ "$SCAN_VULNERABILITIES" = "YES" ]; then

    if [ -x "/opt/trivy/trivy-scan.sh" ]; then

        echo "🔍 Running Trivy scan..."

        /opt/trivy/trivy-scan.sh \
            "$LOCAL_APP_DIR" \
            "${APP_NAME}-trivy-report"

        echo "✅ Vulnerability scan completed"

    else

        echo "❌ Trivy script not found:"
        echo "/opt/trivy/trivy-scan.sh"

        exit 1

    fi

else

    echo "⏭️ Vulnerability scanning skipped"

fi

# ======================================================
# Prepare Remote Server
# ======================================================

echo ""
echo "======================================================"
echo "🖥️ Preparing Remote EC2 Server"
echo "======================================================"

sshpass -p "$PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=15 \
    "${REMOTE_USER}@${SERVER_IP}" << EOF

set -e

echo "=============================================="
echo "Connected to ${SERVER_IP}"
echo "=============================================="

echo "Creating application directory..."

sudo mkdir -p "${REMOTE_APP_DIR}"
sudo mkdir -p "${REMOTE_LOG_DIR}"

sudo chown -R "${REMOTE_USER}:${REMOTE_USER}" "${REMOTE_APP_DIR}"

echo "✅ Application directories ready"

EOF

# ======================================================
# Copy Application to Server
# ======================================================

echo ""
echo "======================================================"
echo "📤 Copying Application to EC2"
echo "======================================================"

rsync \
    -az \
    --delete \
    --exclude=".git" \
    --exclude="node_modules" \
    --exclude=".env" \
    --exclude="log" \
    -e "ssh -o StrictHostKeyChecking=no" \
    "${LOCAL_APP_DIR}/" \
    "${REMOTE_USER}@${SERVER_IP}:${REMOTE_APP_DIR}/" \
    2>&1

echo "✅ Application source copied"

# ======================================================
# Remote Node.js / NVM / npm / PM2 Setup
# ======================================================

echo ""
echo "======================================================"
echo "🔧 Configuring Node.js Environment on EC2"
echo "======================================================"

sshpass -p "$PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=15 \
    "${REMOTE_USER}@${SERVER_IP}" << EOF

set -e

echo "=============================================="
echo "🔧 Remote Node.js Environment"
echo "=============================================="

export NVM_DIR="\$HOME/.nvm"

if [ ! -s "\$NVM_DIR/nvm.sh" ]; then

    echo "❌ NVM not found on remote server:"
    echo "\$NVM_DIR/nvm.sh"

    exit 1

fi

source "\$NVM_DIR/nvm.sh"

echo "Available Node versions:"
nvm ls

echo ""
echo "Using Node.js 20..."

nvm use 20

echo ""
echo "Node version:"
node --version

echo "npm version:"
npm --version

echo "Node path:"
command -v node

echo "npm path:"
command -v npm

EOF

# ======================================================
# Install Production Dependencies on Server
# ======================================================

echo ""
echo "======================================================"
echo "📦 Installing Production Dependencies on EC2"
echo "======================================================"

sshpass -p "$PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=15 \
    "${REMOTE_USER}@${SERVER_IP}" << EOF

set -e

export NVM_DIR="\$HOME/.nvm"

source "\$NVM_DIR/nvm.sh"

nvm use 20

cd "${REMOTE_APP_DIR}"

echo "Current directory:"
pwd

echo ""
echo "Installing production dependencies..."

if [ -f package-lock.json ]; then

    echo "package-lock.json found"
    npm ci --omit=dev

else

    echo "package-lock.json not found"
    npm install --omit=dev

fi

echo ""
echo "✅ Production dependencies installed"

EOF

# ======================================================
# PM2 Deployment
# ======================================================

echo ""
echo "======================================================"
echo "🚀 Deploying Application with PM2"
echo "======================================================"

sshpass -p "$PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=15 \
    "${REMOTE_USER}@${SERVER_IP}" << EOF

set -e

export NVM_DIR="\$HOME/.nvm"

source "\$NVM_DIR/nvm.sh"

nvm use 20

cd "${REMOTE_APP_DIR}"

echo "=============================================="
echo "Checking PM2"
echo "=============================================="

if ! command -v pm2 >/dev/null 2>&1; then

    echo "❌ PM2 is not installed"

    echo ""
    echo "Installing PM2..."

    npm install -g pm2

fi

echo ""
echo "PM2 version:"
pm2 --version

echo ""
echo "PM2 path:"
command -v pm2

# --------------------------------------------------
# Stop existing application
# --------------------------------------------------

echo ""
echo "=============================================="
echo "Stopping Existing Application"
echo "=============================================="

pm2 delete "${APP_NAME}" 2>/dev/null || true

# --------------------------------------------------
# Create log directory
# --------------------------------------------------

mkdir -p "${REMOTE_LOG_DIR}"

# --------------------------------------------------
# Start application
# --------------------------------------------------

echo ""
echo "=============================================="
echo "Starting Node.js Application"
echo "=============================================="

export PORT="${APP_PORT}"

pm2 start "${NODE_ENTRY}" \
    --name "${APP_NAME}" \
    --time \
    --update-env \
    --output "${REMOTE_LOG_FILE}" \
    --error "${REMOTE_LOG_FILE}"

# --------------------------------------------------
# Save PM2 process
# --------------------------------------------------

echo ""
echo "=============================================="
echo "Saving PM2 Process"
echo "=============================================="

pm2 save

# --------------------------------------------------
# Show PM2 status
# --------------------------------------------------

echo ""
echo "=============================================="
echo "PM2 Status"
echo "=============================================="

pm2 status

EOF

# ======================================================
# Configure PM2 Startup
# ======================================================

echo ""
echo "======================================================"
echo "⚙️ Configuring PM2 Startup"
echo "======================================================"

sshpass -p "$PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=15 \
    "${REMOTE_USER}@${SERVER_IP}" << EOF

set -e

export NVM_DIR="\$HOME/.nvm"

source "\$NVM_DIR/nvm.sh"

nvm use 20

echo "=============================================="
echo "Configuring PM2 system startup"
echo "=============================================="

# Generate PM2 startup configuration
sudo env PATH="\$PATH" pm2 startup systemd \
    -u "${REMOTE_USER}" \
    --hp "/home/${REMOTE_USER}" \
    > /tmp/pm2-startup.txt 2>&1 || true

echo ""
echo "PM2 startup output:"
cat /tmp/pm2-startup.txt

# Extract and execute the generated sudo command
STARTUP_COMMAND=\$(grep -E '^sudo ' /tmp/pm2-startup.txt | tail -n 1 || true)

if [ -n "\$STARTUP_COMMAND" ]; then

    echo ""
    echo "Executing PM2 startup command..."

    eval "\$STARTUP_COMMAND"

else

    echo ""
    echo "ℹ️ PM2 startup command already configured or not required"

fi

# Save current process list
pm2 save

echo ""
echo "✅ PM2 startup configured"

EOF

# ======================================================
# Wait for Application
# ======================================================

echo ""
echo "======================================================"
echo "⏳ Waiting for Application"
echo "======================================================"

sleep 10

# ======================================================
# Health Check
# ======================================================

echo ""
echo "======================================================"
echo "🏥 Application Health Check"
echo "======================================================"

sshpass -p "$PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=15 \
    "${REMOTE_USER}@${SERVER_IP}" << EOF

set -e

export NVM_DIR="\$HOME/.nvm"

source "\$NVM_DIR/nvm.sh"

nvm use 20

echo "=============================================="
echo "PM2 Status"
echo "=============================================="

pm2 status

echo ""
echo "=============================================="
echo "Checking Port ${APP_PORT}"
echo "=============================================="

if ss -lnt | grep -q ":${APP_PORT} "; then

    echo "✅ Port ${APP_PORT} is listening"

else

    echo "❌ Port ${APP_PORT} is NOT listening"

    echo ""
    echo "=============================================="
    echo "PM2 Logs"
    echo "=============================================="

    pm2 logs "${APP_NAME}" --lines 100 --nostream || true

    exit 1

fi

echo ""
echo "=============================================="
echo "HTTP Health Check"
echo "=============================================="

if curl \
    --fail \
    --silent \
    --show-error \
    --max-time 10 \
    "http://127.0.0.1:${APP_PORT}/api/health"; then

    echo ""
    echo "✅ Application health check successful"

else

    echo ""
    echo "❌ Application health check FAILED"

    echo ""
    echo "=============================================="
    echo "PM2 Logs"
    echo "=============================================="

    pm2 logs "${APP_NAME}" --lines 100 --nostream || true

    exit 1

fi

EOF

# ======================================================
# Deployment Complete
# ======================================================

echo ""
echo "======================================================"
echo "✅ DEPLOYMENT SUCCESSFUL"
echo "======================================================"
echo ""
echo "Application : ${APP_NAME}"
echo "Server      : ${SERVER_IP}"
echo "User        : ${REMOTE_USER}"
echo "Branch      : ${BRANCH}"
echo "Port        : ${APP_PORT}"
echo "PM2 Name    : ${APP_NAME}"
echo "Entry       : ${NODE_ENTRY}"
echo ""
echo "Health URL:"
echo "http://${SERVER_IP}:${APP_PORT}/api/health"
echo ""
echo "Remote logs:"
echo "${REMOTE_LOG_FILE}"
echo ""
echo "======================================================"