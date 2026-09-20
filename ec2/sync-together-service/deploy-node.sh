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

# IMPORTANT:
# Change this if your actual Node.js entry file is different.
#
# Examples:
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

    echo "🧹 Cleaning untracked files"

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

echo "Current branch:"
git branch --show-current

echo ""

echo "Current commit:"
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

    echo "❌ package.json not found:"
    echo "$LOCAL_APP_DIR/package.json"

    exit 1

fi

echo "✅ package.json found"

# ======================================================
# Validate Node.js Entry File
# ======================================================

if [ ! -f "$NODE_ENTRY" ]; then

    echo "❌ Node.js entry file not found:"
    echo "$LOCAL_APP_DIR/$NODE_ENTRY"

    echo ""
    echo "Available files:"

    ls -la

    echo ""
    echo "Please update:"
    echo "NODE_ENTRY=\"server.js\""

    exit 1
fi

echo "✅ Node.js entry file found:"
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

echo ""

sshpass -p "$PASSWORD" rsync \
    -az \
    --delete \
    --exclude=".git" \
    --exclude="node_modules" \
    --exclude=".env" \
    --exclude="log" \
    -e "ssh ${SSH_OPTIONS}" \
    "${LOCAL_APP_DIR}/" \
    "${REMOTE_USER}@${SERVER_IP}:${REMOTE_APP_DIR}/"

echo ""
echo "✅ Application copied successfully"

# ======================================================
# Verify Files on EC2
# ======================================================

echo ""
echo "======================================================"
echo "🔎 Verifying Application on EC2"
echo "======================================================"

sshpass -p "$PASSWORD" ssh \
    $SSH_OPTIONS \
    "${REMOTE_USER}@${SERVER_IP}" << EOF

set -e

cd "${REMOTE_APP_DIR}"

echo "Application directory:"
pwd

echo ""
echo "Application files:"
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
echo "✅ Application files verified"

EOF

# ======================================================
# Load NVM on EC2
# ======================================================

echo ""
echo "======================================================"
echo "🔧 Configuring Node.js on EC2"
echo "======================================================"

sshpass -p "$PASSWORD" ssh \
    $SSH_OPTIONS \
    "${REMOTE_USER}@${SERVER_IP}" << EOF

set -e

export NVM_DIR="\$HOME/.nvm"

if [ ! -s "\$NVM_DIR/nvm.sh" ]; then

    echo "❌ NVM not found on EC2:"
    echo "\$NVM_DIR/nvm.sh"

    echo ""
    echo "Please install NVM for user ${REMOTE_USER}."

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

echo ""
echo "npm version:"
npm --version

echo ""
echo "Node path:"
command -v node

echo ""
echo "npm path:"
command -v npm

EOF

# ======================================================
# Install Production Dependencies on EC2
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
echo "======================================================"

sshpass -p "$PASSWORD" ssh \
    $SSH_OPTIONS \
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

    echo "⚠️ PM2 not installed"

    echo "Installing PM2 globally..."

    npm install -g pm2

fi

echo ""
echo "PM2 version:"
pm2 --version

echo ""
echo "PM2 path:"
command -v pm2

# --------------------------------------------------
# Stop existing application (pm2-tracked)
# --------------------------------------------------

echo ""
echo "=============================================="
echo "Stopping Existing Application"
echo "=============================================="

pm2 delete "${APP_NAME}" 2>/dev/null || true

# --------------------------------------------------
# Forcefully free the port
# --------------------------------------------------
# pm2 delete only stops what PM2 itself is tracking. If a previous
# deploy left an orphaned/zombie node process bound to the port (crash
# loop, manual run, pm2 losing track of the pid, etc.), pm2 delete will
# NOT free it, and the next "pm2 start" fails with EADDRINUSE and
# crash-loops. So explicitly find and kill whatever is actually holding
# the port before starting the new process.

echo ""
echo "=============================================="
echo "Freeing Port ${APP_PORT}"
echo "=============================================="

PORT_PIDS=\$(sudo lsof -t -i :${APP_PORT} 2>/dev/null || true)

if [ -n "\$PORT_PIDS" ]; then

    echo "⚠️ Port ${APP_PORT} is still in use by PID(s): \$PORT_PIDS"
    echo "Process details:"
    sudo lsof -i :${APP_PORT} || true

    echo ""
    echo "Killing PID(s): \$PORT_PIDS"
    sudo kill -9 \$PORT_PIDS || true

    echo "Waiting for port to be released..."
    for i in \$(seq 1 10); do
        if sudo lsof -i :${APP_PORT} >/dev/null 2>&1; then
            sleep 1
        else
            break
        fi
    done

    if sudo lsof -i :${APP_PORT} >/dev/null 2>&1; then
        echo "❌ Port ${APP_PORT} still in use after kill attempt"
        sudo lsof -i :${APP_PORT} || true
        exit 1
    fi

    echo "✅ Port ${APP_PORT} freed"

else

    echo "✅ Port ${APP_PORT} is already free"

fi

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

echo ""
echo "✅ Application started"

# --------------------------------------------------
# Give the process a moment, then confirm it's not crash-looping
# --------------------------------------------------

sleep 3

RESTARTS=\$(pm2 jlist | node -e "
  let d='';
  process.stdin.on('data', c => d += c);
  process.stdin.on('end', () => {
    try {
      const list = JSON.parse(d);
      const proc = list.find(p => p.name === '${APP_NAME}');
      console.log(proc ? proc.pm2_env.restart_time : 0);
    } catch (e) { console.log(0); }
  });
")

if [ "\$RESTARTS" -gt 2 ] 2>/dev/null; then
    echo "❌ Application is crash-looping (restart_time=\$RESTARTS)"
    echo ""
    echo "Recent logs:"
    pm2 logs "${APP_NAME}" --lines 50 --nostream || true
    exit 1
fi

# --------------------------------------------------
# PM2 save
# --------------------------------------------------

echo ""
echo "=============================================="
echo "Saving PM2 Process List"
echo "=============================================="

pm2 save

# --------------------------------------------------
# PM2 status
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
    $SSH_OPTIONS \
    "${REMOTE_USER}@${SERVER_IP}" << EOF

set -e

export NVM_DIR="\$HOME/.nvm"

source "\$NVM_DIR/nvm.sh"

nvm use 20

echo "=============================================="
echo "Configuring PM2 systemd startup"
echo "=============================================="

sudo env PATH="\$PATH" pm2 startup systemd \
    -u "${REMOTE_USER}" \
    --hp "/home/${REMOTE_USER}" \
    > /tmp/pm2-startup.txt 2>&1 || true

echo ""
echo "PM2 startup output:"
cat /tmp/pm2-startup.txt

STARTUP_COMMAND=\$(grep -E '^sudo ' /tmp/pm2-startup.txt | tail -n 1 || true)

if [ -n "\$STARTUP_COMMAND" ]; then

    echo ""
    echo "Executing PM2 startup command..."

    eval "\$STARTUP_COMMAND"

else

    echo ""
    echo "ℹ️ PM2 startup already configured or no command generated"

fi

echo ""
echo "Saving PM2 process list..."

pm2 save

echo ""
echo "✅ PM2 startup configured"

EOF

# ======================================================
# Wait for Application
# ======================================================

echo ""
echo "======================================================"
echo "⏳ Waiting for Application Startup"
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
    $SSH_OPTIONS \
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
    echo ""
    echo "Process bound to port ${APP_PORT}:"
    sudo lsof -i :${APP_PORT} || true

else

    echo "❌ Port ${APP_PORT} is NOT listening"

    echo ""
    echo "=============================================="
    echo "PM2 Logs"
    echo "=============================================="

    pm2 logs "${APP_NAME}" \
        --lines 100 \
        --nostream || true

    exit 1

fi

# ==================================================
# HTTP Health Check
# ==================================================

echo ""
echo "=============================================="
echo "HTTP Health Check"
echo "=============================================="

HEALTH_URL="http://127.0.0.1:${APP_PORT}/api/health"

echo "Checking:"
echo "\$HEALTH_URL"

if curl \
    --fail \
    --silent \
    --show-error \
    --max-time 10 \
    "\$HEALTH_URL"; then

    echo ""
    echo ""
    echo "✅ Application health check successful"

else

    echo ""
    echo "❌ Application health check FAILED"
    echo ""
    echo "Note: if this returned 404 (not a connection error/timeout),"
    echo "port ${APP_PORT} is being served by something OTHER than this"
    echo "app (e.g. a leftover process, or another service on this host"
    echo "that happens to share the port). Check the lsof output above"
    echo "against the PM2-reported pid for ${APP_NAME}."

    echo ""
    echo "=============================================="
    echo "PM2 Logs"
    echo "=============================================="

    pm2 logs "${APP_NAME}" \
        --lines 100 \
        --nostream || true

    exit 1

fi

EOF

# ======================================================
# Final Deployment Status
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
echo "Node Entry  : ${NODE_ENTRY}"

echo ""
echo "Health URL:"
echo "http://${SERVER_IP}:${APP_PORT}/api/health"

echo ""
echo "Remote Log:"
echo "${REMOTE_LOG_FILE}"

echo ""
echo "======================================================"
echo "🎉 Screening Room deployment completed"
echo "======================================================"