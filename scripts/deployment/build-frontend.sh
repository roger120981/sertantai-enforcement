#!/bin/bash
#
# build-frontend.sh - Build Svelte frontend for production
#
# This script builds the Svelte frontend for production deployment.
# The output is a static build in frontend/build/ that can be deployed
# to nginx or any static file server.
#
# Usage:
#   ./scripts/deployment/build-frontend.sh [options]
#
# Options:
#   --clean        Remove node_modules and reinstall before building
#   --check        Run type checking and linting before build
#   --help         Show this help message
#
# Prerequisites:
#   - Node.js 20+ installed
#   - npm installed
#
# Environment Variables (set in frontend/.env.production):
#   PUBLIC_API_URL      - Phoenix backend URL (e.g., https://enforcement.sertantai.com)
#   PUBLIC_ELECTRIC_URL - ElectricSQL sync service URL
#   PUBLIC_ENV          - Environment identifier (production)
#
# Next steps after successful build:
#   - Deploy frontend: ./scripts/deployment/deploy-frontend.sh
#   - Or deploy everything: ./scripts/deployment/deploy-prod.sh --frontend
#

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
FRONTEND_DIR="frontend"
BUILD_DIR="frontend/build"

# Parse command line options
CLEAN_BUILD=false
RUN_CHECKS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --check)
            RUN_CHECKS=true
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --clean        Remove node_modules and reinstall before building"
            echo "  --check        Run type checking and linting before build"
            echo "  --help         Show this help message"
            echo ""
            echo "Environment Variables (in frontend/.env.production):"
            echo "  PUBLIC_API_URL      - Phoenix backend URL"
            echo "  PUBLIC_ELECTRIC_URL - ElectricSQL sync service URL"
            echo "  PUBLIC_ENV          - Environment identifier"
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
echo -e "${BLUE}  Sertantai Enforcement - Frontend Build${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check if frontend directory exists
if [ ! -d "${FRONTEND_DIR}" ]; then
    echo -e "${RED}✗ Error: Frontend directory not found: ${FRONTEND_DIR}${NC}"
    echo -e "${YELLOW}  Current directory: $(pwd)${NC}"
    exit 1
fi

# Check Node.js is installed
if ! command -v node &> /dev/null; then
    echo -e "${RED}✗ Error: Node.js is not installed${NC}"
    echo -e "${YELLOW}  Please install Node.js 20+ and try again${NC}"
    exit 1
fi

# Check npm is installed
if ! command -v npm &> /dev/null; then
    echo -e "${RED}✗ Error: npm is not installed${NC}"
    echo -e "${YELLOW}  Please install npm and try again${NC}"
    exit 1
fi

# Display versions
NODE_VERSION=$(node --version)
NPM_VERSION=$(npm --version)
echo -e "${YELLOW}Node.js:${NC} ${NODE_VERSION}"
echo -e "${YELLOW}npm:${NC} ${NPM_VERSION}"
echo ""

# Change to frontend directory
cd "${FRONTEND_DIR}"

# Clean build if requested
if [ "$CLEAN_BUILD" = true ]; then
    echo -e "${BLUE}[1/5] Cleaning previous build and dependencies...${NC}"
    rm -rf node_modules build .svelte-kit
    echo -e "${GREEN}✓ Cleaned${NC}"
    echo ""
else
    echo -e "${YELLOW}[1/5] Skipping clean (use --clean to force)${NC}"
    echo ""
fi

# Install dependencies
echo -e "${BLUE}[2/5] Installing dependencies...${NC}"
npm ci --silent 2>/dev/null || npm install --silent
echo -e "${GREEN}✓ Dependencies installed${NC}"
echo ""

# Run checks if requested
if [ "$RUN_CHECKS" = true ]; then
    echo -e "${BLUE}[3/5] Running type checks and linting...${NC}"

    # Type check
    echo -e "${YELLOW}  Running svelte-check...${NC}"
    if npm run check; then
        echo -e "${GREEN}  ✓ Type checks passed${NC}"
    else
        echo -e "${RED}  ✗ Type checks failed${NC}"
        exit 1
    fi

    # Lint
    echo -e "${YELLOW}  Running eslint...${NC}"
    if npm run lint; then
        echo -e "${GREEN}  ✓ Linting passed${NC}"
    else
        echo -e "${RED}  ✗ Linting failed${NC}"
        exit 1
    fi
    echo ""
else
    echo -e "${YELLOW}[3/5] Skipping checks (use --check to enable)${NC}"
    echo ""
fi

# Check for production environment file
if [ -f ".env.production" ]; then
    echo -e "${GREEN}✓ Found .env.production${NC}"
    # Show configured URLs (without revealing secrets)
    if grep -q "PUBLIC_API_URL" .env.production; then
        API_URL=$(grep "PUBLIC_API_URL" .env.production | cut -d '=' -f2)
        echo -e "${YELLOW}  API URL:${NC} ${API_URL}"
    fi
    if grep -q "PUBLIC_ELECTRIC_URL" .env.production; then
        ELECTRIC_URL=$(grep "PUBLIC_ELECTRIC_URL" .env.production | cut -d '=' -f2)
        echo -e "${YELLOW}  Electric URL:${NC} ${ELECTRIC_URL}"
    fi
elif [ -f ".env" ]; then
    echo -e "${YELLOW}⚠ No .env.production found, using .env${NC}"
    echo -e "${YELLOW}  Consider creating .env.production for production builds${NC}"
else
    echo -e "${YELLOW}⚠ No environment file found${NC}"
    echo -e "${YELLOW}  Build will use default/hardcoded values${NC}"
fi
echo ""

# Build for production
echo -e "${BLUE}[4/5] Building for production...${NC}"
npm run build

if [ $? -ne 0 ]; then
    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}✗ Build failed${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}Check the output above for error details${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Build complete${NC}"
echo ""

# Verify build output
echo -e "${BLUE}[5/5] Verifying build output...${NC}"
cd ..  # Back to project root

if [ ! -d "${BUILD_DIR}" ]; then
    echo -e "${RED}✗ Error: Build directory not found: ${BUILD_DIR}${NC}"
    exit 1
fi

# Count files and calculate size
FILE_COUNT=$(find "${BUILD_DIR}" -type f | wc -l)
BUILD_SIZE=$(du -sh "${BUILD_DIR}" | cut -f1)

echo -e "${GREEN}✓ Build verified${NC}"
echo ""

# Success summary
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Frontend build successful!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Output:${NC} ${BUILD_DIR}/"
echo -e "${YELLOW}Files:${NC} ${FILE_COUNT}"
echo -e "${YELLOW}Size:${NC} ${BUILD_SIZE}"
echo ""

# Show key files
echo -e "${BLUE}Build contents:${NC}"
ls -la "${BUILD_DIR}/" | head -10
echo ""

echo -e "${BLUE}Next steps:${NC}"
echo -e "  ${GREEN}→${NC} Deploy frontend:     ${YELLOW}./scripts/deployment/deploy-frontend.sh${NC}"
echo -e "  ${GREEN}→${NC} Deploy everything:   ${YELLOW}./scripts/deployment/deploy-prod.sh --frontend${NC}"
echo -e "  ${GREEN}→${NC} Preview locally:     ${YELLOW}cd frontend && npm run preview${NC}"
echo ""
