#!/bin/bash

# Purpose: place public key on container so that local user can do this:
#
#   % slogin localhost -p 717
#
# This script is run on the container
#
#   /mnt/zimbra/setup_env.sh
#

# Find the first non-root user in /home
TARGET_USER=$(ls /home | head -n1)
USER_HOME="/home/$TARGET_USER"
SSH_DIR="$USER_HOME/.ssh"
BUILD_DIR="$USER_HOME/mybuild"
TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_GID="$(id -g "$TARGET_USER")"

echo "Setting up GitHub SSH keys for $TARGET_USER..."
mkdir -p "$SSH_DIR"
cp /mnt/zimbra/id_* "$SSH_DIR" 2>/dev/null || echo "No SSH keys found in /mnt/zimbra"
chmod 600 "$SSH_DIR"/id_* 2>/dev/null
chown -R "${TARGET_UID}:${TARGET_GID}" "$SSH_DIR"

echo "Setting up build scripts for $TARGET_USER..."
mkdir -p "$BUILD_DIR"
cp /mnt/zimbra/build_zimbra.sh "$BUILD_DIR/" 2>/dev/null || echo "build_zimbra.sh not found in /mnt/zimbra"
cp /mnt/zimbra/build_zm_web_client_war.sh "$BUILD_DIR/" 2>/dev/null || echo "build_zm_web_client_war.sh not found in /mnt/zimbra"
chmod +x "$BUILD_DIR"/build_zimbra.sh "$BUILD_DIR"/build_zm_web_client_war.sh 2>/dev/null
chown -R "${TARGET_UID}:${TARGET_GID}" "$BUILD_DIR"

echo "Environment setup complete."
