#!/bin/bash
set -euo pipefail

echo "======================================================"
echo "🚀 Starting Screening Room Frontend Deployment"
echo "    Build on Jenkins, Copy Build to Server (nginx)"
echo "======================================================"

# ======================================================
# Jenkins Parameters
# ======================================================

PASSWORD="${1:-}"
BRANCH="${2:-}"
SCAN_VULNERABILITIES="${3:-NO}"

if [ -z "$PASSWORD" ] || [ -z "$BRANCH" ]; then
    echo ""
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

if ! command -v scp >/dev/null 2>&1; then
    echo "❌ scp is not installed"
    exit 1
fi

echo "✅ Git     : $(git --version)"
echo "✅ Node.js : $(node --version)"
echo "✅ npm     : $(npm --version)"
echo "✅ sshpass : $(command -v sshpass)"
echo "✅ scp     : $(command -v scp)"

# ======================================================
# Git Configuration
# ======================================================

REPO_URL="git@github.com:Rsharma0374/watch-together.git"
REPO_NAME="watch-together"

# React/Vite project inside monorepo
APP_SOURCE_DIR="screening-room-frontend-react"

# ======================================================
# Application Configuration
# ======================================================

APP_NAME="screening-room-frontend-react"

# ======================================================
# EC2 Server Configuration
# ======================================================

SERVER_IP="130.210.44.155"
REMOTE_USER="ubuntu"

REMOTE_WEB_DIR="/opt/web/${APP_NAME}"
TMP_DIR="${REMOTE_WEB_DIR}.new"

# ======================================================
# Jenkins Workspace
# ======================================================

WORKDIR="${WORKSPACE:-$PWD}"

LOCAL_REPO_DIR="${WORKDIR}/${REPO_NAME}"
LOCAL_APP_DIR="${LOCAL_REPO_DIR}/${APP_SOURCE_DIR}"

# ======================================================
# SSH Configuration
# ======================================================

SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -o PreferredAuthentications=password -o PubkeyAuthentication=no"

# ======================================================
# Deployment Configuration
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
echo "Remote web dir      : ${REMOTE_WEB_DIR}"
echo "Application name    : ${APP_NAME}"
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

    echo "🔄 Existing repository found"

    git -C "$LOCAL_REPO_DIR" fetch --all --prune

    echo "🌿 Checking out branch: ${BRANCH}"

    git -C "$LOCAL_REPO_DIR" checkout "$BRANCH"

    echo "🔄 Resetting to origin/${BRANCH}"

    git -C "$LOCAL_REPO_DIR" reset --hard "origin/${BRANCH}"

    echo "🧹 Cleaning untracked files"

    git -C "$LOCAL_REPO_DIR" clean -fd

else

    echo "📥 Cloning repository..."

    rm -rf "$LOCAL_REPO_DIR"

    git clone "$REPO_URL" "$LOCAL_REPO_DIR"

    git -C "$LOCAL_REPO_DIR" checkout "$BRANCH"

fi

echo ""
echo "Current branch:"
git -C "$LOCAL_REPO_DIR" branch --show-current

echo ""
echo "Current commit:"
git -C "$LOCAL_REPO_DIR" rev-parse --short HEAD

# ======================================================
# Validate Frontend Project Directory
# ======================================================

echo ""
echo "======================================================"
echo "📁 Validating Frontend Project"
echo "======================================================"

if [ ! -d "$LOCAL_APP_DIR" ]; then

    echo "❌ Project directory not found:"
    echo "$LOCAL_APP_DIR"

    echo ""
    echo "Repository contents:"
    ls -la "$LOCAL_REPO_DIR"

    exit 1
fi

cd "$LOCAL_APP_DIR"

echo "Frontend directory:"
pwd

echo ""
echo "Frontend files:"
ls -la

# ======================================================
# Validate package.json
# ======================================================

if [ ! -f "package.json" ]; then

    echo "❌ package.json not found:"
    echo "$LOCAL_APP_DIR/package.json"

    exit 1

fi

echo "✅ package.json found"

# ======================================================
# Install Dependencies
# ======================================================

echo ""
echo "======================================================"
echo "📦 Installing Dependencies"
echo "======================================================"

echo "Node version:"
node --version

echo "npm version:"
npm --version

if [ -f "package-lock.json" ]; then

    echo ""
    echo "📦 package-lock.json found"

    echo "Running:"
    echo "npm ci"

    npm ci

else

    echo ""
    echo "⚠️ package-lock.json not found"

    echo "Running:"
    echo "npm install"

    npm install

fi

echo ""
echo "✅ Dependencies installed"

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

    echo ""
    echo "✅ Vulnerability scan completed"

else

    echo "⏭️ Vulnerability scanning skipped"

fi

# ======================================================
# Build Frontend
# ======================================================

echo ""
echo "======================================================"
echo "🏗️ Building Frontend"
echo "======================================================"

echo "Node version:"
node --version

echo "npm version:"
npm --version

echo ""
echo "Running:"
echo "npm run build"

npm run build

echo ""
echo "✅ Frontend build completed"

# ======================================================
# Detect Build Output
# ======================================================

echo ""
echo "======================================================"
echo "📂 Detecting Build Output"
echo "======================================================"

BUILD_DIR=""

if [ -d "${LOCAL_APP_DIR}/dist" ]; then

    BUILD_DIR="${LOCAL_APP_DIR}/dist"

elif [ -d "${LOCAL_APP_DIR}/build" ]; then

    BUILD_DIR="${LOCAL_APP_DIR}/build"

else

    echo "❌ Neither dist/ nor build/ found after build"

    echo ""
    echo "Application directory:"
    ls -la "$LOCAL_APP_DIR"

    exit 1

fi

echo "Build output:"
echo "$BUILD_DIR"

echo ""
echo "Build contents:"
ls -la "$BUILD_DIR"

# ======================================================
# Test SSH Connection
# ======================================================

echo ""
echo "======================================================"
echo "🔐 Testing SSH Connection to EC2"
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
echo "🖥️ Preparing Remote Web Directories"
echo "======================================================"

sshpass -p "$PASSWORD" ssh \
    $SSH_OPTIONS \
    "${REMOTE_USER}@${SERVER_IP}" << EOF

set -e

echo "=============================================="
echo "Connected to ${SERVER_IP}"
echo "=============================================="

echo ""
echo "Creating /opt/web..."

sudo mkdir -p "/opt/web"

echo ""
echo "Creating application directory..."

sudo mkdir -p "${REMOTE_WEB_DIR}"

echo ""
echo "Removing previous temporary directory..."

sudo rm -rf "${TMP_DIR}"

echo ""
echo "Creating temporary directory..."

sudo mkdir -p "${TMP_DIR}"

echo ""
echo "Setting temporary directory ownership..."

sudo chown -R "${REMOTE_USER}:${REMOTE_USER}" "${TMP_DIR}"

sudo chown -R "${REMOTE_USER}:${REMOTE_USER}" "${REMOTE_WEB_DIR}"

echo ""
echo "Application directory:"
ls -ld "${REMOTE_WEB_DIR}"

echo ""
echo "Temporary directory:"
ls -ld "${TMP_DIR}"

echo ""
echo "✅ Remote directories ready"

EOF

# ======================================================
# Upload Build Output
# ======================================================

echo ""
echo "======================================================"
echo "📤 Uploading Frontend Build to EC2"
echo "======================================================"

echo "Source:"
echo "${BUILD_DIR}/"

echo ""
echo "Destination:"
echo "${REMOTE_USER}@${SERVER_IP}:${TMP_DIR}/"

echo ""

sshpass -p "$PASSWORD" scp \
    $SSH_OPTIONS \
    -r \
    "${BUILD_DIR}/." \
    "${REMOTE_USER}@${SERVER_IP}:${TMP_DIR}/"

echo ""
echo "✅ Upload complete"

# ======================================================
# Verify Uploaded Files
# ======================================================

echo ""
echo "======================================================"
echo "🔎 Verifying Uploaded Files"
echo "======================================================"

sshpass -p "$PASSWORD" ssh \
    $SSH_OPTIONS \
    "${REMOTE_USER}@${SERVER_IP}" << EOF

set -e

echo "Temporary deployment directory:"
ls -la "${TMP_DIR}"

if [ -z "\$(ls -A "${TMP_DIR}")" ]; then

    echo "❌ Temporary deployment directory is empty"

    exit 1

fi

echo ""
echo "✅ Build files successfully uploaded"

EOF

# ======================================================
# Swap Deployment
# ======================================================

echo ""
echo "======================================================"
echo "🔁 Swapping Frontend Deployment"
echo "======================================================"

sshpass -p "$PASSWORD" ssh \
    $SSH_OPTIONS \
    "${REMOTE_USER}@${SERVER_IP}" << EOF

set -e

echo "=============================================="
echo "Preparing backup"
echo "=============================================="

sudo rm -rf "${REMOTE_WEB_DIR}.bak"

if [ -d "${REMOTE_WEB_DIR}" ]; then

    sudo mv \
        "${REMOTE_WEB_DIR}" \
        "${REMOTE_WEB_DIR}.bak"

fi

echo ""
echo "Moving new deployment into place..."

sudo mv \
    "${TMP_DIR}" \
    "${REMOTE_WEB_DIR}"

echo ""
echo "Setting nginx ownership..."

sudo chown -R www-data:www-data \
    "${REMOTE_WEB_DIR}" 2>/dev/null || true

echo ""
echo "Setting read permissions..."

sudo chmod -R a+rX \
    "${REMOTE_WEB_DIR}"

echo ""
echo "Deployment directory:"
ls -la "${REMOTE_WEB_DIR}"

echo ""
echo "=============================================="
echo "Testing nginx configuration"
echo "=============================================="

sudo nginx -t

echo ""
echo "=============================================="
echo "Restarting nginx"
echo "=============================================="

sudo systemctl restart nginx

echo ""
echo "Checking nginx status..."

sudo systemctl is-active --quiet nginx

echo ""
echo "✅ nginx is running"

EOF

# ======================================================
# Optional HTTP Verification
# ======================================================

echo ""
echo "======================================================"
echo "🌐 nginx Verification"
echo "======================================================"

sshpass -p "$PASSWORD" ssh \
    $SSH_OPTIONS \
    "${REMOTE_USER}@${SERVER_IP}" << EOF

set -e

echo "Checking nginx process..."

if sudo systemctl is-active --quiet nginx; then

    echo "✅ nginx is active"

else

    echo "❌ nginx is not active"

    sudo systemctl status nginx --no-pager || true

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
echo "Build       : ${BUILD_DIR}"
echo "Remote dir  : ${REMOTE_WEB_DIR}"

echo ""
echo "======================================================"
echo "🎉 Screening Room frontend deployment completed"
echo "======================================================"