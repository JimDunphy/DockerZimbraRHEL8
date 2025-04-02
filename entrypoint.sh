#!/bin/bash

# Fix hosts
/usr/local/bin/fix-hosts.sh

#==================================================================================
# BEGIN BIND9

# Path to named.conf
NAMED_CONF="/etc/named.conf"

# Only add our zone if it’s not already in named.conf
if ! grep -q 'zone "example.com"' $NAMED_CONF; then
  echo "Adding example.com zone to named.conf..."
  cat >> $NAMED_CONF <<EOF

zone "example.com" IN {
    type master;
    file "example.com.zone";
    allow-query { any; };
};
EOF
fi

# --------------------------
# FIX PERMISSIONS FOR BIND
# --------------------------
mkdir -p /run/named /var/named/data /var/named/dynamic
touch /var/named/data/named.run /run/named/session.key /var/named/named.ca
chown -R named:named /run/named /var/named
chmod -R 755 /run/named /var/named
chmod 644 /var/named/data/named.run /run/named/session.key /var/named/named.ca


touch /var/named/data/named.run
touch /var/named/named.ca  # Optional: only if you use root hints
touch /run/named/session.key

chown -R named:named /run/named /var/named
chmod -R 755 /run/named /var/named
chmod 644 /var/named/data/named.run /var/named/named.ca /run/named/session.key

# --------------------------
# DNS ZONE FILE CHECK
# --------------------------
if [ ! -f /var/named/example.com.zone ]; then
  echo "[entrypoint] Creating default example.com zone"
  cat > /var/named/example.com.zone <<EOF
\$TTL 86400
@   IN  SOA mail.example.com. root.example.com. (
        2025032801 ; Serial
        3600       ; Refresh
        1800       ; Retry
        604800     ; Expire
        86400 )    ; Minimum

    IN  NS      mail.example.com.
mail IN  A       $(ip route get 1 | awk '{print $7; exit}')
    IN  MX 10   mail.example.com.
EOF

  chown named:named /var/named/example.com.zone
  chmod 644 /var/named/example.com.zone
fi

# Set DNS resolver to use local bind
# Backup and rewrite /etc/resolv.conf only once
if [ ! -f /etc/resolv.conf.bak ]; then
  echo "Backing up /etc/resolv.conf..."
  cp /etc/resolv.conf /etc/resolv.conf.bak
  echo "search example.com" > /etc/resolv.conf
  echo "nameserver 127.0.0.1" >> /etc/resolv.conf
  echo "# Added by entrypoint to use local bind" >> /etc/resolv.conf
else
  echo "/etc/resolv.conf already modified; skipping"
fi

echo "Starting named..."
/usr/sbin/named -c /etc/named.conf -u named &

# END BIND9
#==================================================================================

#==================================================================================
# BEGIN sshd

# Directory where SSH keys will be stored
SSH_KEYS_DIR="/etc/ssh"
# Path to the tar archive
SSH_KEYS_TAR="/mnt/zimbra/ssh-keys.tar"

# Function to generate SSH host keys
generate_ssh_keys() {
    echo "Generating new SSH host keys..."
    [ ! -f "$SSH_KEYS_DIR/ssh_host_rsa_key" ] && ssh-keygen -q -t rsa -b 4096 -N '' -f "$SSH_KEYS_DIR/ssh_host_rsa_key"
    [ ! -f "$SSH_KEYS_DIR/ssh_host_ecdsa_key" ] && ssh-keygen -q -t ecdsa -b 521 -N '' -f "$SSH_KEYS_DIR/ssh_host_ecdsa_key"
    [ ! -f "$SSH_KEYS_DIR/ssh_host_ed25519_key" ] && ssh-keygen -q -t ed25519 -N '' -f "$SSH_KEYS_DIR/ssh_host_ed25519_key"
}

# Check if the tar file exists
if [ -f "$SSH_KEYS_TAR" ]; then
    echo "Existing SSH host keys archive found. Extracting to $SSH_KEYS_DIR..."
    tar xf "$SSH_KEYS_TAR" -C "$SSH_KEYS_DIR"
else
    echo "No SSH host keys archive found. Generating new keys..."
    generate_ssh_keys
    
    # Create the directory if it doesn't exist
    mkdir -p "$(dirname "$SSH_KEYS_TAR")"
    
    echo "Creating new SSH host keys archive at $SSH_KEYS_TAR..."
    # Create tar archive with the keys
    (cd "$SSH_KEYS_DIR" && tar cf "$SSH_KEYS_TAR" \
        ssh_host_rsa_key ssh_host_rsa_key.pub \
        ssh_host_ecdsa_key ssh_host_ecdsa_key.pub \
        ssh_host_ed25519_key ssh_host_ed25519_key.pub)
    
    # Verify the archive was created
    if [ -f "$SSH_KEYS_TAR" ]; then
        echo "Successfully created SSH host keys archive."
    else
        echo "Warning: Failed to create SSH host keys archive at $SSH_KEYS_TAR"
    fi
fi

# Start sshd in background
echo "Starting sshd in background..."
/usr/sbin/sshd

# END sshd
#==================================================================================

# Always drop into a shell
echo "Container ready. Dropping to bash shell..."
cd /
exec /bin/bash
