#!/bin/bash
#
# deploy-prod.sh - Deploy Sertantai Enforcement to production server
#
# This script deploys the full stack to production:
#   - Frontend: Svelte static files to nginx (via rsync)
#   - Backend: Phoenix Docker container (via docker compose)
#   - Electric: ElectricSQL sync service (safe restart)
#
# Usage:
#   ./scripts/deployment/deploy-prod.sh [options]
#
# Options:
#   --all              Deploy both frontend and backend (default)
#   --frontend         Deploy frontend only
#   --backend          Deploy backend only
#   --electric         Restart ElectricSQL only (safe restart)
#   --with-electric    Also restart ElectricSQL when deploying backend
#   --electric-clear-cache  Restart Electric and clear shape cache
#   --migrate          Run database migrations
#   --check-only       Only check status, don't deploy
#   --logs             Follow logs after deployment
#   --help             Show this help message
#
# ElectricSQL Notes:
#   - Uses 'docker restart' for safe restarts (preserves database)
#   - NEVER uses 'docker compose up electric' (can wipe database!)
#   - Clear cache when schema changes or shapes are stale
#   - Electric container: sertantai-enforcement-electric
#
# Prerequisites:
#   - SSH access to sertantai-hz server configured
#   - Backend: Image pushed to GHCR (./scripts/deployment/push.sh)
#   - Frontend: Built (./scripts/deployment/build-frontend.sh)
#
# Production server details:
#   - Server: sertantai-hz (Hetzner dedicated server)
#   - Infrastructure: ~/infrastructure/docker
#   - Frontend: /var/www/enforcement-frontend
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
DEPLOY_PATH="~/infrastructure/docker"
SERVICE_NAME="sertantai-enforcement"
ELECTRIC_CONTAINER="sertantai-enforcement-electric"
FRONTEND_PATH="/var/www/enforcement-frontend"
BUILD_DIR="frontend/build"
SITE_URL="https://enforcement.sertantai.com"
ELECTRIC_URL="${SITE_URL}/electric"

# Parse command line options
DEPLOY_FRONTEND=true
DEPLOY_BACKEND=true
DEPLOY_ELECTRIC=false
WITH_ELECTRIC=false
ELECTRIC_CLEAR_CACHE=false
RUN_MIGRATIONS=false
CHECK_ONLY=false
FOLLOW_LOGS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            DEPLOY_FRONTEND=true
            DEPLOY_BACKEND=true
            shift
            ;;
        --frontend)
            DEPLOY_FRONTEND=true
            DEPLOY_BACKEND=false
            shift
            ;;
        --backend)
            DEPLOY_FRONTEND=false
            DEPLOY_BACKEND=true
            shift
            ;;
        --electric)
            DEPLOY_FRONTEND=false
            DEPLOY_BACKEND=false
            DEPLOY_ELECTRIC=true
            shift
            ;;
        --with-electric)
            WITH_ELECTRIC=true
            shift
            ;;
        --electric-clear-cache)
            DEPLOY_FRONTEND=false
            DEPLOY_BACKEND=false
            DEPLOY_ELECTRIC=true
            ELECTRIC_CLEAR_CACHE=true
            shift
            ;;
        --migrate)
            RUN_MIGRATIONS=true
            shift
            ;;
        --check-only)
            CHECK_ONLY=true
            shift
            ;;
        --logs)
            FOLLOW_LOGS=true
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --all              Deploy both frontend and backend (default)"
            echo "  --frontend         Deploy frontend only"
            echo "  --backend          Deploy backend only"
            echo "  --electric         Restart ElectricSQL only (safe restart)"
            echo "  --with-electric    Also restart ElectricSQL when deploying backend"
            echo "  --electric-clear-cache  Restart Electric and clear shape cache"
            echo "  --migrate          Run database migrations"
            echo "  --check-only       Only check status, don't deploy"
            echo "  --logs             Follow logs after deployment"
            echo "  --help             Show this help message"
            echo ""
            echo "Production Details:"
            echo "  Server:        ${SERVER}"
            echo "  Backend:       ${DEPLOY_PATH}"
            echo "  Frontend:      ${FRONTEND_PATH}"
            echo "  Electric:      ${ELECTRIC_CONTAINER}"
            echo "  URL:           ${SITE_URL}"
            echo ""
            echo "ElectricSQL Notes:"
            echo "  - Uses 'docker restart' for safe restarts (preserves database)"
            echo "  - Use --electric-clear-cache after schema changes"
            echo "  - Check status: curl ${ELECTRIC_URL}/v1/health"
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

# Navigate to project root
cd "$(dirname "$0")/../.."

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Sertantai Enforcement - Production Deployment${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Server:${NC} ${SERVER}"
echo -e "${YELLOW}URL:${NC} ${SITE_URL}"

# Show what will be deployed
if [ "$DEPLOY_ELECTRIC" = true ]; then
    if [ "$ELECTRIC_CLEAR_CACHE" = true ]; then
        echo -e "${YELLOW}Deploying:${NC} ElectricSQL (with cache clear)"
    else
        echo -e "${YELLOW}Deploying:${NC} ElectricSQL only"
    fi
elif [ "$DEPLOY_FRONTEND" = true ] && [ "$DEPLOY_BACKEND" = true ]; then
    if [ "$WITH_ELECTRIC" = true ]; then
        echo -e "${YELLOW}Deploying:${NC} Full stack (frontend + backend + electric)"
    else
        echo -e "${YELLOW}Deploying:${NC} Full stack (frontend + backend)"
    fi
elif [ "$DEPLOY_FRONTEND" = true ]; then
    echo -e "${YELLOW}Deploying:${NC} Frontend only"
elif [ "$DEPLOY_BACKEND" = true ]; then
    if [ "$WITH_ELECTRIC" = true ]; then
        echo -e "${YELLOW}Deploying:${NC} Backend + ElectricSQL"
    else
        echo -e "${YELLOW}Deploying:${NC} Backend only"
    fi
fi
echo ""

# Check SSH connectivity
echo -e "${BLUE}Checking SSH connection to ${SERVER}...${NC}"
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "${SERVER}" "echo 'SSH OK'" > /dev/null 2>&1; then
    echo -e "${RED}✗ Cannot connect to ${SERVER}${NC}"
    echo -e "${YELLOW}  Check your SSH configuration and try again${NC}"
    exit 1
fi
echo -e "${GREEN}✓ SSH connection OK${NC}"
echo ""

# ============================================================
# CHECK-ONLY MODE
# ============================================================
if [ "$CHECK_ONLY" = true ]; then
    echo -e "${BLUE}Checking production status...${NC}"
    echo ""

    if [ "$DEPLOY_BACKEND" = true ] || [ "$DEPLOY_ELECTRIC" = true ]; then
        echo -e "${BLUE}Backend Status:${NC}"
        ssh "${SERVER}" "cd ${DEPLOY_PATH} && docker compose ps ${SERVICE_NAME}" || echo "  Backend not running"
        echo ""

        echo -e "${BLUE}ElectricSQL Status:${NC}"
        ssh "${SERVER}" "docker ps --filter name=${ELECTRIC_CONTAINER} --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" || echo "  Electric not running"

        # Check Electric health
        ELECTRIC_HEALTH=$(ssh "${SERVER}" "curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/v1/health" 2>/dev/null || echo "000")
        if [ "$ELECTRIC_HEALTH" = "200" ]; then
            echo -e "  ${GREEN}✓${NC} Electric health check passed (HTTP 200)"
        else
            echo -e "  ${YELLOW}⚠${NC} Electric health check returned HTTP ${ELECTRIC_HEALTH}"
        fi
        echo ""
    fi

    if [ "$DEPLOY_FRONTEND" = true ]; then
        echo -e "${BLUE}Frontend Status:${NC}"
        if ssh "${SERVER}" "[ -d ${FRONTEND_PATH} ]"; then
            FRONTEND_FILES=$(ssh "${SERVER}" "find ${FRONTEND_PATH} -type f | wc -l")
            FRONTEND_SIZE=$(ssh "${SERVER}" "du -sh ${FRONTEND_PATH}" 2>/dev/null | cut -f1)
            echo -e "  ${GREEN}✓${NC} Frontend deployed: ${FRONTEND_FILES} files (${FRONTEND_SIZE})"
            if ssh "${SERVER}" "[ -f ${FRONTEND_PATH}/index.html ]"; then
                echo -e "  ${GREEN}✓${NC} index.html present"
            else
                echo -e "  ${YELLOW}⚠${NC} index.html missing"
            fi
        else
            echo -e "  ${YELLOW}⚠${NC} Frontend directory not found"
        fi
        echo ""
    fi

    if [ "$DEPLOY_BACKEND" = true ]; then
        echo -e "${BLUE}Recent Backend Logs:${NC}"
        ssh "${SERVER}" "cd ${DEPLOY_PATH} && docker compose logs --tail=15 ${SERVICE_NAME}" 2>/dev/null || echo "  No logs available"
    fi

    echo ""
    echo -e "${GREEN}Status check complete${NC}"
    exit 0
fi

# Track deployment success
FRONTEND_SUCCESS=true
BACKEND_SUCCESS=true
ELECTRIC_SUCCESS=true

# ============================================================
# DEPLOY FRONTEND
# ============================================================
if [ "$DEPLOY_FRONTEND" = true ]; then
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│  Deploying Frontend                                     │${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────┘${NC}"
    echo ""

    # Check build exists
    if [ ! -d "${BUILD_DIR}" ]; then
        echo -e "${RED}✗ Frontend build not found: ${BUILD_DIR}${NC}"
        echo -e "${YELLOW}  Build first: ./scripts/deployment/build-frontend.sh${NC}"
        FRONTEND_SUCCESS=false
    else
        FILE_COUNT=$(find "${BUILD_DIR}" -type f | wc -l)
        if [ "$FILE_COUNT" -eq 0 ]; then
            echo -e "${RED}✗ Frontend build is empty${NC}"
            FRONTEND_SUCCESS=false
        else
            # Deploy using deploy-frontend.sh
            if ./scripts/deployment/deploy-frontend.sh; then
                echo -e "${GREEN}✓ Frontend deployed${NC}"
            else
                echo -e "${RED}✗ Frontend deployment failed${NC}"
                FRONTEND_SUCCESS=false
            fi
        fi
    fi
    echo ""
fi

# ============================================================
# DEPLOY BACKEND
# ============================================================
if [ "$DEPLOY_BACKEND" = true ]; then
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│  Deploying Backend                                      │${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────┘${NC}"
    echo ""

    # Pull latest image
    echo -e "${BLUE}[1/4] Pulling latest image from GHCR...${NC}"
    if ssh "${SERVER}" "cd ${DEPLOY_PATH} && docker compose pull ${SERVICE_NAME}"; then
        echo -e "${GREEN}✓ Image pulled successfully${NC}"
    else
        echo -e "${RED}✗ Failed to pull image${NC}"
        BACKEND_SUCCESS=false
    fi
    echo ""

    if [ "$BACKEND_SUCCESS" = true ]; then
        # Check migration status
        echo -e "${BLUE}[2/4] Checking migration status...${NC}"
        ssh "${SERVER}" "cd ${DEPLOY_PATH} && docker compose exec -T ${SERVICE_NAME} /app/bin/ehs_enforcement eval 'EhsEnforcement.Release.status'" 2>/dev/null || {
            echo -e "${YELLOW}⚠ Could not check migration status (container may not be running)${NC}"
        }
        echo ""

        # Run migrations if requested
        if [ "$RUN_MIGRATIONS" = true ]; then
            echo -e "${BLUE}[3/4] Running migrations...${NC}"
            if ssh "${SERVER}" "cd ${DEPLOY_PATH} && docker compose exec -T ${SERVICE_NAME} /app/bin/ehs_enforcement eval 'EhsEnforcement.Release.migrate'"; then
                echo -e "${GREEN}✓ Migrations complete${NC}"
            else
                echo -e "${RED}✗ Migration failed${NC}"
                echo -e "${YELLOW}  Check logs for details${NC}"
                BACKEND_SUCCESS=false
            fi
            echo ""
        else
            echo -e "${YELLOW}[3/4] Skipping migrations (use --migrate to run)${NC}"
            echo ""
        fi
    fi

    if [ "$BACKEND_SUCCESS" = true ]; then
        # Restart container
        echo -e "${BLUE}[4/4] Restarting container...${NC}"
        if ssh "${SERVER}" "cd ${DEPLOY_PATH} && docker compose up -d ${SERVICE_NAME}"; then
            echo -e "${GREEN}✓ Container restarted${NC}"
        else
            echo -e "${RED}✗ Failed to restart container${NC}"
            BACKEND_SUCCESS=false
        fi
        echo ""

        # Wait and check health
        if [ "$BACKEND_SUCCESS" = true ]; then
            echo -e "${BLUE}Waiting for startup...${NC}"
            sleep 5

            echo -e "${BLUE}Checking health endpoint...${NC}"
            HEALTH_CHECK=$(ssh "${SERVER}" "curl -s -o /dev/null -w '%{http_code}' http://localhost:4002/health" || echo "000")

            if [ "$HEALTH_CHECK" = "200" ]; then
                echo -e "${GREEN}✓ Health check passed (HTTP 200)${NC}"
            else
                echo -e "${YELLOW}⚠ Health check returned HTTP ${HEALTH_CHECK}${NC}"
                echo -e "${YELLOW}  The application may still be starting up${NC}"
            fi
            echo ""
        fi
    fi
fi

# ============================================================
# DEPLOY ELECTRICSQL
# ============================================================
# Deploy Electric if --electric flag is set, or --with-electric with backend
if [ "$DEPLOY_ELECTRIC" = true ] || ([ "$WITH_ELECTRIC" = true ] && [ "$DEPLOY_BACKEND" = true ]); then
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│  Deploying ElectricSQL                                  │${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────┘${NC}"
    echo ""

    # CRITICAL: Use docker restart, NOT docker-compose up
    # docker-compose up can recreate dependent containers and WIPE the database!

    if [ "$ELECTRIC_CLEAR_CACHE" = true ]; then
        echo -e "${BLUE}[1/3] Stopping Electric container...${NC}"
        if ssh "${SERVER}" "docker stop ${ELECTRIC_CONTAINER}" 2>/dev/null; then
            echo -e "${GREEN}✓ Container stopped${NC}"
        else
            echo -e "${YELLOW}⚠ Container was not running${NC}"
        fi
        echo ""

        echo -e "${BLUE}[2/3] Removing container and clearing cache...${NC}"
        ssh "${SERVER}" "docker rm ${ELECTRIC_CONTAINER}" 2>/dev/null || true
        # Note: Volume removal would be: docker volume rm VOLUME_NAME
        # But we recreate container which clears in-memory cache
        echo -e "${GREEN}✓ Container removed (cache will be cleared on restart)${NC}"
        echo ""

        echo -e "${BLUE}[3/3] Recreating Electric container (safe - no deps)...${NC}"
        # Use --no-deps to prevent recreating PostgreSQL!
        if ssh "${SERVER}" "cd ${DEPLOY_PATH} && docker compose up -d sertantai-enforcement-electric --no-deps"; then
            echo -e "${GREEN}✓ Electric container recreated${NC}"
        else
            echo -e "${RED}✗ Failed to recreate Electric container${NC}"
            ELECTRIC_SUCCESS=false
        fi
    else
        echo -e "${BLUE}[1/1] Restarting Electric container (safe restart)...${NC}"
        # Safe restart - preserves database, just restarts Electric
        if ssh "${SERVER}" "docker restart ${ELECTRIC_CONTAINER}"; then
            echo -e "${GREEN}✓ Electric container restarted${NC}"
        else
            echo -e "${RED}✗ Failed to restart Electric container${NC}"
            echo -e "${YELLOW}  Container may not exist. Try --electric-clear-cache to recreate.${NC}"
            ELECTRIC_SUCCESS=false
        fi
    fi
    echo ""

    # Wait and check Electric health
    if [ "$ELECTRIC_SUCCESS" = true ]; then
        echo -e "${BLUE}Waiting for Electric startup...${NC}"
        sleep 3

        echo -e "${BLUE}Checking Electric health...${NC}"
        ELECTRIC_HEALTH=$(ssh "${SERVER}" "curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/v1/health" 2>/dev/null || echo "000")

        if [ "$ELECTRIC_HEALTH" = "200" ]; then
            echo -e "${GREEN}✓ Electric health check passed (HTTP 200)${NC}"
        else
            echo -e "${YELLOW}⚠ Electric health check returned HTTP ${ELECTRIC_HEALTH}${NC}"
            echo -e "${YELLOW}  Electric may still be starting up${NC}"
        fi
        echo ""

        # Show Electric container status
        echo -e "${BLUE}Electric container status:${NC}"
        ssh "${SERVER}" "docker ps --filter name=${ELECTRIC_CONTAINER} --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
        echo ""
    fi
fi

# ============================================================
# SUMMARY
# ============================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ "$FRONTEND_SUCCESS" = true ] && [ "$BACKEND_SUCCESS" = true ] && [ "$ELECTRIC_SUCCESS" = true ]; then
    echo -e "${GREEN}✓ Deployment complete!${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}Application:${NC} ${SITE_URL}"
    echo -e "${YELLOW}API:${NC} ${SITE_URL}/api"
    echo -e "${YELLOW}Health:${NC} ${SITE_URL}/api/health"
    if [ "$DEPLOY_ELECTRIC" = true ] || [ "$WITH_ELECTRIC" = true ]; then
        echo -e "${YELLOW}Electric:${NC} ${ELECTRIC_URL}/v1/health"
    fi
    echo ""

    # Show recent logs if backend was deployed
    if [ "$DEPLOY_BACKEND" = true ]; then
        echo -e "${BLUE}Recent backend logs:${NC}"
        ssh "${SERVER}" "cd ${DEPLOY_PATH} && docker compose logs --tail=10 ${SERVICE_NAME}"
        echo ""
    fi

    # Follow logs if requested
    if [ "$FOLLOW_LOGS" = true ] && [ "$DEPLOY_BACKEND" = true ]; then
        echo -e "${BLUE}Following logs (Ctrl+C to exit)...${NC}"
        echo ""
        ssh "${SERVER}" "cd ${DEPLOY_PATH} && docker compose logs -f ${SERVICE_NAME}"
    else
        echo -e "${BLUE}To follow logs:${NC}"
        echo -e "  ${YELLOW}ssh ${SERVER} 'cd ${DEPLOY_PATH} && docker compose logs -f ${SERVICE_NAME}'${NC}"
        echo ""
    fi
else
    echo -e "${RED}✗ Deployment failed${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    if [ "$DEPLOY_FRONTEND" = true ] && [ "$FRONTEND_SUCCESS" = false ]; then
        echo -e "${RED}  ✗ Frontend deployment failed${NC}"
    fi
    if [ "$DEPLOY_BACKEND" = true ] && [ "$BACKEND_SUCCESS" = false ]; then
        echo -e "${RED}  ✗ Backend deployment failed${NC}"
    fi
    if ([ "$DEPLOY_ELECTRIC" = true ] || [ "$WITH_ELECTRIC" = true ]) && [ "$ELECTRIC_SUCCESS" = false ]; then
        echo -e "${RED}  ✗ ElectricSQL deployment failed${NC}"
    fi
    echo ""
    echo -e "${YELLOW}Check the output above for error details${NC}"
    exit 1
fi
