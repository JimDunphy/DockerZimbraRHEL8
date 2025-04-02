# 🐳 Zimbra Build & Run Docker Image

This project provides a Docker-based environment to build and run Zimbra-related tools in a consistent and isolated container, using Oracle Linux 8. It's designed for contributors and developers who want a minimal setup with pre-installed tools like `bind`, `sshd`, Java 8, Maven, Perl, and more. See docker.sh for a full description of how this works.

## 🚀 Quick Start

This project includes a single unified `docker.sh` script that handles both building and running the Docker container. It exists do test and debug zimbra installation scripts and or the zimbra build environment. It can install any zimbra release and updates. I use it to debug some forum questions where their envionment is messed up and I am attempting to replicate it to see how zimbra's install or build scripts behave. When the container terminates, all changes made to it are gone. I then repeat the docker.sh --run to start fresh (note: you may have to docker rm zimbra if you have had previous runs).

### 0. Clone the repository
```bash
git clone git@github.com:JimDunphy/DockerZimbraRHEL8.git
cd ZimbraRHEL8
```

### 1. Inital Setup 
This will create a ~/Zimbra directory on the host and populate it. Only needs to be done once.
```bash
% ./docker.sh --init
```

### 2. Build the Image
```bash
% ./docker.sh --build
```

This will:
- Automatically detect your current username.
- Copy your SSH public key from `~/.ssh/id_rsa.pub` to the Docker build context.
- Build the image using that key and your username.
- Setup suid for your current username
- Start bind9 with a delegated mail.example.com and approproiate /etc/hosts so that zimbra installs can be tested with install.sh

### 3. Run the Container
This will leave you with a root shell on the container. if you have previously run ./docker.sh --init, then execute /mnt/zimbra/setup_env.sh
```bash
% ./docker.sh --run
# /mnt/zimbra/setup_env.sh
# su - <username>
```

This will:
- Run the container interactively
- Expose SSH on port 777
- Mount your `~/Zimbra` directory into the container at `/mnt/zimbra`

### 4. slogin to the container
Provided you did the docker.sh --init and ~/Zimbra is populated, you can now do.
```bash
% slogin localhost -p 777
% cd mybuild
% ./build_zimbra.sh --init
% ./build_zimbra.sh --dry-run --version 10.1
```
---

## 🗂️ Volume Mount

The container expects a volume to be mounted at:

```bash
~/Zimbra  ➡️  /mnt/zimbra
```

If you do not do docker.sh --init, you should create this directory **before running the container**, e.g.:

```bash
mkdir -p ~/Zimbra
```

You can use this folder to store:

- Zimbra source code or release tarballs
- SSH key archive (`ssh-keys.tar`) generated on first run
- Build artifacts and installation logs
- Anything you want the container to have access to

---

## 🔧 Zimbra Build Script

If you're building Zimbra releases,  I use this: [`build_zimbra.sh`](https://github.com/JimDunphy/build_zimbra.sh):

```bash
cd /mnt/zimbra
git clone https://github.com/JimDunphy/build_zimbra.sh.git
cd build_zimbra.sh
./build_zimbra.sh --help
```

---

## 🧰 Tools Included in the Image

- Java 8 (OpenJDK)
- Maven, Ant, Git, Perl, Ruby
- GCC, make, RPM tools
- DNS: `bind`, `bind-utils`
- Networking: `telnet`, `traceroute`, `tcpdump`, `nmap`
- SSH server pre-configured
- Sudo (passwordless for the created user)

---

## 🧼 Cleanup

To remove the container (if not using `--rm`):

```bash
docker rm zimbra
```

To remove the image:

```bash
docker rmi oracle8/rhel8
```

---

## 🙋 Troubleshooting

- ❌ **SSH key not found**  
  Make sure your public key exists at `~/.ssh/id_rsa.pub`. The script requires it for user login setup inside the container.

- ⚠️ **Volume not mounted properly**  
  Ensure the `~/Zimbra` folder exists **before** running the container. You can verify it's mounted by checking `/mnt/zimbra` inside the container.

---

## 📜 License

MIT — do what you want with this.

---

### 📦 What This Container Does

- 📨 **Creates a local DNS zone for `example.com`**  
  The container sets up a `mail.example.com` hostname and a BIND9 zone file (`example.com.zone`) on startup. This allows the container to self-resolve DNS entries during Zimbra installation and testing.

- 🔐 **Passwordless `sudo` access**  
  The default user (based on the one running the build script) is granted full `sudo` privileges without requiring a password. This simplifies administrative tasks and testing workflows inside the container.

- 🔁 **Safe for build, install, and re-install workflows**  
  The container is designed for **repeated builds and installs of Zimbra** using local source code or release packages. It does **not** persist user data or configuration between runs unless explicitly mounted into the `~/Zimbra` volume.

> ⚠️ This container is intended for **development and testing purposes only**. It is **not suitable for production use** or running real user services.
