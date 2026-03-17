#!/bin/bash
set -e

echo "Setting up NetworkManager D-Bus permissions for container..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (use sudo)"
    exit 1
fi

# Create polkit rules directory if it doesn't exist
mkdir -p /etc/polkit-1/rules.d

# Copy the rule file
cp networkmanager-allow-container.rules /etc/polkit-1/rules.d/50-networkmanager-container.rules
chmod 644 /etc/polkit-1/rules.d/50-networkmanager-container.rules

# Ensure the host has a user 'centroid' with uid 1000
# Or adjust the rule to match your actual username
if ! id -u centroid &>/dev/null; then
    echo "Warning: User 'centroid' does not exist on host."
    echo "Either create it with: sudo useradd -u 1000 centroid"
    echo "Or edit the .rules file to use your actual username"
fi

# Restart polkit to apply changes
if systemctl is-active --quiet polkit; then
    systemctl restart polkit
    echo "Polkit restarted"
elif systemctl is-active --quiet polkitd; then
    systemctl restart polkitd
    echo "Polkitd restarted"
else
    echo "Warning: Could not restart polkit service. You may need to reboot."
fi

echo "Done! The container user should now be able to manage NetworkManager via D-Bus."
echo "Restart your container with: docker-compose up -d flutter"
