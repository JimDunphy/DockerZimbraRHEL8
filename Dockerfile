FROM oraclelinux:8

RUN dnf clean all && \
    dnf install -y dnf-plugins-core && \
    dnf config-manager --set-enabled \
        ol8_appstream \
        ol8_baseos_latest \
        ol8_codeready_builder && \
    dnf install -y oracle-epel-release-el8 && \
    dnf config-manager --set-enabled ol8_developer_EPEL && \
    dnf module reset -y ant && \
    dnf module enable -y ant:1.10 && \
    dnf upgrade -y && \
    dnf install -y --allowerasing \
        curl \
        hostname \
        wget \
        which \
        sudo \
        git \
        perl \
        perl-Data-Dumper \
        perl-IPC-Cmd \
        ruby \
        gcc \
        gcc-c++ \
        make \
        java-1.8.0-openjdk-devel \
        maven \
        rpm-build \
        createrepo \
        rsync \
        ant \
        junit \
        net-tools \
        bind \
        bind-utils \
        telnet \
        traceroute \
        tcpdump \
        nmap \
        hamcrest-core && \
    dnf remove -y java-11-openjdk* 2>/dev/null || true  # Remove Java 11 if present && \
    alternatives --set java java-1.8.0-openjdk.x86_64  # Force Java 8 as default && \
    dnf clean all

RUN dnf install -y openssh-server && \
    systemctl enable sshd

# Create the $USER_NAME user and add SSH key
ARG USER_NAME
RUN useradd -m $USER_NAME && \
    mkdir -p /home/$USER_NAME/.ssh && \
    chmod 700 /home/$USER_NAME/.ssh

# Copy public key (replace with actual path if different)
COPY id_rsa.pub /home/$USER_NAME/.ssh/authorized_keys

RUN chmod 600 /home/$USER_NAME/.ssh/authorized_keys && \
    chown -R $USER_NAME:$USER_NAME /home/$USER_NAME/.ssh

# Install sudo (if not already installed)
RUN dnf install -y sudo

# Add user '$USER_NAME' to the 'wheel' group
RUN usermod -aG wheel $USER_NAME

# Allow passwordless sudo for '$USER_NAME'
RUN echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USER_NAME && \
    chmod 0440 /etc/sudoers.d/$USER_NAME

# Copy the fix-hosts script
# Set as entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
