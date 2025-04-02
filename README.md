# 🐳 Zimbra Build & Run Docker Image

This project provides a Docker-based environment to build and run Zimbra-related tools in a consistent and isolated container, using Oracle Linux 8. It's designed for contributors and developers who want a minimal setup with pre-installed tools like `bind`, `sshd`, Java 8, Maven, Perl, and more. 

## 🚀 Quick Start

This project includes a single unified `docker.sh` script that handles both building and running the Docker container.

### 1. Clone the repository
```bash
git clone https://github.com/your-repo/zimbra-docker.git
cd zimbra-docker
```

### 2. Build the Image
```bash
./docker.sh --build
```

This will:
- Automatically detect your current username.
- Copy your SSH public key from `~/.ssh/id_rsa.pub` to the Docker build context.
- Build the image using that key and your username.

### 3. Run the Container
```bash
./docker.sh --run
```

This will:
- Run the container interactively
- Expose SSH on port 777
- Mount your `~/Zimbra` directory into the container at `/mnt/zimbra`

---

## 🗂️ Volume Mount

The container expects a volume to be mounted at:

```bash
~/Zimbra  ➡️  /mnt/zimbra
```

You should create this directory **before running the container**, e.g.:

```bash
mkdir -p ~/Zimbra
```

You can use this folder to store:

- Zimbra source code or release tarballs
- SSH key archive (`ssh-keys.tar`) generated on first run
- Build artifacts and installation logs

---

## 🔧 Zimbra Build Script

If you're building Zimbra releases, we recommend using [Jim Dunphy's `build_zimbra.sh`](https://github.com/JimDunphy/build_zimbra.sh):

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
docker rm -f zimbra
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

MIT — do what you want, just don't blame us if it eats your homework.

---

### 📦 What This Container Does

- 📨 **Creates a local DNS zone for `example.com`**  
  The container sets up a `mail.example.com` hostname and a BIND9 zone file (`example.com.zone`) on startup. This allows the container to self-resolve DNS entries during Zimbra installation and testing.

- 🔐 **Passwordless `sudo` access**  
  The default user (based on the one running the build script) is granted full `sudo` privileges without requiring a password. This simplifies administrative tasks and testing workflows inside the container.

- 🔁 **Safe for build, install, and re-install workflows**  
  The container is designed for **repeated builds and installs of Zimbra** using local source code or release packages. It does **not** persist user data or configuration between runs unless explicitly mounted into the `~/Zimbra` volume.

> ⚠️ This container is intended for **development and testing purposes only**. It is **not suitable for production use** or running real user services.
