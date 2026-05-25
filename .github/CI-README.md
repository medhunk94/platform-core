# GitHub Actions CI/CD Pipeline

This repository uses GitHub Actions to automatically build, scan, and publish Docker images when code is pushed.

## Workflow: Build and Push Services

**Location:** `.github/workflows/build-services.yml`

### What It Does

1. **Triggers on:**
   - Push to `feature/systemcharts` or `main` branches
   - Changes to service code in `apps/checkout-team/` or `apps/orders-team/`
   - Manual workflow dispatch

2. **For Each Service:**
   - Builds Docker image using multi-stage Dockerfile
   - Tags image with branch name and git SHA
   - Pushes to GitHub Container Registry (`ghcr.io`)
   - Runs Trivy security scan for vulnerabilities
   - Uploads scan results to GitHub Security tab

3. **Image Tags:**
   - `feature-systemcharts-abc1234` - Branch + SHA
   - `feature-systemcharts` - Latest for branch
   - `latest` - Only on main branch

### Image Locations

After CI runs, images are published to:
- `ghcr.io/<your-username>/checkout-service`
- `ghcr.io/<your-username>/order-service`

### Setting Up

The workflow uses `GITHUB_TOKEN` automatically - no secrets to configure!

To pull images from GHCR:
```bash
echo $GITHUB_TOKEN | docker login ghcr.io -u <username> --password-stdin
docker pull ghcr.io/<username>/checkout-service:feature-systemcharts
```

### Security Scanning

Trivy scans for:
- OS package vulnerabilities
- Application dependencies
- Known CVEs rated CRITICAL or HIGH

Results appear in the GitHub Security > Code scanning alerts tab.

### Local Testing

Build locally before pushing:
```bash
# Checkout service
cd apps/checkout-team/checkout-service
docker build -t checkout-service:local .

# Order service
cd apps/orders-team/order-service
docker build -t order-service:local .
```
