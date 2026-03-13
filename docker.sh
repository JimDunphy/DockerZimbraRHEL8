#!/bin/bash

#
# Author: Jim Dunphy (4/21/2025)
#
# Purpose:
#     You can run a zimbra install.sh a in this container and/or build an image
#
# Build and/or Run a Docker image running RHEL8 (Oracle 8)
# 
# usage: 
#      ./docker.sh --build
#      ./docker.sh --run
#      ./docker.sh --help
#      ./docker.sh --init     # will create ~/Zimbra mount point, and copy private key to it
#
#  WARNING: ./docker.sh --init will attempt to copy keys including private
#       so inside the container as a localuser can do git commands against github
#       example: 
#           % cd; mkdir mybuild; cd mybuild
#           % git clone https://github.com/JimDunphy/build_zimbra.sh.git
#           % cd build_zimbra.sh
#           % ./build_zimbra.sh --version 10.1
#
# Customization: see Step0 to make any changes
#
#*****************************************************************************************
#  You DO NOT have to run ./docker.sh --init as it's a convience for 1st time users
#*****************************************************************************************
#
# Assumptions:
#   Container will be mail.example.com and will have bind9 zonefile and /etc/hosts
#
# Prerequisite: 
#     - Working from your home account.
#     - A directory named: ~/Zimbra which will be shared and mounted as /mnt/zimbra in the container
#       Preload it with build_zimbra.sh or Zimbra tarballs
#     - ~/.ssh keys have been generated (meaning you have run ssh-keygen.sh at some point) id_rsa.pub
#
# How I use it:
#   ./docker.sh --run
#      this provides a bash root shell.
#   % /mnt/zimbra/setup_jad.sh
#      this cp's my ssh keys I use for github
#      and I create a directory and script where I build zimbra tarballs
#
# Hint: Populate ~/Zimbra with tarballs if you don't want to build a release
#
# docker commands:
#    docker ps -a
#    docker rm zimbra
#    docker.sh --run
#    docker rm zimbra
#    docker.sh rmi zimbra
#    docker images
# Those commands should handle most things a novice faces.
# 

set -e

# Cusomizations
# %%% Step0 
#    Possible changes here
IMAGE_NAME="oracle8/zimbra"
CONTAINER_NAME="zimbra"
USER_NAME="$(id -nu)"			# our local account
SSH_PORT="717"				# slogin localhost -p $SSH_PORT
SSH_KEY="$HOME/.ssh/id_rsa.pub"         # no password to local account on container
ZIMBRA_DIR="$HOME/Zimbra"		# local account shares this with container

show_help() {
  echo "Usage: $0 [--build] [--run] [--help]"
  echo "  --build   Build the Docker image with your SSH key"
  echo "  --run     Run the container attached"
  echo "  --run-detached Run the container in the background"
  echo "  --shell   Open a root shell in the running container"
  echo "  --stop    Stop the running container"
  echo "  --status  Show container status"
  echo "  --resume  Start an existing container"
  echo "  --init    Set up the ~/Zimbra directory with environment files and keys"
  echo "  --purge   docker system prune --volumes"
  echo "  --help    Show this help message"
}

build_image() {
  if [ ! -f "$SSH_KEY" ]; then
    echo "SSH key not found at $SSH_KEY"
    exit 1
  fi

  echo "Copying SSH key to build context..."
  cp "$SSH_KEY" ./id_rsa.pub

  echo "Building Docker image as user '$USER_NAME'..."
  docker build --build-arg USER_NAME="$USER_NAME" -t "$IMAGE_NAME" .

  rm -f id_rsa.pub
  echo "Build complete."
}

run_container() {
  echo "Running container..."
  docker run -it \
    --hostname mail.example.com \
    --name "$CONTAINER_NAME" \
    -e "ZIMBRA_SKIP_DNS_SETUP=${ZIMBRA_SKIP_DNS_SETUP:-0}" \
    -v "$ZIMBRA_DIR":/mnt/zimbra \
    -p $SSH_PORT:22 \
    "$IMAGE_NAME"
}

run_container_detached() {
  echo "Running container in the background..."
  docker run -dit \
    --hostname mail.example.com \
    --name "$CONTAINER_NAME" \
    -e "ZIMBRA_SKIP_DNS_SETUP=${ZIMBRA_SKIP_DNS_SETUP:-0}" \
    -v "$ZIMBRA_DIR":/mnt/zimbra \
    -p $SSH_PORT:22 \
    "$IMAGE_NAME"
}

shell_container() {
  echo "Opening a root shell in $CONTAINER_NAME..."
  docker exec -it "$CONTAINER_NAME" /bin/bash
}

stop_container() {
  echo "Stopping $CONTAINER_NAME..."
  docker stop "$CONTAINER_NAME"
}

status_container() {
  docker ps -a --filter "name=^/${CONTAINER_NAME}$" \
    --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

init_zimbra_dir() {
  echo "Initializing $ZIMBRA_DIR..."
  mkdir -p "$ZIMBRA_DIR"

  echo "Copying setup_env.sh to $ZIMBRA_DIR..."
  cp ./setup_env.sh "$ZIMBRA_DIR/setup_env.sh"
  cp ./build_zimbra.sh "$ZIMBRA_DIR/build_zimbra.sh"
  cp ./build_zm_web_client_war.sh "$ZIMBRA_DIR/build_zm_web_client_war.sh"
  chmod +x "$ZIMBRA_DIR/setup_env.sh" "$ZIMBRA_DIR/build_zimbra.sh" "$ZIMBRA_DIR/build_zm_web_client_war.sh"

  echo "Checking for SSH keys..."
  if [ -f "$HOME/.ssh/id_rsa" ] && [ -f "$HOME/.ssh/id_rsa.pub" ]; then
    echo "Copying SSH keys into $ZIMBRA_DIR (WARNING: contains private key)"
    cp "$HOME/.ssh/id_rsa" "$ZIMBRA_DIR/"
    cp "$HOME/.ssh/id_rsa.pub" "$ZIMBRA_DIR/"
    chmod 600 "$ZIMBRA_DIR/id_rsa"
  else
    echo "SSH keypair not found in ~/.ssh. Please generate or copy your key manually."
  fi

  echo "Writing .gitignore to $ZIMBRA_DIR..."
  cat > "$ZIMBRA_DIR/.gitignore" <<EOF
# Never commit private keys
# precaution only as this be on ~/Zimbra which is mounted by the container
# We don't expect to see a local git repository on that mount point at that level...but????
id_rsa
id_rsa.pub
ssh-keys.tar
EOF

  echo "Initialization complete. You can now run ./docker.sh --build"
}


case "$1" in
  --build)
    build_image
    ;;
  --run)
    run_container
    ;;
  --run-detached)
    run_container_detached
    ;;
  --shell)
    shell_container
    ;;
  --stop)
    stop_container
    ;;
  --status)
    status_container
    ;;
  --resume)
    echo "Starting $CONTAINER_NAME..."
    docker start "$CONTAINER_NAME"
    ;;
  --init)
    init_zimbra_dir
    ;;
  --purge)
    docker system prune --volumes
    ;;
  --help | * )
    show_help
    ;;
esac
