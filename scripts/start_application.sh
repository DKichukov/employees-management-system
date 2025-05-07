#!/bin/bash
set -e

echo "Starting application..."
AWS_REGION="eu-central-1"

# Override AWS_REGION if it's explicitly set in the environment
if [ ! -z "$AWS_REGION_OVERRIDE" ]; then
    AWS_REGION="$AWS_REGION_OVERRIDE"
    echo "AWS Region overridden to: $AWS_REGION"
fi
echo "Using AWS Region: $AWS_REGION"

# Try to determine the ECR repository URI dynamically if not set
if [ -z "$ECR_REPOSITORY_URI" ]; then
    # Get the AWS account ID
    AWS_ACCOUNT_ID=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep -oP '(?<="accountId" : ")[^"]*')

    if [ -z "$AWS_ACCOUNT_ID" ]; then
        # Fallback method to get AWS account ID using AWS CLI
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    fi

    # If we get the account ID, try to construct the ECR URI
    if [ ! -z "$AWS_ACCOUNT_ID" ]; then
        # Use a hardcoded repository name that matches your ECR repository
        REPOSITORY_NAME="ems-app"

        # Construct ECR repository URI
        ECR_REPOSITORY_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${REPOSITORY_NAME}"
        echo "Determined ECR repository URI: $ECR_REPOSITORY_URI"
    else
        echo "Could not determine AWS account ID. Using default ECR repository URI."
        # Use the specific ECR repository
        ECR_REPOSITORY_URI="565393040546.dkr.ecr.eu-central-1.amazonaws.com/ems-app"
    fi
fi

echo "Using ECR repository: $ECR_REPOSITORY_URI"

# Check if .env directory exists, if not create it
mkdir -p /home/ec2-user/employees-management-system

# Create .env file for docker-compose
cat > /home/ec2-user/employees-management-system/.env << EOF
ECR_REPOSITORY_URI=$ECR_REPOSITORY_URI
DB_USER=root
DB_PASSWORD=root
DB_NAME=employees_management_system
AWS_REGION=$AWS_REGION
EOF

# Login to AWS ECR (only if we have a valid ECR URI)
if [[ $ECR_REPOSITORY_URI == *.dkr.ecr.*.amazonaws.com/* ]]; then
    echo "Logging in to ECR..."
    aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $(echo $ECR_REPOSITORY_URI | cut -d'/' -f1)

    # Navigate to application directory
    cd /home/ec2-user/employees-management-system

    # Check if we need to pull the image first
    echo "Pulling latest image from ECR..."
    docker pull $ECR_REPOSITORY_URI:latest || echo "Failed to pull image, will attempt to use cached version"
else
    echo "Not using ECR repository, skipping login and pull"
    cd /home/ec2-user/employees-management-system
fi

# Check if docker-compose.prod.yml exists
if [ ! -f docker-compose.prod.yml ]; then
    echo "Creating docker-compose.prod.yml file..."
    cat > docker-compose.prod.yml << 'EOF'
services:
  postgres:
    image: postgres:13-alpine
    container_name: ems-db
    ports:
      - "5432:5432"
    environment:
      POSTGRES_USER: ${DB_USER:-root}
      POSTGRES_PASSWORD: ${DB_PASSWORD:-root}
      POSTGRES_DB: ${DB_NAME:-employees_management_system}
    volumes:
      - postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: [ "CMD-SHELL", "pg_isready -U ${DB_USER:-root} -d ${DB_NAME:-employees_management_system}" ]
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
      SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/${DB_NAME:-employees_management_system}
      SPRING_DATASOURCE_USERNAME: ${DB_USER:-root}
      SPRING_DATASOURCE_PASSWORD: ${DB_PASSWORD:-root}
      SPRING_JPA_HIBERNATE_DDL_AUTO: update
      SPRING_JPA_PROPERTIES_HIBERNATE_DIALECT: org.hibernate.dialect.PostgreSQLDialect
      AWS_REGION: ${AWS_REGION}
    restart: unless-stopped
    networks:
      - app-network

volumes:
  postgres-data:

networks:
  app-network:
EOF
fi

# Start Docker containers
echo "Starting containers..."
docker compose -f docker-compose.prod.yml up -d

echo "Application started successfully"
