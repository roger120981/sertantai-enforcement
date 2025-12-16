#!/bin/bash
#
# build.sh - Build production artifacts for Sertantai Enforcement
#
# This script builds production artifacts for the full stack:
#   - Phoenix backend Docker image (tagged for GHCR)
#   - Svelte frontend static files (to frontend/build/)
#
# Usage:
#   ./scripts/deployment/build.sh [options] [tag]
#
# Options:
#   --backend-only   Build only the Phoenix Docker image
#   --frontend-only  Build only the Svelte frontend
#   --no-cache       Build Docker image without cache
#   --check          Run frontend type checks and linting
#   --help           Show this help message
#
# Arguments:
#   tag              Docker image tag (default: latest)
#
# Prerequisites:
#   - Docker installed and running (for backend)
#   - Node.js 20+ installed (for frontend)
#   - Dockerfile present in project root
#
# Next steps after successful build:
#   - Test locally: ./scripts/deployment/test-container.sh
#   - Push backend: ./scripts/deployment/push.sh
#   - Deploy frontend: ./scripts/deployment/deploy-frontend.sh
#   - Deploy all: ./scripts/deployment/deploy-prod.sh --all
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
IMAGE_TAG="latest"

# Parse command line options
BUILD_BACKEND=true
BUILD_FRONTEND=true
NO_CACHE=false
RUN_CHECKS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --backend-only)
            BUILD_FRONTEND=false
            shift
            ;;
        --frontend-only)
            BUILD_BACKEND=false
            shift
            ;;
        --no-cache)
            NO_CACHE=true
            shift
            ;;
        --check)
            RUN_CHECKS=true
            shift
            ;;
        --help)
            echo "Usage: $0 [options] [tag]"
            echo ""
            echo "Options:"
            echo "  --backend-only   Build only the Phoenix Docker image"
            echo "  --frontend-only  Build only the Svelte frontend"
            echo "  --no-cache       Build Docker image without cache"
            echo "  --check          Run frontend type checks and linting"
            echo "  --help           Show this help message"
            echo ""
            echo "Arguments:"
            echo "  tag              Docker image tag (default: latest)"
            echo ""
            exit 0
            ;;
        -*)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            IMAGE_TAG="$1"
            shift
            ;;
    esac
done

FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

# Navigate to project root (two levels up from scripts/deployment/)
cd "$(dirname "$0")/../.."

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Sertantai Enforcement - Production Build${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Show what will be built
if [ "$BUILD_BACKEND" = true ] && [ "$BUILD_FRONTEND" = true ]; then
    echo -e "${YELLOW}Building:${NC} Full stack (backend + frontend)"
elif [ "$BUILD_BACKEND" = true ]; then
    echo -e "${YELLOW}Building:${NC} Backend only"
else
    echo -e "${YELLOW}Building:${NC} Frontend only"
fi
echo ""

# Track overall success
BACKEND_SUCCESS=true
FRONTEND_SUCCESS=true

# ============================================================
# BUILD FRONTEND
# ============================================================
if [ "$BUILD_FRONTEND" = true ]; then
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│  Building Frontend (Svelte)                             │${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────┘${NC}"
    echo ""

    # Build frontend using the dedicated script
    if [ "$RUN_CHECKS" = true ]; then
        if ./scripts/deployment/build-frontend.sh --check; then
            echo -e "${GREEN}✓ Frontend build complete${NC}"
        else
            echo -e "${RED}✗ Frontend build failed${NC}"
            FRONTEND_SUCCESS=false
        fi
    else
        if ./scripts/deployment/build-frontend.sh; then
            echo -e "${GREEN}✓ Frontend build complete${NC}"
        else
            echo -e "${RED}✗ Frontend build failed${NC}"
            FRONTEND_SUCCESS=false
        fi
    fi
    echo ""
fi

# ============================================================
# BUILD BACKEND
# ============================================================
if [ "$BUILD_BACKEND" = true ]; then
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│  Building Backend (Phoenix Docker Image)                │${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${YELLOW}Image:${NC} ${FULL_IMAGE}"
    echo -e "${YELLOW}Dockerfile:${NC} ./Dockerfile"
    echo ""

    # Check if Dockerfile exists
    if [ ! -f "Dockerfile" ]; then
        echo -e "${RED}✗ Error: Dockerfile not found in project root${NC}"
        echo -e "${YELLOW}  Current directory: $(pwd)${NC}"
        BACKEND_SUCCESS=false
    else
        # Check if Docker is running
        if ! docker info > /dev/null 2>&1; then
            echo -e "${RED}✗ Error: Docker is not running${NC}"
            echo -e "${YELLOW}  Please start Docker and try again${NC}"
            BACKEND_SUCCESS=false
        else
            # Build the image
            echo -e "${BLUE}Building Docker image...${NC}"
            echo ""

            BUILD_ARGS="--tag ${FULL_IMAGE} --file Dockerfile"
            if [ "$NO_CACHE" = true ]; then
                BUILD_ARGS="--no-cache ${BUILD_ARGS}"
                echo -e "${YELLOW}Building without cache...${NC}"
            fi

            if docker build ${BUILD_ARGS} .; then
                echo ""
                echo -e "${GREEN}✓ Backend build complete${NC}"

                # Display image details
                IMAGE_SIZE=$(docker images --format "{{.Size}}" "${FULL_IMAGE}" | head -1)
                IMAGE_ID=$(docker images --format "{{.ID}}" "${FULL_IMAGE}" | head -1)
                echo -e "${YELLOW}  Size:${NC} ${IMAGE_SIZE}"
                echo -e "${YELLOW}  ID:${NC} ${IMAGE_ID}"
            else
                echo -e "${RED}✗ Backend build failed${NC}"
                BACKEND_SUCCESS=false
            fi
        fi
    fi
    echo ""
fi

# ============================================================
# SUMMARY
# ============================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ "$BACKEND_SUCCESS" = true ] && [ "$FRONTEND_SUCCESS" = true ]; then
    echo -e "${GREEN}✓ Build complete!${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if [ "$BUILD_BACKEND" = true ]; then
        echo -e "${YELLOW}Backend image:${NC} ${FULL_IMAGE}"
    fi
    if [ "$BUILD_FRONTEND" = true ]; then
        echo -e "${YELLOW}Frontend build:${NC} frontend/build/"
    fi
    echo ""

    echo -e "${BLUE}Next steps:${NC}"
    if [ "$BUILD_BACKEND" = true ]; then
        echo -e "  ${GREEN}→${NC} Test locally:      ${YELLOW}./scripts/deployment/test-container.sh${NC}"
        echo -e "  ${GREEN}→${NC} Push to GHCR:      ${YELLOW}./scripts/deployment/push.sh${NC}"
    fi
    if [ "$BUILD_FRONTEND" = true ]; then
        echo -e "  ${GREEN}→${NC} Deploy frontend:   ${YELLOW}./scripts/deployment/deploy-frontend.sh${NC}"
    fi
    echo -e "  ${GREEN}→${NC} Deploy everything: ${YELLOW}./scripts/deployment/deploy-prod.sh --all${NC}"
    echo ""
else
    echo -e "${RED}✗ Build failed${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    if [ "$BACKEND_SUCCESS" = false ]; then
        echo -e "${RED}  ✗ Backend build failed${NC}"
    fi
    if [ "$FRONTEND_SUCCESS" = false ]; then
        echo -e "${RED}  ✗ Frontend build failed${NC}"
    fi
    echo ""
    echo -e "${YELLOW}Check the output above for error details${NC}"
    exit 1
fi
