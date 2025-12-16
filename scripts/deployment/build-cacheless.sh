#!/bin/bash
#
# build-cacheless.sh - Build production Docker image WITHOUT CACHE
#
# This script builds the production Docker image locally using the standard
# Dockerfile with --no-cache flag to force fresh builds of all layers.
# Use this when you need to ensure the latest source code is included.
#
# Usage:
#   ./scripts/deployment/build-cacheless.sh
#
# Prerequisites:
#   - Docker installed and running
#   - Dockerfile present in project root
#
# Next steps after successful build:
#   - Test locally: ./scripts/test-container.sh
#   - Push to GHCR: ./scripts/push.sh
#

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Image configuration
IMAGE_NAME="ghcr.io/shotleybuilder/sertantai-enforcement"
IMAGE_TAG="${1:-latest}"
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

# Navigate to project root (two levels up from scripts/deployment/)
cd "$(dirname "$0")/../.."

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Sertantai Enforcement - Docker Build (NO CACHE)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Image:${NC} ${FULL_IMAGE}"
echo -e "${YELLOW}Dockerfile:${NC} ./Dockerfile"
echo ""

# Check if Dockerfile exists
if [ ! -f "Dockerfile" ]; then
    echo -e "${RED}✗ Error: Dockerfile not found in project root${NC}"
    echo -e "${YELLOW}  Current directory: $(pwd)${NC}"
    exit 1
fi

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}✗ Error: Docker is not running${NC}"
    echo -e "${YELLOW}  Please start Docker and try again${NC}"
    exit 1
fi

# Clear Docker build cache first (critical for --no-cache to work properly)
echo -e "${YELLOW}Clearing Docker build cache...${NC}"
docker builder prune -f > /dev/null 2>&1
echo -e "${GREEN}✓ Build cache cleared${NC}"
echo ""

# Display build information
echo -e "${BLUE}Building Docker image...${NC}"
echo ""

# Build the image with progress output (NO CACHE - forces fresh build)
docker build \
    --no-cache \
    --tag "${FULL_IMAGE}" \
    --file Dockerfile \
    .

# Check build success
if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓ Build complete!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}Image:${NC} ${FULL_IMAGE}"

    # Display image details
    IMAGE_SIZE=$(docker images --format "{{.Size}}" "${FULL_IMAGE}" | head -1)
    IMAGE_ID=$(docker images --format "{{.ID}}" "${FULL_IMAGE}" | head -1)
    echo -e "${YELLOW}Size:${NC} ${IMAGE_SIZE}"
    echo -e "${YELLOW}ID:${NC} ${IMAGE_ID}"
    echo ""

    echo -e "${BLUE}Next steps:${NC}"
    echo -e "  ${GREEN}→${NC} Test locally:  ${YELLOW}./scripts/deployment/test-container.sh${NC}"
    echo -e "  ${GREEN}→${NC} Push to GHCR:  ${YELLOW}./scripts/deployment/push.sh${NC}"
    echo ""
else
    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}✗ Build failed${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}Check the output above for error details${NC}"
    exit 1
fi
