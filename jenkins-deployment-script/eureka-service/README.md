# Eureka Service Deployment

This directory contains deployment scripts for the Eureka Service Registry across two different server environments.

## Server Architecture

- **Server 1**: Jenkins server with direct deployment
- **Server 2**: Kubernetes server with Docker and K8s deployment

## Files Overview

### Server 1 (Jenkins Server)
- `deploy-direct.sh` - Direct deployment script for Jenkins server
- `Jenkinsfile` - Jenkins CI/CD pipeline for automated deployment
- `deploy-to-server2.sh` - Script to deploy to Server 2 from Server 1 (SSH key)
- `deploy-to-server2-password.sh` - Script to deploy to Server 2 from Server 1 (Password)
- `Jenkinsfile-multi-server` - Multi-server Jenkins pipeline (SSH key)
- `Jenkinsfile-password-auth` - Multi-server Jenkins pipeline (Password)

### Server 2 (K8s Server)
- `server2-setup.sh` - Initial setup script for Server 2
- `server2-deploy.sh` - Deployment script for Server 2
- `Dockerfile` - Docker image configuration
- `k8s-deployment.yaml` - Kubernetes deployment manifests
- `deploy-k8s.sh` - Alternative K8s deployment script

### Configuration
- `server-config.sh` - Server configuration and validation (SSH key)
- `server-config-password.sh` - Server configuration and validation (Password)

## Deployment Process

### Server 1: Jenkins Server

1. **Direct Deployment** (Current setup):
   ```bash
   # Run the direct deployment script
   ./deploy-direct.sh
   ```

2. **Jenkins Pipeline** (Automated):
   - Configure Jenkins job using the `Jenkinsfile`
   - Pipeline will automatically build and deploy on code changes

### Server 2: Kubernetes Server

#### Option 1: Direct Deployment from Server 2
```bash
# Initial setup (one-time)
./server2-setup.sh

# Deploy service
./server2-deploy.sh
```

#### Option 2: Deploy from Server 1 (Jenkins) - SSH Key Authentication
```bash
# Configure server settings
# Edit server-config.sh with your Server 2 details

# Deploy from Server 1 to Server 2
./deploy-to-server2.sh deploy

# Check status
./deploy-to-server2.sh status

# Rollback if needed
./deploy-to-server2.sh rollback
```

#### Option 3: Deploy from Server 1 (Jenkins) - Password Authentication
```bash
# Configure server settings with password
# Edit server-config-password.sh with your Server 2 details

# Install sshpass (one-time)
./server-config-password.sh install-sshpass

# Deploy from Server 1 to Server 2
./deploy-to-server2-password.sh deploy

# Check status
./deploy-to-server2-password.sh status

# Rollback if needed
./deploy-to-server2-password.sh rollback
```

## Prerequisites

### Server 1 Requirements
- Jenkins server
- Java 17+
- Maven
- Git access to repository
- SSH key configured for GitHub

### Server 2 Requirements
- Docker
- kubectl
- Git
- SSH key configured for GitHub
- Kubernetes cluster access

## Configuration

### Environment Variables
- `REPO_URL`: GitHub repository URL
- `DOCKER_IMAGE_NAME`: Docker image name
- `K8S_NAMESPACE`: Kubernetes namespace
- `DEPLOYMENT_DIR`: Deployment directory path

### Port Configuration
- Default Eureka port: 8761
- Update `k8s-deployment.yaml` if using different port

## Monitoring and Troubleshooting

### Check Deployment Status
```bash
# Server 1
ps aux | grep java
tail -f /opt/deployment/eurekaServer.log

# Server 2
kubectl get pods -l app=eureka-service
kubectl logs -l app=eureka-service
```

### Common Issues

1. **SSH Key Issues**:
   ```bash
   # Test SSH connection
   ssh -T git@github.com
   ```

2. **Docker Build Issues**:
   ```bash
   # Check Docker daemon
   docker info
   ```

3. **Kubernetes Issues**:
   ```bash
   # Check cluster access
   kubectl cluster-info
   ```

## Security Considerations

1. **SSH Keys**: Ensure SSH keys are properly configured for GitHub access
2. **Docker Images**: Consider using private registries for production
3. **Kubernetes RBAC**: Configure appropriate RBAC for production deployments
4. **Network Policies**: Implement network policies for service communication

## Maintenance

### Updating Deployment
1. Pull latest code from repository
2. Rebuild Docker image (Server 2)
3. Redeploy using appropriate script

### Rollback
```bash
# Server 2 - Kubernetes rollback
kubectl rollout undo deployment/eureka-service
```

## File Structure
```
eureka-service/
├── deploy-direct.sh          # Server 1 direct deployment
├── deploy-to-server2.sh     # Deploy to Server 2 from Server 1
├── deploy-k8s.sh            # Alternative K8s deployment
├── server2-setup.sh         # Server 2 initial setup
├── server2-deploy.sh        # Server 2 deployment
├── Dockerfile               # Docker image configuration
├── k8s-deployment.yaml      # Kubernetes manifests
├── Jenkinsfile              # Jenkins CI/CD pipeline
├── Jenkinsfile-multi-server # Multi-server Jenkins pipeline
├── server-config.sh         # Server configuration
└── README.md               # This file
```

## Support

For issues or questions:
1. Check logs for error messages
2. Verify prerequisites are installed
3. Test connectivity to GitHub and Kubernetes cluster
4. Review configuration files for correct settings 