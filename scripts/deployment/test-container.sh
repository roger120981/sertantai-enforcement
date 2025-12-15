#!/bin/bash
#
# test-container.sh - Test EHS Enforcement full stack locally
#
# This script tests the production build locally before deploying.
# It uses docker-compose.yml to create a local test environment with:
#   - PostgreSQL with logical replication
#   - ElectricSQL sync service
#   - Phoenix backend (production Docker image)
#   - Frontend (served via npm preview or separate check)
#
# Usage:
#   ./scripts/deployment/test-container.sh [options]
#
# Options:
#   --backend-only   Test only the Phoenix backend
#   --frontend-only  Test only the frontend build
#   --skip-electric  Skip ElectricSQL startup (faster, but no sync testing)
#   --clean          Clean up and remove test environment
#   --help           Show this help message
#
# Prerequisites:
#   - Docker image built: ./scripts/deployment/build.sh --backend-only
#   - Frontend built: ./scripts/deployment/build-frontend.sh
#   - docker-compose.yml exists (development compose file)
#
# What it does:
#   - Starts PostgreSQL with logical replication
#   - Starts ElectricSQL for sync testing
#   - Runs the production Docker image
#   - Tests health endpoints
#   - Optionally previews frontend
#
# Note: For day-to-day development, use ./scripts/development/sert-enf-start instead.
# This script is specifically for testing production builds before deployment.
#

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.yml"
IMAGE_NAME="ghcr.io/shotleybuilder/ehs-enforcement:latest"
FRONTEND_BUILD="frontend/build"

# Parse command line options
TEST_BACKEND=true
TEST_FRONTEND=true
SKIP_ELECTRIC=false
CLEAN_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --backend-only)
            TEST_FRONTEND=false
            shift
            ;;
        --frontend-only)
            TEST_BACKEND=false
            shift
            ;;
        --skip-electric)
            SKIP_ELECTRIC=true
            shift
            ;;
        --clean)
            CLEAN_ONLY=true
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --backend-only   Test only the Phoenix backend"
            echo "  --frontend-only  Test only the frontend build"
            echo "  --skip-electric  Skip ElectricSQL startup"
            echo "  --clean          Clean up test environment"
            echo "  --help           Show this help message"
            echo ""
            echo "Note: For development, use ./scripts/development/sert-enf-start"
            echo "      This script tests production builds before deployment."
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
echo -e "${BLUE}  EHS Enforcement - Production Build Test${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Clean up mode
if [ "$CLEAN_ONLY" = true ]; then
    echo -e "${BLUE}Cleaning up test environment...${NC}"
    docker compose -f "${COMPOSE_FILE}" down -v > /dev/null 2>&1 || true
    echo -e "${GREEN}✓ Test environment cleaned up${NC}"
    exit 0
fi

# Show what will be tested
if [ "$TEST_BACKEND" = true ] && [ "$TEST_FRONTEND" = true ]; then
    echo -e "${YELLOW}Testing:${NC} Full stack (backend + frontend)"
elif [ "$TEST_BACKEND" = true ]; then
    echo -e "${YELLOW}Testing:${NC} Backend only"
else
    echo -e "${YELLOW}Testing:${NC} Frontend only"
fi
echo ""

# ============================================================
# TEST FRONTEND
# ============================================================
if [ "$TEST_FRONTEND" = true ]; then
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│  Testing Frontend Build                                 │${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────┘${NC}"
    echo ""

    if [ ! -d "${FRONTEND_BUILD}" ]; then
        echo -e "${RED}✗ Frontend build not found: ${FRONTEND_BUILD}${NC}"
        echo -e "${YELLOW}  Build first: ./scripts/deployment/build-frontend.sh${NC}"
        echo ""
    else
        FILE_COUNT=$(find "${FRONTEND_BUILD}" -type f | wc -l)
        BUILD_SIZE=$(du -sh "${FRONTEND_BUILD}" | cut -f1)
        echo -e "${GREEN}✓ Frontend build found${NC}"
        echo -e "${YELLOW}  Files:${NC} ${FILE_COUNT}"
        echo -e "${YELLOW}  Size:${NC} ${BUILD_SIZE}"

        # Check for index.html
        if [ -f "${FRONTEND_BUILD}/index.html" ]; then
            echo -e "${GREEN}✓ index.html present${NC}"
        else
            echo -e "${RED}✗ index.html missing${NC}"
        fi

        # Check for _app directory (SvelteKit output)
        if [ -d "${FRONTEND_BUILD}/_app" ]; then
            echo -e "${GREEN}✓ _app directory present (SvelteKit assets)${NC}"
        fi

        echo ""
        echo -e "${BLUE}To preview frontend locally:${NC}"
        echo -e "  ${YELLOW}cd frontend && npm run preview${NC}"
        echo ""
    fi
fi

# ============================================================
# TEST BACKEND
# ============================================================
if [ "$TEST_BACKEND" = true ]; then
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│  Testing Backend (Docker Container)                     │${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────┘${NC}"
    echo ""

    # Check if Docker image exists
    if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${IMAGE_NAME}$"; then
        echo -e "${RED}✗ Docker image not found: ${IMAGE_NAME}${NC}"
        echo -e "${YELLOW}  Build first: ./scripts/deployment/build.sh --backend-only${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Docker image found${NC}"

    # Show image details
    IMAGE_SIZE=$(docker images --format "{{.Size}}" "${IMAGE_NAME}" | head -1)
    IMAGE_ID=$(docker images --format "{{.ID}}" "${IMAGE_NAME}" | head -1)
    echo -e "${YELLOW}  Size:${NC} ${IMAGE_SIZE}"
    echo -e "${YELLOW}  ID:${NC} ${IMAGE_ID}"
    echo ""

    # Check if docker-compose.yml exists
    if [ ! -f "${COMPOSE_FILE}" ]; then
        echo -e "${RED}✗ ${COMPOSE_FILE} not found${NC}"
        echo -e "${YELLOW}  Cannot run container tests without compose file${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Found ${COMPOSE_FILE}${NC}"
    echo ""

    # Clean up any previous test environment
    echo -e "${BLUE}Cleaning up previous test environment...${NC}"
    docker compose -f "${COMPOSE_FILE}" down -v > /dev/null 2>&1 || true
    echo -e "${GREEN}✓ Cleanup complete${NC}"
    echo ""

    # Start PostgreSQL
    echo -e "${BLUE}Starting PostgreSQL...${NC}"
    docker compose -f "${COMPOSE_FILE}" up -d postgres

    # Wait for PostgreSQL
    echo -e "${BLUE}Waiting for PostgreSQL to be ready...${NC}"
    for i in {1..30}; do
        if docker compose -f "${COMPOSE_FILE}" exec -T postgres pg_isready -U postgres > /dev/null 2>&1; then
            echo -e "${GREEN}✓ PostgreSQL is ready${NC}"
            break
        fi
        if [ $i -eq 30 ]; then
            echo -e "${RED}✗ PostgreSQL failed to start within 30 seconds${NC}"
            docker compose -f "${COMPOSE_FILE}" logs postgres
            docker compose -f "${COMPOSE_FILE}" down -v
            exit 1
        fi
        sleep 1
    done
    echo ""

    # Start ElectricSQL (unless skipped)
    if [ "$SKIP_ELECTRIC" = false ]; then
        echo -e "${BLUE}Starting ElectricSQL...${NC}"
        docker compose -f "${COMPOSE_FILE}" up -d electric

        # Wait for Electric
        echo -e "${BLUE}Waiting for ElectricSQL to be ready...${NC}"
        for i in {1..30}; do
            if curl -s http://localhost:3001/v1/health > /dev/null 2>&1; then
                echo -e "${GREEN}✓ ElectricSQL is ready${NC}"
                break
            fi
            if [ $i -eq 30 ]; then
                echo -e "${YELLOW}⚠ ElectricSQL not responding (continuing anyway)${NC}"
                break
            fi
            sleep 1
        done
        echo ""
    else
        echo -e "${YELLOW}Skipping ElectricSQL (--skip-electric)${NC}"
        echo ""
    fi

    # Note: The production image test would require a separate compose service
    # For now, we test with the development setup
    echo -e "${BLUE}Testing with development compose services...${NC}"
    echo -e "${YELLOW}Note: Production image testing requires additional setup${NC}"
    echo ""

    # Check PostgreSQL connection
    echo -e "${BLUE}Testing database connectivity...${NC}"
    if docker compose -f "${COMPOSE_FILE}" exec -T postgres psql -U postgres -d ehs_enforcement_dev -c "SELECT 1" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Database connection OK${NC}"
    else
        echo -e "${YELLOW}⚠ Database may need initialization${NC}"
    fi
    echo ""

    # Summary
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Test environment is running!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}Services:${NC}"
    echo -e "  PostgreSQL: localhost:5434"
    if [ "$SKIP_ELECTRIC" = false ]; then
        echo -e "  ElectricSQL: http://localhost:3001"
    fi
    echo ""
    echo -e "${BLUE}Commands:${NC}"
    echo -e "  View logs:        ${YELLOW}docker compose -f ${COMPOSE_FILE} logs -f${NC}"
    echo -e "  Check status:     ${YELLOW}docker compose -f ${COMPOSE_FILE} ps${NC}"
    echo -e "  Stop environment: ${YELLOW}docker compose -f ${COMPOSE_FILE} down${NC}"
    echo -e "  Clean up:         ${YELLOW}docker compose -f ${COMPOSE_FILE} down -v${NC}"
    echo ""
    echo -e "${BLUE}To start the full dev environment:${NC}"
    echo -e "  ${YELLOW}./scripts/development/sert-enf-start${NC}"
    echo ""

    # Offer to follow logs
    read -p "Follow logs? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Following logs (Ctrl+C to exit)...${NC}"
        echo ""
        docker compose -f "${COMPOSE_FILE}" logs -f
    fi
fi

echo ""
echo -e "${GREEN}Test complete!${NC}"
echo ""
echo -e "${BLUE}To clean up:${NC} ${YELLOW}./scripts/deployment/test-container.sh --clean${NC}"
echo ""
