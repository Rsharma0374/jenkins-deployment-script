#!/bin/bash
sudo su - jenkins << 'EOF'

echo "Change the directory"
cd /var/lib/jenkins/repository/core

echo "Check if repository already exists"
if [ -d "euruka-service-registry" ]; then
    echo "Repository already exists, moving to directory"
    cd euruka-service-registry
    echo "checkout main branch"
    git checkout main
    echo "pull to the latest code"
    git pull origin main
else
    echo "Repository does not exist, cloning..."
    git clone git@github.com:Rsharma0374/euruka-service-registry.git
    echo "move inside repo"
    cd euruka-service-registry
    echo "checkout main branch"
    git checkout main
    echo "pull to the latest code"
    git pull origin main
fi

echo "Build the project"
mvn clean install

echo "Create deployment directory if not exists"
sudo mkdir -p /opt/deployment
sudo mkdir -p /opt/deployment/eureka-service


echo "Copy jar file to deployment directory"
sudo cp target/service-registry-0.0.1-SNAPSHOT.jar /opt/deployment/eureka-service/

echo "Change directory to deployment location"
cd /opt/
sudo chown jenkins:jenkins deployment/
sudo chown jenkins:jenkins deployment/*
cd deployment/eureka-service

echo "kill existing process"
sudo pkill -f "service-registry-0.0.1-SNAPSHOT.jar"

echo "start the jar with nohup"
nohup java -jar service-registry-0.0.1-SNAPSHOT.jar > /opt/deployment/eureka-service/eurekaServer.log 2>&1 &

echo "restart the nginx"
sudo systemctl restart nginx