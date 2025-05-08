#!/bin/bash
set -e

echo "Starting application..."

# Define application directory and create if it doesn't exist
APP_DIR="/home/ec2-user/employees-management-system"
sudo mkdir -p "$APP_DIR"
sudo chown ec2-user:ec2-user "$APP_DIR"

# Determine AWS region with fallbacks
AWS_REGION=""

# First try environment variables
if [ -z "$AWS_REGION" ]; then
    AWS_REGION=${AWS_DEFAULT_REGION:-}
fi

# If still empty, try instance metadata
if [ -z "$AWS_REGION" ] && command -v curl &>/dev/null; then
    # Try IMDSv2 first
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || true)

    if [ -n "$TOKEN" ]; then
        AWS_REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || true)
    else
        # Fall back to IMDSv1
        AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || true)
    fi
fi

# Final fallback
if [ -z "$AWS_REGION" ]; then
    AWS_REGION="us-east-1"
fi

echo "Using AWS Region: $AWS_REGION"

# Get AWS account ID
AWS_ACCOUNT_ID=""

# Try AWS CLI first (most reliable if configured)
if command -v aws &>/dev/null; then
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)
fi

# If still empty, try instance metadata
if [ -z "$AWS_ACCOUNT_ID" ] && command -v curl &>/dev/null; then
    if [ -n "$TOKEN" ]; then
        AWS_ACCOUNT_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document 2>/dev/null | \
                        grep -o '"accountId" : "[^"]*' | cut -d'"' -f4 || true)
    else
        AWS_ACCOUNT_ID=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document 2>/dev/null | \
                        grep -o '"accountId" : "[^"]*' | cut -d'"' -f4 || true)
    fi
fi

# Determine ECR repository URI
if [ -z "$ECR_REPOSITORY_URI" ]; then
    if [ -n "$AWS_ACCOUNT_ID" ]; then
        # Default app name from your terraform
        APP_NAME="ems-app"
        ECR_REPOSITORY_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${APP_NAME}"
    else
        echo "ERROR: Could not determine AWS account ID. Set ECR_REPOSITORY_URI manually."
        exit 1
    fi
fi

echo "Using ECR repository: $ECR_REPOSITORY_URI"

# Create .env file for docker-compose
cat > "$APP_DIR/.env" << EOF
ECR_REPOSITORY_URI=$ECR_REPOSITORY_URI
DB_USER=root
DB_PASSWORD=root
DB_NAME=employees_management_system
AWS_REGION=$AWS_REGION
EOF

# Create docker-compose.prod.yml if it doesn't exist
if [ ! -f "$APP_DIR/docker-compose.prod.yml" ]; then
    cat > "$APP_DIR/docker-compose.prod.yml" << 'EOF'
services:
  postgres:
    image: postgres:13-alpine
    container_name: ems-db
    ports:
      - "5432:5432"
    environment:
      POSTGRES_USER: \${DB_USER:-root}
      POSTGRES_PASSWORD: \${DB_PASSWORD:-root}
      POSTGRES_DB: \${DB_NAME:-employees_management_system}
    volumes:
      - postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: [ "CMD-SHELL", "pg_isready -U \${DB_USER:-root} -d \${DB_NAME:-employees_management_system}" ]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped
    networks:
      - app-network

  app:
    image: ${ECR_REPOSITORY_URI}:latest
    container_name: ems-app
    ports:
      - "8080:8080"
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/\${DB_NAME:-employees_management_system}
      SPRING_DATASOURCE_USERNAME: \${DB_USER:-root}
      SPRING_DATASOURCE_PASSWORD: \${DB_PASSWORD:-root}
      SPRING_JPA_HIBERNATE_DDL_AUTO: update
      SPRING_JPA_PROPERTIES_HIBERNATE_DIALECT: org.hibernate.dialect.PostgreSQLDialect
    restart: unless-stopped
    networks:
      - app-network

volumes:
  postgres-data:

networks:
  app-network:
EOF
fi

# Set proper permissions
sudo chown ec2-user:ec2-user "$APP_DIR/docker-compose.prod.yml"
sudo chmod 644 "$APP_DIR/docker-compose.prod.yml"

# Go to application directory
cd "$APP_DIR"

# Login to ECR with debug output and retry
echo "Logging in to ECR..."
for i in {1..3}; do
    echo "ECR login attempt $i..."

    # Print AWS identity for debugging
    echo "Current AWS identity:"
    aws sts get-caller-identity || echo "Failed to get identity"

    # Explicitly set region for AWS CLI
    export AWS_DEFAULT_REGION="$AWS_REGION"

    if aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$(echo "$ECR_REPOSITORY_URI" | cut -d'/' -f1)"; then
        echo "Successfully logged in to ECR"
        break
    else
        echo "ECR login attempt $i failed"
        if [ $i -eq 3 ]; then
            echo "ERROR: Failed to log in to ECR after multiple attempts."
            echo "Checking if image already exists locally..."

            if docker image inspect "$ECR_REPOSITORY_URI:latest" &>/dev/null; then
                echo "Image exists locally, proceeding with deployment"
                break
            else
                echo "ERROR: Image does not exist locally and ECR login failed"
                exit 1
            fi
        fi
        sleep 5
    fi
done

# Pull latest image
echo "Pulling latest image from ECR..."
if docker pull "$ECR_REPOSITORY_URI:latest"; then
    echo "Successfully pulled latest image"
else
    echo "WARNING: Failed to pull image, will attempt to use cached version"

    # Check if image exists locally
    if ! docker image inspect "$ECR_REPOSITORY_URI:latest" &>/dev/null; then
        echo "ERROR: Image does not exist locally and could not be pulled"
        exit 1
    fi
fi

# Start containers
echo "Starting containers..."
if docker-compose -f docker-compose.prod.yml up -d; then
    echo "Application started successfully"
    docker ps
else
    echo "ERROR: Failed to start containers"
    docker-compose -f docker-compose.prod.yml logs
    exit 1
fi
