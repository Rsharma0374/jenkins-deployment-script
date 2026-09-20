#!/bin/bash
set -euo pipefail

echo "======================================================"
echo "🚀 Starting Screening Room Node.js Deployment"
echo "    Build on Jenkins, Run on EC2 with PM2"
echo "======================================================"

# ======================================================
# Jenkins Parameters
# ======================================================

PASSWORD="${1:-}"
BRANCH="${2:-}"
SCAN_VULNERABILITIES="${3:-NO}"

if [ -z "$PASSWORD" ] || [ -z "$BRANCH" ]; then
    echo "❌ Missing required parameters"
    echo ""
    echo "Usage:"
    echo "  $0 <server-password> <branch> [YES|NO]"
    echo ""
    exit 1
fi

# ======================================================
# Jenkins NVM / Node.js Configuration
# ======================================================

export NVM_DIR="/var/lib/jenkins/.nvm"

echo ""
echo "======================================================"
echo "🔧 Loading Node.js / NVM on Jenkins"
echo "======================================================"

if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    echo "❌ NVM not found:"
    echo "$NVM_DIR/nvm.sh"
    exit 1
fi

source "$NVM_DIR/nvm.sh"

echo "Using Node.js 20..."

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
echo "🔍 Checking Jenkins Tools"
echo "======================================================"

if ! command -v git >/dev/null 2>&1; then
    echo "❌ git is not installed"
    exit 1
fi

if ! command -v node >/dev/null 2>&1; then
    echo "❌ node is not available"
    exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
    echo "❌ npm is not available"
    exit 1
fi

if ! command -v sshpass >/dev/null 2>&1; then
    echo "❌ sshpass is not installed"
    exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
    echo "❌ rsync is not installed"
    exit 1
fi

echo "✅ Git     : $(git --version)"
echo "✅ Node.js : $(node --version)"
echo "✅ npm     : $(npm --version)"
echo "✅ sshpass : $(command -v sshpass)"
echo "✅ rsync   : $(rsync --version | head -n 1)"

# ======================================================
# EC2 Server Configuration
# ======================================================

SERVER_IP="140.238.230.44"
REMOTE_USER="opc"

# ======================================================
# Git Configuration
# ======================================================

REPO_URL="git@github.com:Rsharma0374/watch-together.git"
REPO_NAME="watch-together"

# Node.js project inside repository
APP_SOURCE_DIR="screening-room-backend"

# ======================================================
# Application Configuration
# ======================================================

APP_NAME="screening-room-backend"
NODE_ENTRY="server.js"
APP_PORT="8001"

# ======================================================
# Jenkins Workspace
# ======================================================

WORKDIR="${WORKSPACE:-$PWD}"

LOCAL_REPO_DIR="${WORKDIR}/${REPO_NAME}"
LOCAL_APP_DIR="${LOCAL_REPO_DIR}/${APP_SOURCE_DIR}"

# ======================================================
# Remote Application Configuration
# ======================================================

REMOTE_APP_DIR="/opt/${APP_NAME}"
REMOTE_LOG_DIR="${REMOTE_APP_DIR}/log"
REMOTE_LOG_FILE="${REMOTE_LOG_DIR}/${APP_NAME}.log"

# ======================================================
# SSH Configuration
# ======================================================

SSH_OPTIONS="\
-o StrictHostKeyChecking=no \
-o UserKnownHostsFile=/dev/null \
-o PreferredAuthentications=password \
-o PubkeyAuthentication=no \
-o ConnectTimeout=15"

# ======================================================
# Deployment Information
# ======================================================

echo ""
echo "======================================================"
echo "📋 Deployment Configuration"
echo "======================================================"

echo "Repository          : ${REPO_URL}"
echo "Branch              : ${BRANCH}"
echo "Local repository    : ${LOCAL_REPO_DIR}"
echo "Local application   : ${LOCAL_APP_DIR}"
echo "Remote server       : ${SERVER_IP}"
echo "Remote user         : ${REMOTE_USER}"
echo "Remote application  : ${REMOTE_APP_DIR}"
echo "Application name    : ${APP_NAME}"
echo "Node entry          : ${NODE_ENTRY}"
echo "Application port    : ${APP_PORT}"
echo "Vulnerability scan  : ${SCAN_VULNERABILITIES}"

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

    echo "📡 Fetching latest changes..."
    git fetch --all --prune

    echo "🌿 Checking out branch: ${BRANCH}"
    git checkout "$BRANCH"

    echo "🔄 Resetting to origin/${BRANCH}"
    git reset --hard "origin/${BRANCH}"

else

    echo "📦 Cloning fresh repository..."
    git clone --branch "$BRANCH" "$REPO_URL" "$LOCAL_REPO_DIR"

    cd "$LOCAL_REPO_DIR"

fi

echo ""
echo "✅ Repository ready"

# ======================================================
# Validating Node.js Application
# ======================================================

echo ""
echo "======================================================"
echo "🧪 Validating Node.js Application"
echo "======================================================"

if [ ! -d "${LOCAL_APP_DIR}" ]; then
    echo "❌ Application directory not found:"
    echo "${LOCAL_APP_DIR}"
    exit 1
fi

cd "${LOCAL_APP_DIR}"

echo "Application directory:"
pwd

echo ""
echo "Contents:"
ls -la

# ======================================================
# Validate package.json
# ======================================================

echo ""
echo "======================================================"
echo "📄 Validate package.json"
echo "======================================================"

if [ ! -f "package.json" ]; then
    echo "❌ package.json not found in:"
    echo "${LOCAL_APP_DIR}"
    exit 1
fi

echo "✅ package.json found"

# ======================================================
# Validate Node.js Entry File
# ======================================================

echo ""
echo "======================================================"
echo "📄 Validate Node.js Entry File"
echo "======================================================"

if [ ! -f "${NODE_ENTRY}" ]; then
    echo "❌ Node entry file not found:"
    echo "${LOCAL_APP_DIR}/${NODE_ENTRY}"
    exit 1
fi

echo "✅ Entry file found: ${NODE_ENTRY}"

# ======================================================
# Install Dependencies on Jenkins
# ======================================================

echo ""
echo "======================================================"
echo "📦 Install Dependencies on Jenkins"
echo "======================================================"

if [ -f "package-lock.json" ]; then

    echo "📦 package-lock.json found"
    echo "Running:"
    echo "npm ci"

    npm ci

else

    echo "⚠️ package-lock.json not found"
    echo "Running:"
    echo "npm install"

    npm install

fi

echo ""
echo "✅ Jenkins dependencies installed"

# ======================================================
# Vulnerability Scan
# ======================================================

echo ""
echo "======================================================"
echo "🔐 Vulnerability Scan"
echo "======================================================"

if [ "$SCAN_VULNERABILITIES" = "YES" ]; then

    if [ ! -x "/opt/trivy/trivy-scan.sh" ]; then

        echo "❌ Trivy script not found:"
        echo "/opt/trivy/trivy-scan.sh"

        exit 1

    fi

    echo "🔍 Running Trivy scan..."

    /opt/trivy/trivy-scan.sh \
        "$LOCAL_APP_DIR" \
        "${APP_NAME}-trivy-report"

    echo "✅ Vulnerability scan completed"

else

    echo "⏭️ Vulnerability scanning skipped"

fi

# ======================================================
# Test SSH Connection
# ======================================================

echo ""
echo "======================================================"
echo "🔐 Testing EC2 SSH Connection"
echo "======================================================"

sshpass -p "$PASSWORD" ssh \
    $SSH_OPTIONS \
    "${REMOTE_USER}@${SERVER_IP}" \
    "echo '✅ SSH connection successful'"

# ======================================================
# Prepare Remote Server
# ======================================================

echo ""
echo "======================================================"
echo "🖥️ Preparing EC2 Server"
echo "======================================================"

sshpass -p "$PASSWORD" ssh \
    $SSH_OPTIONS \
    "${REMOTE_USER}@${SERVER_IP}" << EOF

set -e

echo "=============================================="
echo "Connected to ${SERVER_IP}"
echo "=============================================="

echo ""
echo "Creating application directory..."

sudo mkdir -p "${REMOTE_APP_DIR}"
sudo mkdir -p "${REMOTE_LOG_DIR}"
sudo chown -R "${REMOTE_USER}:${REMOTE_USER}" "${REMOTE_APP_DIR}"

echo ""
echo "Application directory:"
ls -ld "${REMOTE_APP_DIR}"

echo ""
echo "Log directory:"
ls -ld "${REMOTE_LOG_DIR}"

echo ""
echo "✅ Remote directories ready"

EOF

# ======================================================
# Copy Application to EC2
# ======================================================

echo ""
echo "======================================================"
echo "📤 Copying Application to EC2"
echo "======================================================"

echo "Source:"
echo "${LOCAL_APP_DIR}/"

echo "Destination:"
echo "${REMOTE_USER}@${SERVER_IP}:${REMOTE_APP_DIR}/"

rsync -avz --delete \
    -e "ssh $SSH_OPTIONS" \
    "${LOCAL_APP_DIR}/" \
    "${REMOTE_USER}@${SERVER_IP}:${REMOTE_APP_DIR}/"

echo ""
echo "✅ Application copied to EC2"

# ======================================================
# Verify Files on EC2
# ======================================================

echo ""
echo "======================================================"
echo "🔎 Verifying Application Files on EC2"
echo "======================================================"

sshpass -p "$PASSWORD" ssh \
    $SSH_OPTIONS \
    "${REMOTE_USER}@${SERVER_IP}" << EOF

set -e

cd "${REMOTE_APP_DIR}"

echo "Current directory:"
pwd

echo ""
echo "Files:"
ls -la

if [ ! -f "package.json" ]; then
    echo "❌ package.json missing on EC2"
    exit 1
fi

if [ ! -f "${NODE_ENTRY}" ]; then
    echo "❌ ${NODE_ENTRY} missing on EC2"
    exit 1
fi

echo ""
echo "✅ Required files verified on EC2"

EOF

# ======================================================
# EC2 Node.js / NVM Validation
# ======================================================

echo ""
echo "======================================================"
echo "🔧 Validating Node.js / NVM on EC2"
echo "======================================================"

sshpass -p "$PASSWORD" ssh \
    $SSH_OPTIONS \
    "${REMOTE_USER}@${SERVER_IP}" << EOF

set -e

export NVM_DIR="\$HOME/.nvm"

if [ ! -s "\$NVM_DIR/nvm.sh" ]; then
    echo "❌ NVM not found on EC2:"
    echo "\$NVM_DIR/nvm.sh"
    exit 1
fi

source "\$NVM_DIR/nvm.sh"

nvm use 20

echo "Node version : \$(node --version)"
echo "npm version  : \$(npm --version)"
echo "Node path    : \$(command -v node)"
echo "npm path     : \$(command -v npm)"

EOF

# ======================================================
# Installing Production Dependencies on EC2
# ======================================================

echo ""
echo "======================================================"
echo "📦 Installing Production Dependencies on EC2"
echo "======================================================"

sshpass -p "$PASSWORD" ssh \
    $SSH_OPTIONS \
    "${REMOTE_USER}@${SERVER_IP}" << EOF

set -e

export NVM_DIR="\$HOME/.nvm"
source "\$NVM_DIR/nvm.sh"

nvm use 20

cd "${REMOTE_APP_DIR}"

echo "Current directory:"
pwd

echo ""

if [ -f "package-lock.json" ]; then

    echo "📦 package-lock.json found"

    echo "Running:"
    echo "npm ci --omit=dev"

    npm ci --omit=dev

else

    echo "⚠️ package-lock.json not found"

    echo "Running:"
    echo "npm install --omit=dev"

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
echo "🚀 Starting Application with PM2"
