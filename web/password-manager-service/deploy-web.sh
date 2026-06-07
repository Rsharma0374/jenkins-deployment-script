#!/bin/bash
set -euo pipefail

echo "=== Starting Password Manager Web Deployment (Build on Jenkins, Copy build to Server) ==="

PASSWORD="${1:-}"
BRANCH="${2:-}"

SERVER_IP="80.225.218.113"
REMOTE_USER="ubuntu"

REPO_URL="git@github.com:Rsharma0374/password-manager-web.git"
REPO_NAME="password-manager-web"

APP_NAME="password-manager-web"
REMOTE_WEB_DIR="/opt/web/${APP_NAME}"

WORKDIR="${WORKSPACE:-$PWD}"
LOCAL_REPO_DIR="${WORKDIR}/${REPO_NAME}"

if [ -z "$PASSWORD" ] || [ -z "$BRANCH" ]; then
  echo "Usage: $0 <server-password> <branch>"
  exit 1
fi

echo "=== Jenkins: Cloning/Updating repo in workspace ==="
if [ -d "$LOCAL_REPO_DIR/.git" ]; then
  git -C "$LOCAL_REPO_DIR" fetch --all
  git -C "$LOCAL_REPO_DIR" reset --hard
  git -C "$LOCAL_REPO_DIR" checkout "$BRANCH"
  git -C "$LOCAL_REPO_DIR" pull origin "$BRANCH"
else
  git clone "$REPO_URL" "$LOCAL_REPO_DIR"
  git -C "$LOCAL_REPO_DIR" checkout "$BRANCH"
fi

echo "=== Jenkins: Install deps + Build ==="
cd "$LOCAL_REPO_DIR"
npm ci
npm run build

# Support either common output folder name: dist/ or build/
BUILD_DIR=""
if [ -d "${LOCAL_REPO_DIR}/dist" ]; then
  BUILD_DIR="${LOCAL_REPO_DIR}/dist"
elif [ -d "${LOCAL_REPO_DIR}/build" ]; then
  BUILD_DIR="${LOCAL_REPO_DIR}/build"
else
  echo "ERROR: Neither dist/ nor build/ found after build."
  exit 1
fi
echo "Build output: ${BUILD_DIR}"

echo "=== Server: Create deploy directory (if missing) ==="
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "${REMOTE_USER}@${SERVER_IP}" <<EOF
  set -e
  sudo mkdir -p "${REMOTE_WEB_DIR}"
  sudo chown -R ${REMOTE_USER}:${REMOTE_USER} "${REMOTE_WEB_DIR}"
EOF

echo "=== Jenkins: Upload build output to server (replace existing) ==="
TMP_DIR="${REMOTE_WEB_DIR}.new"

sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "${REMOTE_USER}@${SERVER_IP}" <<EOF
  set -e
  rm -rf "${TMP_DIR}"
  mkdir -p "${TMP_DIR}"
EOF

sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no -r "${BUILD_DIR}/"* \
  "${REMOTE_USER}@${SERVER_IP}:${TMP_DIR}/"

echo "=== Server: Swap folders + restart nginx ==="
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "${REMOTE_USER}@${SERVER_IP}" <<EOF
  set -e
  rm -rf "${REMOTE_WEB_DIR}.bak" || true
  if [ -d "${REMOTE_WEB_DIR}" ]; then
    mv "${REMOTE_WEB_DIR}" "${REMOTE_WEB_DIR}.bak"
  fi
  mv "${TMP_DIR}" "${REMOTE_WEB_DIR}"

  sudo systemctl restart nginx
  echo "=== Deployment Completed Successfully ==="
EOF

echo "=== Deployment Completed Successfully ==="