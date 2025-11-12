#!/bin/bash
# Combined script to install Docker and Minikube on Ubuntu ARM64

set -e  # Exit immediately if a command exits with a non-zero status

# ============================
# PART 1: Install Docker
# ============================
echo "------------------------------------------------------------"
echo " Updating package list and upgrading existing packages..."
echo "------------------------------------------------------------"
sudo apt update -y && sudo apt upgrade -y


echo "------------------------------------------------------------"
echo " Installing required packages: ca-certificates, git, curl, open-vm-tools..."
echo "------------------------------------------------------------"
sudo apt install -y ca-certificates git curl open-vm-tools

echo "------------------------------------------------------------"
echo " Installing Docker for ARM architecture..."
echo "------------------------------------------------------------"
# Set up the Docker repository
sudo apt update -y
sudo apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add Docker's official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Set up the stable Docker repository for ARM64 (instead of AMD64)
echo "deb [arch=arm64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update the package index and install Docker
sudo apt update -y
sudo apt install -y docker-ce docker-ce-cli containerd.io

# Start and enable Docker service
sudo systemctl enable --now docker

echo "------------------------------------------------------------"
echo " Docker installation complete!"
echo "------------------------------------------------------------"

# Add the currently logged-in user to the docker group
sudo usermod -aG docker $(whoami)

echo "------------------------------------------------------------"
echo " Installed versions:"
git --version
curl --version | head -n 1
docker --version
echo "------------------------------------------------------------"


# ============================
# PART 2: Install Minikube
# ============================
echo ""
echo "============================================================"
echo " Installing Minikube..."
echo "============================================================"

echo "📦 Downloading latest Minikube for Linux ARM64..."
curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-arm64

echo "🔧 Installing Minikube to /usr/local/bin..."
sudo install minikube-linux-arm64 /usr/local/bin/minikube
rm minikube-linux-arm64

echo "✅ Minikube installation complete!"

echo "🔍 Checking Minikube version..."
minikube version

echo ""
echo "============================================================"
echo "🎉 All done! Docker and Minikube are ready to use."
echo "============================================================"

# Apply group last to avoid interrupting installation with session restart
newgrp docker

