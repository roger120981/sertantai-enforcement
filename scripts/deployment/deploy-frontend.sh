#!/bin/bash
#
# deploy-frontend.sh - Deploy Svelte frontend to production server
#
# This script deploys the built frontend static files to the production
# server's nginx directory using rsync.
#
# Usage:
#   ./scripts/deployment/deploy-frontend.sh [options]
#
# Options:
#   --build        Build frontend before deploying
#   --dry-run      Show what would be transferred without actually doing it
#   --check-only   Check server connectivity and current deployment status
#   --help         Show this help message
#
# Prerequisites:
#   - Frontend built: ./scripts/deployment/build-frontend.sh
#   - SSH access to sertantai-hz server configured
#   - rsync installed locally
#
# Production server details:
#   - Server: sertantai-hz (Hetzner dedicated server)
#   - Deploy path: /var/www/enforcement-frontend
#   - URL: https://enforcement.sertantai.com
#

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SERVER="sertantai-hz"
DEPLOY_PATH="/var/www/enforcement-frontend"
BUILD_DIR="frontend/build"
SITE_URL="https://enforcement.sertantai.com"

# Parse command line options
BUILD_FIRST=false
DRY_RUN=false
CHECK_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --build)
            BUILD_FIRST=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --check-only)
            CHECK_ONLY=true
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --build        Build frontend before deploying"
            echo "  --dry-run      Show what would be transferred without actually doing it"
            echo "  --check-only   Check server connectivity and current deployment status"
            echo "  --help         Show this help message"
            echo ""
            echo "Production Details:"
            echo "  Server:      ${SERVER}"
            echo "  Deploy path: ${DEPLOY_PATH}"
            echo "  URL:         ${SITE_URL}"
            echo ""
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Navigate to project root (two levels up from scripts/deployment/)
cd "$(dirname "$0")/../.."

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Sertantai Enforcement - Frontend Deployment${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Server:${NC} ${SERVER}"
echo -e "${YELLOW}Deploy path:${NC} ${DEPLOY_PATH}"
echo -e "${YELLOW}URL:${NC} ${SITE_URL}"
echo ""

# Check rsync is installed
if ! command -v rsync &> /dev/null; then
    echo -e "${RED}✗ Error: rsync is not installed${NC}"
    echo -e "${YELLOW}  Install rsync and try again${NC}"
    exit 1
fi

# Check SSH connectivity
echo -e "${BLUE}Checking SSH connection to ${SERVER}...${NC}"
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "${SERVER}" "echo 'SSH OK'" > /dev/null 2>&1; then
    echo -e "${RED}✗ Cannot connect to ${SERVER}${NC}"
    echo -e "${YELLOW}  Check your SSH configuration and try again${NC}"
    exit 1
fi
echo -e "${GREEN}✓ SSH connection OK${NC}"
echo ""

# Check-only mode
if [ "$CHECK_ONLY" = true ]; then
    echo -e "${BLUE}Checking current deployment status...${NC}"
    echo ""

    # Check if deploy directory exists
    if ssh "${SERVER}" "[ -d ${DEPLOY_PATH} ]"; then
        echo -e "${GREEN}✓ Deploy directory exists${NC}"

        # Show current deployment info
        echo ""
        echo -e "${BLUE}Current deployment:${NC}"
        ssh "${SERVER}" "ls -la ${DEPLOY_PATH}/ | head -15"

        # Check disk usage
        echo ""
        DISK_USAGE=$(ssh "${SERVER}" "du -sh ${DEPLOY_PATH}" 2>/dev/null || echo "unknown")
        echo -e "${YELLOW}Disk usage:${NC} ${DISK_USAGE}"

        # Check if index.html exists
        if ssh "${SERVER}" "[ -f ${DEPLOY_PATH}/index.html ]"; then
            echo -e "${GREEN}✓ index.html present${NC}"
        else
            echo -e "${YELLOW}⚠ index.html not found${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Deploy directory does not exist: ${DEPLOY_PATH}${NC}"
        echo -e "${YELLOW}  It will be created on first deployment${NC}"
    fi

    echo ""
    echo -e "${GREEN}Status check complete${NC}"
    exit 0
fi

# Build first if requested
if [ "$BUILD_FIRST" = true ]; then
    echo -e "${BLUE}Building frontend first...${NC}"
    echo ""
    ./scripts/deployment/build-frontend.sh
    echo ""
fi

# Check build directory exists
if [ ! -d "${BUILD_DIR}" ]; then
    echo -e "${RED}✗ Error: Build directory not found: ${BUILD_DIR}${NC}"
    echo -e "${YELLOW}  Run build first: ./scripts/deployment/build-frontend.sh${NC}"
    exit 1
fi

# Check build has content
FILE_COUNT=$(find "${BUILD_DIR}" -type f | wc -l)
if [ "$FILE_COUNT" -eq 0 ]; then
    echo -e "${RED}✗ Error: Build directory is empty${NC}"
    echo -e "${YELLOW}  Run build first: ./scripts/deployment/build-frontend.sh${NC}"
    exit 1
fi

BUILD_SIZE=$(du -sh "${BUILD_DIR}" | cut -f1)
echo -e "${GREEN}✓ Build found: ${FILE_COUNT} files (${BUILD_SIZE})${NC}"
echo ""

# Ensure deploy directory exists on server
echo -e "${BLUE}Ensuring deploy directory exists...${NC}"
ssh "${SERVER}" "sudo mkdir -p ${DEPLOY_PATH} && sudo chown \$(whoami):\$(whoami) ${DEPLOY_PATH}"
echo -e "${GREEN}✓ Deploy directory ready${NC}"
echo ""

# Deploy with rsync
if [ "$DRY_RUN" = true ]; then
    echo -e "${BLUE}Dry run - showing what would be transferred:${NC}"
    echo ""
    rsync -avz --delete --dry-run "${BUILD_DIR}/" "${SERVER}:${DEPLOY_PATH}/"
    echo ""
    echo -e "${YELLOW}This was a dry run. No files were transferred.${NC}"
    echo -e "${YELLOW}Remove --dry-run to actually deploy.${NC}"
    exit 0
fi

echo -e "${BLUE}Deploying to ${SERVER}:${DEPLOY_PATH}...${NC}"
echo ""

rsync -avz --delete --progress "${BUILD_DIR}/" "${SERVER}:${DEPLOY_PATH}/"

if [ $? -ne 0 ]; then
    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}✗ Deployment failed${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    exit 1
fi

echo ""

# Verify deployment
echo -e "${BLUE}Verifying deployment...${NC}"
REMOTE_COUNT=$(ssh "${SERVER}" "find ${DEPLOY_PATH} -type f | wc -l")
echo -e "${GREEN}✓ Deployed ${REMOTE_COUNT} files${NC}"

# Check if nginx can serve the files (basic check)
if ssh "${SERVER}" "[ -f ${DEPLOY_PATH}/index.html ]"; then
    echo -e "${GREEN}✓ index.html present${NC}"
else
    echo -e "${YELLOW}⚠ index.html not found - check build output${NC}"
fi

echo ""

# Success summary
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Frontend deployment successful!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}URL:${NC} ${SITE_URL}"
echo -e "${YELLOW}Files deployed:${NC} ${REMOTE_COUNT}"
echo ""

echo -e "${BLUE}Next steps:${NC}"
echo -e "  ${GREEN}→${NC} Verify site:        ${YELLOW}curl -I ${SITE_URL}${NC}"
echo -e "  ${GREEN}→${NC} Deploy backend:     ${YELLOW}./scripts/deployment/deploy-prod.sh${NC}"
echo -e "  ${GREEN}→${NC} Check nginx config: ${YELLOW}ssh ${SERVER} 'sudo nginx -t'${NC}"
echo ""

echo -e "${BLUE}Note:${NC} If this is the first deployment, ensure nginx is configured"
echo -e "      to serve files from ${DEPLOY_PATH}"
echo ""
