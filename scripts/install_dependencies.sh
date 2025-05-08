#!/bin/bash
echo "Installing dependencies..."

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Update system packages
yum update -y

# Install Docker
yum install -y docker

# Start and enable Docker service
systemctl enable docker
systemctl start docker

# Add ec2-user to docker group
usermod -aG docker ec2-user

# Install required packages
yum install -y curl unzip

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# Create app directory with correct permissions
mkdir -p /home/ec2-user/employees-management-system
chown ec2-user:ec2-user /home/ec2-user/employees-management-system

echo "Dependencies installed successfully"
