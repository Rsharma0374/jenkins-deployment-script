#!/bin/bash
set -eu

echo "=== Starting Document Utility Web Deployment (Build on Jenkins, Copy build to Server) ==="

PASSWORD="${1:-}"
BRANCH="${2:-}"

SERVER_IP="80.225.218.113"
REMOTE_USER="ubuntu"

REPO_URL="git@github.com:Rsharma0374/document-utility-web.git"
REPO_NAME="document-utility-web"

APP_NAME="document-utility-web"
REMOTE_WEB_DIR="/opt/web/${APP_NAME}"
TMP_DIR="${REMOTE_WEB_DIR}.new"

WORKDIR="${WORKSPACE:-$PWD}"
LOCAL_REPO_DIR="${WORKDIR}/${REPO_NAME}"

if [ -z "$PASSWORD" ] || [ -z "$BRANCH" ]; then
  echo "Usage: $0 <server-password> <branch>"
  exit 1
fi

echo "=== Jenkins: Cloning/Updating repo in workspace ==="
if [ -d "${LOCAL_REPO_DIR}/.git" ]; then
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

echo "=== Jenkins: Detecting build output folder (dist/ or build/) ==="
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

echo "=== Server: Prepare /opt/web dirs (requires sudo) ==="
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "${REMOTE_USER}@${SERVER_IP}" <<EOF
  set -e

  # /opt is root-owned: create dirs with sudo
  sudo mkdir -p "/opt/web"
  sudo mkdir -p "${REMOTE_WEB_DIR}"

  # Create temp dir with sudo, then allow ubuntu to scp into it
  sudo rm -rf "${TMP_DIR}"
  sudo mkdir -p "${TMP_DIR}"
  sudo chown -R ${REMOTE_USER}:${REMOTE_USER} "${TMP_DIR}"

  # Keep final dir writable too (optional)
  sudo chown -R ${REMOTE_USER}:${REMOTE_USER} "${REMOTE_WEB_DIR}"
EOF

echo "=== Jenkins: Upload build output to server temp dir ==="
# Copy CONTENTS of build dir into TMP_DIR (not the folder itself)
sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no -r "${BUILD_DIR}/"* \
  "${REMOTE_USER}@${SERVER_IP}:${TMP_DIR}/"

echo "=== Server: Swap deployment + restart nginx ==="
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "${REMOTE_USER}@${SERVER_IP}" <<EOF
  set -e

  # Swap directories (use sudo because parent is under /opt)
  sudo rm -rf "${REMOTE_WEB_DIR}.bak" || true
  if [ -d "${REMOTE_WEB_DIR}" ]; then
    sudo mv "${REMOTE_WEB_DIR}" "${REMOTE_WEB_DIR}.bak"
  fi
  sudo mv "${TMP_DIR}" "${REMOTE_WEB_DIR}"

  # Ensure nginx can read the files
  sudo chown -R www-data:www-data "${REMOTE_WEB_DIR}" 2>/dev/null || true
  sudo chmod -R a+rX "${REMOTE_WEB_DIR}"

  sudo systemctl restart nginx
  echo "=== Deployment Completed Successfully ==="
EOF

echo "=== Deployment Completed Successfully ==="