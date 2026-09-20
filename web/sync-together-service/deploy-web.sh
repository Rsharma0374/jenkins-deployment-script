#!/bin/bash
set -eu

echo "======================================================"
echo "🚀 Starting Screening Room Frontend Deployment"
echo "    Build on Jenkins, Copy build to Server (nginx)"
echo "======================================================"

# ======================================================
# Jenkins Parameters
# ======================================================

PASSWORD="${1:-}"
BRANCH="${2:-}"
SCAN_VULNERABILITIES="${3:-NO}"

if [ -z "$PASSWORD" ] || [ -z "$BRANCH" ]; then
  echo "Usage: $0 <server-password> <branch> [YES|NO]"
  exit 1
fi

# ======================================================
# Git Configuration
# ======================================================
# watch-together is a monorepo: this script only cares about the
# frontend project inside it (screening-room-frontend-react). The
# backend (screening-room-backend) is deployed by a separate script.

REPO_URL="git@github.com:Rsharma0374/watch-together.git"
REPO_NAME="watch-together"

# React/Vite project inside the repository
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

SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15"

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
  echo "🔄 Existing repository found, updating..."
  git -C "$LOCAL_REPO_DIR" fetch --all --prune
  git -C "$LOCAL_REPO_DIR" checkout "$BRANCH"
  git -C "$LOCAL_REPO_DIR" reset --hard "origin/${BRANCH}"
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
  echo "❌ Project directory not found: ${LOCAL_APP_DIR}"
  echo ""
  echo "Repository contents:"
  ls -la "$LOCAL_REPO_DIR"
  exit 1
fi

cd "$LOCAL_APP_DIR"

if [ ! -f "package.json" ]; then
  echo "❌ package.json not found in ${LOCAL_APP_DIR}"
  exit 1
fi

echo "✅ Project found: ${LOCAL_APP_DIR}"
ls -la

# ======================================================
# Install Dependencies
# ======================================================

echo ""
echo "======================================================"
echo "📦 Installing Dependencies"
echo "======================================================"

if [ -f "package-lock.json" ]; then
  echo "Running: npm ci"
  npm ci
else
  echo "⚠️ package-lock.json not found, running: npm install"
  npm install
fi

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
    echo "❌ Trivy script not found: /opt/trivy/trivy-scan.sh"
    exit 1
  fi

  echo "🔍 Running Trivy scan on ${LOCAL_APP_DIR}..."
  # Runs after npm ci (so node_modules exists to scan) and before the
  # build, so a bad scan fails fast without wasting a build.
  /opt/trivy/trivy-scan.sh \
    "$LOCAL_APP_DIR" \
    "${APP_NAME}-trivy-report"

  echo "✅ Vulnerability scan completed"

else
  echo "⏭️ Vulnerability scanning skipped"
fi

# ======================================================
# Build
# ======================================================
# .env / .env.production is already committed in the repo, so no
# Jenkins step is needed to generate it — Vite will pick it up
# automatically for a production build.

echo ""
echo "======================================================"
echo "🏗️ Building Frontend"
echo "======================================================"

npm run build

echo ""
echo "======================================================"
echo "📂 Detecting Build Output Folder (dist/ or build/)"
echo "======================================================"

BUILD_DIR=""
if [ -d "${LOCAL_APP_DIR}/dist" ]; then
  BUILD_DIR="${LOCAL_APP_DIR}/dist"
elif [ -d "${LOCAL_APP_DIR}/build" ]; then
  BUILD_DIR="${LOCAL_APP_DIR}/build"
else
  echo "❌ Neither dist/ nor build/ found after build."
  exit 1
fi

echo "Build output: ${BUILD_DIR}"
ls -la "$BUILD_DIR"

# ======================================================
# Prepare Remote Server
# ======================================================

echo ""
echo "======================================================"
echo "🖥️ Server: Preparing /opt/web dirs (requires sudo)"
echo "======================================================"

sshpass -p "$PASSWORD" ssh $SSH_OPTIONS "${REMOTE_USER}@${SERVER_IP}" <<EOF
set -e

sudo mkdir -p "/opt/web"
sudo mkdir -p "${REMOTE_WEB_DIR}"

# Create temp dir with sudo, then allow ${REMOTE_USER} to scp into it
sudo rm -rf "${TMP_DIR}"
sudo mkdir -p "${TMP_DIR}"
sudo chown -R ${REMOTE_USER}:${REMOTE_USER} "${TMP_DIR}"
sudo chown -R ${REMOTE_USER}:${REMOTE_USER} "${REMOTE_WEB_DIR}"

echo "✅ Remote directories ready"
EOF

# ======================================================
# Upload Build Output
# ======================================================

echo ""
echo "======================================================"
echo "📤 Uploading Build Output to Server Temp Dir"
echo "======================================================"

# Copy CONTENTS of build dir into TMP_DIR (not the folder itself)
sshpass -p "$PASSWORD" scp $SSH_OPTIONS -r "${BUILD_DIR}/"* \
  "${REMOTE_USER}@${SERVER_IP}:${TMP_DIR}/"

echo "✅ Upload complete"

# ======================================================
# Swap Deployment + Restart nginx
# ======================================================

echo ""
echo "======================================================"
echo "🔁 Server: Swapping Deployment + Restarting nginx"
echo "======================================================"

sshpass -p "$PASSWORD" ssh $SSH_OPTIONS "${REMOTE_USER}@${SERVER_IP}" <<EOF
set -e

sudo rm -rf "${REMOTE_WEB_DIR}.bak" || true
if [ -d "${REMOTE_WEB_DIR}" ]; then
  sudo mv "${REMOTE_WEB_DIR}" "${REMOTE_WEB_DIR}.bak"
fi
sudo mv "${TMP_DIR}" "${REMOTE_WEB_DIR}"

# Ensure nginx can read the files
sudo chown -R www-data:www-data "${REMOTE_WEB_DIR}" 2>/dev/null || true
sudo chmod -R a+rX "${REMOTE_WEB_DIR}"

sudo systemctl restart nginx

echo "✅ nginx restarted"
EOF

echo ""
echo "======================================================"
echo "✅ DEPLOYMENT SUCCESSFUL"
echo "======================================================"
echo "Application : ${APP_NAME}"
echo "Server      : ${SERVER_IP}"
echo "User        : ${REMOTE_USER}"
echo "Branch      : ${BRANCH}"
echo "Remote dir  : ${REMOTE_WEB_DIR}"
echo "======================================================"
echo "🎉 Screening Room frontend deployment completed"
echo "======================================================"