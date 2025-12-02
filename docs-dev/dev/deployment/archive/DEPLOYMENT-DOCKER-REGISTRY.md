# EHS Enforcement Production Deployment - Docker Registry Approach

This guide provides a modern, efficient deployment approach using pre-built Docker containers and a container registry. This eliminates the need to install Erlang/Elixir on the production server and follows Phoenix deployment best practices.

## Overview

**Local Development → Registry → Production Server**

1. **Local**: Build optimized Docker image with compiled Phoenix release
2. **Registry**: Push image to container registry (Docker Hub, GitHub Container Registry, etc.)
3. **Production**: Pull and run pre-built image

## Benefits

- ✅ **No Erlang/Elixir installation** on production server
- ✅ **No source code** on production server
- ✅ **Faster deployments** (no compilation)
- ✅ **Consistent builds** across environments
- ✅ **Smaller attack surface** and better security
- ✅ **Easy rollbacks** with image tags

## Prerequisites

### Local Development Machine
- Check Docker installed
`docker --version`
- Docker compose installed
`docker-compose version`
`sudo curl -L \
   "https://github.com/docker/compose/releases/download/v2.39.1/docker-compose-$(uname -s)-$(uname -m)" \
   -o /usr/local/bin/docker-compose \
   && sudo chmod +x /usr/local/bin/docker-compose`
   Docker Compose Status ✅

     Two versions detected:
     - docker compose (v2.24.6-desktop.1) - Docker Desktop bundled version
     - docker-compose (v2.39.1) - Latest standalone version you just installed

     Recommendation

     For the EHS Enforcement deployment, use the newer standalone version:

     # Use this for all deployment commands
     docker-compose --version  # v2.39.1 ✅

     Why use docker-compose over docker compose:
     - ✅ Latest features and bug fixes (v2.39.1 vs v2.24.6)
     - ✅ More stable for production deployments
     - ✅ Better compatibility with deployment scripts

     Update deployment commands:
     # Instead of: docker compose up -d
     # Use: docker-compose up -d

     # Instead of: docker compose exec app
     # Use: docker-compose exec app

- Phoenix application with working Dockerfile
- Access to container registry

### Production Server
- Ubuntu 20.04+ VPS (minimum 1GB RAM)
- Domain name pointed to server
- Only Docker required (no Erlang/Elixir!)

## Step 1: Container Registry Setup

  ### Option A: Docker Hub (Free)
  ```bash
  # Create account at hub.docker.com
  docker login
  ```

  ### Option B: GitHub Container Registry (Recommended)
  ```bash
  # Create GitHub Personal Access Token with packages:read/write scope
  echo $GITHUB_TOKEN | docker login ghcr.io -u YOUR_USERNAME --password-stdin
  ```

  ### Option C: Private Registry
  ```bash
  # Use your own registry
  docker login your-registry.com
  ```

## Step 2: Local Docker Build Optimization

  `Dockerfile` is at the root of your project.

  Ensure your `Dockerfile` follows Phoenix release best practices:

  ```dockerfile
  # Build stage
  FROM hexpm/elixir:1.18.4-erlang-27.2.4-alpine-3.21.2 AS build

  # Install build dependencies
  RUN apk add --no-cache build-base git python3 curl nodejs npm

  WORKDIR /app

  # Install hex + rebar
  RUN mix local.hex --force && \
      mix local.rebar --force

  # Set build ENV
  ENV MIX_ENV="prod"

  # Install mix dependencies
  COPY mix.exs mix.lock ./
  RUN mix deps.get --only $MIX_ENV
  RUN mkdir config

  # Copy compile-time config files before we compile dependencies
  COPY config/config.exs config/${MIX_ENV}.exs config/
  RUN mix deps.compile

  # Compile assets
  COPY assets assets
  COPY priv priv
  RUN mix assets.deploy

  # Compile the release
  COPY lib lib
  RUN mix compile

  # Changes to config/runtime.exs don't require recompiling the code
  COPY config/runtime.exs config/

  # Copy release files
  COPY rel rel
  RUN mix release

  # Runtime stage
  FROM alpine:3.21.2 AS app

  # Install runtime dependencies
  RUN apk add --no-cache libstdc++ openssl ncurses-libs

  # Create app user
  RUN addgroup -g 1000 -S phoenix && \
      adduser -S phoenix -u 1000 -G phoenix

  WORKDIR /app
  USER phoenix

  # Copy the release from build stage
  COPY --from=build --chown=phoenix:phoenix /app/_build/prod/rel/ehs_enforcement ./

  EXPOSE 4002

  CMD ["bin/ehs_enforcement", "start"]
  ```

  Your Dockerfile now follows Phoenix release best practices with:

  - Latest versions: Elixir 1.18.4, Erlang 27.2.4, Alpine 3.21.2
  - Optimized layer caching: Dependencies installed before copying source code
  - Security: Non-root phoenix user (UID 1000)
  - Multi-stage build: Smaller runtime image (~50MB vs ~500MB)
  - Health checks: Built-in container health monitoring

  🔧 Phoenix Release Best Practices Explained

  Multi-Stage Build Benefits

  1. Build stage: Contains Erlang/Elixir compiler, Node.js, build tools (~500MB)
  2. Runtime stage: Only contains compiled release and runtime libraries (~50MB)
  3. Result: 90% smaller final image, faster deployments

  Layer Optimization Order

  1. Base image and dependencies (changes rarely)
  2. Mix dependencies (changes when mix.exs/mix.lock changes)
  3. Assets (changes when CSS/JS changes)
  4. Application code (changes most frequently)

  Security Features

  - Non-root user: phoenix:phoenix (UID/GID 1000)
  - Minimal runtime: Only essential Alpine packages
  - Health checks: Automatic container restart if unhealthy

## Step 3: Build and Push Pipeline

### Manual Build for Testing
```bash
# Build the image
docker build -t ehs-enforcement:test .
```
🧪 For Testing Locally
`docker build -t ehs-enforcement:test .`
- Creates image tagged as ehs-enforcement:test
- Stored only on your local machine
- Good for testing before pushing to registry
- Won't be available for production deployment

**Here's how to test your Docker build:**

  1️⃣  Build the Test Image

  cd /home/jason/Desktop/ehs-enforcement
  `docker build -t ehs-enforcement:test .`

  2️⃣  Test the Container

  Since your environment variables are in ~/.bashrc, you can pass them to Docker:

  # Test with your current environment variables
  docker run -p 4002:4002 \
    --env DATABASE_URL \
    --env SECRET_KEY_BASE \
    --env AT_UK_E_API_KEY \
    --env GITHUB_CLIENT_ID \
    --env GITHUB_CLIENT_SECRET \
    ehs-enforcement:test

  3️⃣  Alternative: Create a Test Env File

  If you prefer, create a temporary test file:

  # Create test environment file
  cat > .env.test << 'EOF'
  DATABASE_URL=ecto://postgres:postgres@localhost:5432/sertantai_enforcement_dev
  SECRET_KEY_BASE=your_secret_key_here
  PHX_HOST=localhost
  PORT=4002
  PHX_SERVER=true
  EOF

  # Run with env file
  docker run -p 4002:4002 --env-file .env.test ehs-enforcement:test

  4️⃣  Test the Application

  # In another terminal, test the health endpoint
  curl http://localhost:4002/health

  # Or open in browser
  open http://localhost:4002

  5️⃣  Stop the Container

  # Find the container ID
  docker ps

  # Stop it
  docker stop <container_id>

  # Or use Ctrl+C if running in foreground

  🔍 Troubleshooting

  If the container doesn't start, check logs:

  # See what went wrong
  docker logs <container_id>

  # Or run in interactive mode for debugging
  docker run -it --env-file .env.test ehs-enforcement:test bin/ehs_enforcement remote

  This will help you verify the Docker image works before pushing to production!

### Production Build and Push
  You can use both approaches:
  1. Manual for development/testing deployments
  2. Automated for production releases when you tag versions

### Manual Build and Push
  - Used for ad-hoc deployments
  - Developer manually builds and pushes images
  - Good for testing or emergency deployments
  ```bash
  cd ~/Desktop/ehs_enforcement
  # Build for production with 'Dockerfile' in root
  docker build -t ghcr.io/shotleybuilder/ehs-enforcement:latest .
  # Dockerfile called Dockerfile.debian
  docker build -f Dockerfile.debian -t ghcr.io/shotleybuilder/ehs-enforcement:latest .
  # Test locally (optional)
  docker run -p 4002:4002 --env-file .env.local ghcr.io/shotleybuilder/ehs-enforcement:latest

  # Push to registry
  docker push ghcr.io/shotleybuilder/ehs-enforcement:latest
  ```

### Automated with Git Tags
  - Used for versioned releases
  - Automatically triggers when you create git tags
  - Builds both versioned and latest tags
  ```bash
  # Build with version tag
  VERSION=$(git describe --tags --abbrev=0)
  docker build -t ghcr.io/shotleybuilder/ehs-enforcement:$VERSION .
  docker build -t ghcr.io/shotleybuilder/ehs-enforcement:latest .

  # Using this one
  docker build -f Dockerfile.phoenix -t ghcr.io/shotleybuilder/ehs-enforcement:latest .

  # Push both tags
  docker push ghcr.io/shotleybuilder/ehs-enforcement:$VERSION
  docker push ghcr.io/shotleybuilder/ehs-enforcement:latest
  ```

  The Docker build system doesn't have built-in semantic versioning awareness - it rebuilds whenever you run
  the command. However, you can control when you trigger rebuilds:

  Option 1: Only tag major/minor versions
  # Only create git tags for X.Y releases (ignore patch Z)
  git tag v1.2  # Triggers automated build
  # Don't tag v1.2.1, v1.2.2, etc.

  Option 2: CI/CD with semantic filtering
  In GitHub Actions, you could add logic to only build on certain version patterns:
  on:
    push:
      tags:
        - 'v[0-9]+.[0-9]+' # Only X.Y, not X.Y.Z

  Option 3: Manual control
  With manual builds, you simply choose when to rebuild:
  - Code changes to fix bugs → don't rebuild
  - Code changes for new features → rebuild

  For your use case, the simplest approach is to manually decide when changes are significant enough to
  warrant a new deployment, regardless of version numbering.

## Step 4: Production Server Setup

### Minimal Server Preparation
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker (only requirement!)
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
sudo systemctl enable --now docker

# Install optional tools
sudo apt install -y nginx certbot python3-certbot-nginx htop
```

### Create Application Directory
```bash
# Create app directory
sudo mkdir -p /opt/ehs_enforcement
cd /opt/ehs_enforcement

# Create environment file
sudo touch .env.prod
sudo chown $USER:$USER .env.prod
```

## Step 5: Environment Configuration

  ### Generate Secrets
  ```bash
  # On your local machine, generate secrets
  mix phx.gen.secret  # For SECRET_KEY_BASE
  mix phx.gen.secret  # For TOKEN_SIGNING_SECRET
  ```

  ### Configure .env.prod
  ```bash
  # Required Production Variables
  DATABASE_URL=ecto://postgres:password@postgres:5432/ehs_enforcement_prod
  SECRET_KEY_BASE=your-64-char-secret-from-mix-phx-gen-secret
  PHX_HOST=yourdomain.com
  PORT=4002
  TOKEN_SIGNING_SECRET=your-64-char-secret-from-mix-phx-gen-secret

  # GitHub OAuth (required for authentication)
  GITHUB_CLIENT_ID=your-github-oauth-client-id
  GITHUB_CLIENT_SECRET=your-github-oauth-client-secret
  GITHUB_REDIRECT_URI=https://yourdomain.com/auth/user/github/callback

  # GitHub Admin
  GITHUB_REPO_OWNER=your-github-username
  GITHUB_REPO_NAME=your-repo-name
  GITHUB_ACCESS_TOKEN=your-github-personal-access-token
  GITHUB_ALLOWED_USERS=user1,user2,user3

  # Airtable Integration
  AT_UK_E_API_KEY=your-airtable-api-key

  # Database Configuration (for Docker Compose)
  DATABASE_NAME=ehs_enforcement_prod
  DATABASE_USER=postgres
  DATABASE_PASSWORD=your-strong-db-password
  POOL_SIZE=10

  # Enable Phoenix server
  PHX_SERVER=true
  ```

## Step 6: Production Deployment

  ### Create docker-compose.yml
  ```yaml
  # /opt/ehs_enforcement/docker-compose.yml
  version: '3.8'

  services:
    app:
      image: ghcr.io/yourusername/ehs-enforcement:latest
      restart: unless-stopped
      ports:
        - "4002:4002"
      env_file:
        - .env.prod
      depends_on:
        - postgres
      networks:
        - app-network

    postgres:
      image: postgres:16
      restart: unless-stopped
      environment:
        POSTGRES_DB: ${DATABASE_NAME:-ehs_enforcement_prod}
        POSTGRES_USER: ${DATABASE_USER:-postgres}
        POSTGRES_PASSWORD: ${DATABASE_PASSWORD}
      volumes:
        - postgres_data:/var/lib/postgresql/data
        - ./backups:/backups
      networks:
        - app-network

  volumes:
    postgres_data:

  networks:
    app-network:
      driver: bridge
  ```

  ### Deploy Application
  ```bash
  # Pull latest image
  docker pull ghcr.io/yourusername/ehs-enforcement:latest

  # Start services
  docker compose up -d

  # Run database migrations
  docker compose exec app bin/ehs_enforcement eval "EhsEnforcement.Release.migrate"

  # Check status
  docker compose ps
  docker compose logs app
  ```

## Step 7: SSL and Nginx Configuration

  ### SSL Certificate (Let's Encrypt)
  ```bash
  # Install certbot
  sudo apt install certbot python3-certbot-nginx -y

  # Obtain certificate
  sudo certbot --nginx -d yourdomain.com
  ```

  ### Nginx Reverse Proxy
  ```nginx
  # /etc/nginx/sites-available/ehs-enforcement
  server {
      listen 80;
      server_name yourdomain.com;
      return 301 https://$server_name$request_uri;
  }

  server {
      listen 443 ssl http2;
      server_name yourdomain.com;

      ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
      ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;

      # Security headers
      add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
      add_header X-Content-Type-Options nosniff;
      add_header X-Frame-Options DENY;

      location / {
          proxy_pass http://127.0.0.1:4002;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;

          # WebSocket support
          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
      }
  }
  ```

  ```bash
  # Enable site
  sudo ln -s /etc/nginx/sites-available/ehs-enforcement /etc/nginx/sites-enabled/
  sudo nginx -t
  sudo systemctl reload nginx
  ```

## Step 8: Application Updates

  ### Update Deployment
  ```bash
  # Local: Build and push new version
  docker build -t ghcr.io/yourusername/ehs-enforcement:v1.2.3 .
  docker push ghcr.io/yourusername/ehs-enforcement:v1.2.3

  # Production: Deploy update
  cd /opt/ehs_enforcement
  docker pull ghcr.io/yourusername/ehs-enforcement:v1.2.3

  # Update docker-compose.yml to use new tag or pull latest
  docker compose pull
  docker compose up -d

  # Run migrations (includes Ash migrations)
  docker compose exec app /app/bin/ehs_enforcement eval "EhsEnforcement.Release.migrate"

  ```

  ### Rollback Strategy
  ```bash
  # Rollback to previous version
  docker compose exec app bin/ehs_enforcement stop
  docker run -d ghcr.io/yourusername/ehs-enforcement:v1.2.2  # Previous working version
  ```

## Step 9: CI/CD Automation (Optional)

  ### GitHub Actions Example
  ```yaml
  # .github/workflows/deploy.yml
  name: Deploy to Production

  on:
    push:
      tags: ['v*']

  jobs:
    build-and-deploy:
      runs-on: ubuntu-latest
      steps:
        - name: Checkout
          uses: actions/checkout@v4

        - name: Set up Docker Buildx
          uses: docker/setup-buildx-action@v3

        - name: Login to GitHub Container Registry
          uses: docker/login-action@v3
          with:
            registry: ghcr.io
            username: ${{ github.repository_owner }}
            password: ${{ secrets.GITHUB_TOKEN }}

        - name: Build and push
          uses: docker/build-push-action@v5
          with:
            push: true
            tags: |
              ghcr.io/${{ github.repository }}:latest
              ghcr.io/${{ github.repository }}:${{ github.ref_name }}

        - name: Deploy to production
          uses: appleboy/ssh-action@v0.1.5
          with:
            host: ${{ secrets.PROD_HOST }}
            username: ${{ secrets.PROD_USER }}
            key: ${{ secrets.PROD_SSH_KEY }}
            script: |
              cd /opt/ehs_enforcement
              docker compose pull
              docker compose up -d
              docker compose exec -T app bin/ehs_enforcement eval "EhsEnforcement.Release.migrate"
  ```

## Monitoring and Maintenance

  ### Health Checks
  ```bash
  # Application health
  curl https://yourdomain.com/health

  # Container status
  docker compose ps

  # Resource usage
  docker stats

  # Application logs
  docker compose logs -f app

  # Database logs
  docker compose logs -f postgres
  ```

  ### Backup Strategy
  ```bash
  # Automated backup script
  #!/bin/bash
  # /usr/local/bin/backup-ehs-db
  BACKUP_DIR="/opt/ehs_enforcement/backups"
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  FILENAME="backup_${TIMESTAMP}.sql.gz"

  # Create backup
  docker compose -f /opt/ehs_enforcement/docker-compose.yml exec -T postgres \
    pg_dump -U postgres ehs_enforcement_prod | gzip > ${BACKUP_DIR}/${FILENAME}

  # Keep only last 30 days
  find ${BACKUP_DIR} -name "backup_*.sql.gz" -type f -mtime +30 -delete

  echo "Backup completed: ${BACKUP_DIR}/${FILENAME}"
  ```

  ### Resource Requirements

  **Minimum Production Server:**
  - 1 GB RAM (2 GB recommended)
  - 1 CPU core (2 cores recommended)
  - 20 GB disk space
  - Ubuntu 20.04+

  **Recommended Production Server:**
  - 2-4 GB RAM
  - 2 CPU cores
  - 40 GB disk space
  - Load balancer for high availability

## Troubleshooting

  ### Common Issues

  **Container won't start:**
  ```bash
  # Check logs
  docker compose logs app

  # Verify environment
  docker compose exec app env | grep -E "(SECRET_KEY_BASE|DATABASE_URL)"

  # Test database connectivity
  docker compose exec app bin/ehs_enforcement eval "EhsEnforcement.Release.status"
  ```

  **Database connection issues:**
  ```bash
  # Check database status
  docker compose exec postgres pg_isready -U postgres

  # Check database logs
  docker compose logs postgres

  # Test connection from app
  docker compose exec app bin/ehs_enforcement remote
  # Then in IEx: EhsEnforcement.Repo.query("SELECT 1")
  ```

  **Image pull issues:**
  ```bash
  # Login to registry
  docker login ghcr.io

  # Verify image exists
  docker pull ghcr.io/yourusername/ehs-enforcement:latest

  # Check network connectivity
  curl -I https://ghcr.io
  ```

## Security Considerations

  - Use multi-stage Docker builds to minimize image size
  - Run containers as non-root user
  - Regularly update base images
  - Use specific image tags, not just `latest` in production
  - Enable Docker security scanning
  - Limit container network access
  - Use secrets management for sensitive data

## Benefits Over Traditional Deployment

  **This approach vs. installing Erlang/Elixir on server:**

  | Traditional | Docker Registry |
  |-------------|-----------------|
  | Clone source code | No source code |
  | Install Erlang/Elixir | Only Docker |
  | Compile on server | Pre-compiled |
  | ~30 min deploy | ~2 min deploy |
  | Complex rollbacks | Simple rollbacks |
  | Server as build env | Server only runs |

  This modern approach follows Phoenix deployment best practices while providing enterprise-grade deployment patterns used by major platforms like Fly.io, Render, and Railway.

## Running Scripts

```bash
docker compose exec app mkdir -p /app/scripts # needed if image has been pulled
docker compose cp scripts/<script>.exs app:/app/scripts/
docker compose exec app bin/ehs_enforcement remote
Code.eval_file("/app/scripts/<script>.exs")
```
