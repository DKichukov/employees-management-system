#!/bin/bash
echo "Stopping application..."
cd /home/ec2-user/employee-management-system

# Stop containers if docker-compose file exists
if [ -f docker-compose.prod.yml ]; then
  docker-compose -f docker-compose.prod.yml down || true
fi

# Clean up unused Docker resources
docker system prune -f

echo "Application stopped successfully"
