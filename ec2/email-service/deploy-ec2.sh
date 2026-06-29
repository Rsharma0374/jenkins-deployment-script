#!/bin/bash
set -euo pipefail

echo "=== Starting Email Connector Service Deployment (Build on Jenkins, Run on Server) ==="

PASSWORD="${1:-}"
BRANCH="${2:-}"

SERVER_IP="80.225.218.113"
REMOTE_USER="ubuntu"

REPO_URL="git@github.com:Rsharma0374/emailConnecter-core.git"
REPO_NAME="emailConnecter-core"

APP_NAME="email-connector-service"
APP_PORT="10002"

# Jenkins workspace paths
WORKDIR="${WORKSPACE:-$PWD}"
LOCAL_REPO_DIR="${WORKDIR}/${REPO_NAME}"
LOCAL_JAR_GLOB="${LOCAL_REPO_DIR}/target/*.jar"

# Remote paths (JAR + logs in same folder)
REMOTE_APP_DIR="/opt/${APP_NAME}"
REMOTE_JAR_PATH="${REMOTE_APP_DIR}/${APP_NAME}.jar"
REMOTE_LOG_FILE="${REMOTE_APP_DIR}/${APP_NAME}.log"

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

echo "=== Jenkins: Building JAR with Maven ==="
cd "$LOCAL_REPO_DIR"
mvn -B clean package -DskipTests -Pprod

echo "=== Jenkins: Locating built JAR ==="
JAR_FILE="$(ls -1 $LOCAL_JAR_GLOB | head -n 1)"
if [ -z "${JAR_FILE:-}" ] || [ ! -f "$JAR_FILE" ]; then
  echo "ERROR: No JAR found at ${LOCAL_JAR_GLOB}"
  exit 1
fi
echo "Built JAR: $JAR_FILE"

echo "=== Server: Creating ${REMOTE_APP_DIR} and setting permissions ==="
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "${REMOTE_USER}@${SERVER_IP}" << EOF
  set -e
  sudo mkdir -p "${REMOTE_APP_DIR}"
  sudo chown -R ${REMOTE_USER}:${REMOTE_USER} "${REMOTE_APP_DIR}"
EOF

echo "=== Jenkins: Copying JAR to server (${REMOTE_JAR_PATH}) ==="
sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no "$JAR_FILE" "${REMOTE_USER}@${SERVER_IP}:${REMOTE_JAR_PATH}"

echo "=== Server: Stopping old app and starting new one ==="
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "${REMOTE_USER}@${SERVER_IP}" << EOF
  set -e
  echo "=== Connected to Server (${SERVER_IP}) ==="

  echo "=== Stopping existing app on port ${APP_PORT} ==="
  PID=\$(lsof -t -i:${APP_PORT} || true)
  if [ -n "\$PID" ]; then
    echo "Killing PID \$PID"
    kill -9 "\$PID" || true
  fi

  echo "=== Starting app from ${REMOTE_JAR_PATH} ==="
  cd "${REMOTE_APP_DIR}"

  # Log file lives in the same folder as the JAR
  nohup java -jar "${REMOTE_JAR_PATH}" -DHOSTNAME="$HOSTNAME" --server.port=${APP_PORT} >> "${REMOTE_LOG_FILE}" 2>&1 &

  echo "=== Waiting for app to boot ==="
  sleep 20

  echo "=== Health Check ==="
  curl -f "http://127.0.0.1:${APP_PORT}/" || echo "Health check failed"

  echo "=== Deployment Finished on Server ==="
EOF

echo "=== Deployment Completed Successfully ==="