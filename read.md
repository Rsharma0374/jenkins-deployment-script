# Jenkins Deployment Scripts

This repository contains deployment shell scripts used by Jenkins jobs to deploy multiple services to either:

- Kubernetes environments (`k8s/`)
- Direct EC2 runtime (`ec2/`)

## Project Structure

- `k8s/` - Deployment scripts grouped by service for Kubernetes and web deployments.
- `ec2/` - Direct EC2 deployment scripts (non-Kubernetes).

Current scripts in this repository:

- `k8s/email-service/deploy-k8s.sh`
- `k8s/auth-service/deploy-k8s.sh`
- `k8s/api-gateway-service/deploy-k8s.sh`
- `k8s/doc-utility-service/deploy-k8s.sh`
- `k8s/doc-utility-service/deploy-web.sh`
- `k8s/password-manager-service/deploy-web.sh`
- `k8s/portfolio-service/deploy-web.sh`
- `k8s/eureka-service/deploy-k8s.sh`
- `k8s/eureka-service/deploy-direct.sh`
- `ec2/email-service/deploy-ec2.sh`

## Common Deployment Flow

Most scripts follow this pattern:

1. Accept runtime arguments from Jenkins (`password`, `branch`).
2. SSH into target server (`ubuntu@<server-ip>`) using `sshpass`.
3. Clone/update the service repository.
4. Build and deploy application artifacts (Docker/Kubernetes, Maven JAR, or web build).
5. Restart Nginx.

## Prerequisites

Make sure these are available on the Jenkins agent and target servers:

- `bash`
- `sshpass`
- `git`
- `sudo` access for deployment user
- `systemctl` (for Nginx restart)

Environment-specific requirements:

- Kubernetes scripts: `docker`, `kubectl`, cluster access, Docker Hub access if image push is used.
- Java direct deploy scripts: `java`, `mvn`.
- Web scripts: `node`, `npm`.

## Usage

### Kubernetes deployment example

```bash
bash k8s/email-service/deploy-k8s.sh "<server-password>" "<branch>"
```

### Direct EC2 deployment example (non-Kubernetes)

```bash
bash ec2/email-service/deploy-ec2.sh "<server-password>" "<branch>"
```

## Notes

- Scripts include hard-coded server IP and repository names. Update values in script files when infrastructure changes.
- Because several scripts use `git reset --hard`, avoid uncommitted changes in server-side working directories.
- Password-based SSH is used currently; key-based authentication is recommended for production.
