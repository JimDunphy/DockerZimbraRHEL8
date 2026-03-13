# DockerZimbraRHEL8

This repository provides an Oracle Linux 8 Docker environment for:

- building Zimbra releases
- testing Zimbra installs and upgrade behavior
- building static assets for Project Z Bridge, including `zimbra.war`

The container is intended for development and test work. It is not a
production Zimbra runtime.

## Overview

The main entry point is:

```bash
./docker.sh
```

That wrapper handles:

- host-side initialization of `~/Zimbra`
- image builds
- attached container runs
- detached container runs
- opening a root shell in a running container

The default SSH port for the container is `717`.

## Host Mount

The container uses this bind mount:

```text
~/Zimbra -> /mnt/zimbra
```

This mount is used to share:

- helper scripts such as `build_zimbra.sh` and `build_zm_web_client_war.sh`
- SSH material used for Git access
- build artifacts
- logs and other working files you want to keep on the host

## Quick Start

### 1. Initialize the host mount

This creates `~/Zimbra`, copies helper scripts into it, and copies your SSH
keys if they are present.

```bash
./docker.sh --init
```

### 2. Build the Docker image

```bash
./docker.sh --build
```

### 3. Start the container

Attached root shell:

```bash
./docker.sh --run
```

Detached:

```bash
./docker.sh --run-detached
```

Open a root shell in an already-running container:

```bash
./docker.sh --shell
```

If you only need the container for builds and do not need the DNS/BIND setup,
start it like this:

```bash
ZIMBRA_SKIP_DNS_SETUP=1 ./docker.sh --run-detached
```

### 4. SSH into the container

Long-running builds are expected to be run over SSH rather than through the
attached Docker console.

```bash
ssh -p 717 <user>@localhost
```

If you initialized `~/Zimbra`, then inside the container run:

```bash
/mnt/zimbra/setup_env.sh
cd ~/mybuild
```

## Building Zimbra Releases

This container is commonly used with:

```bash
build_zimbra.sh
```

Typical flow inside the container:

```bash
cd ~/mybuild
./build_zimbra.sh --init
./build_zimbra.sh --version 10.1
```

`build_zimbra.sh --init` remains the source of truth for preparing the normal
Zimbra build environment.

## Building `zimbra.war` for Project Z Bridge

This repository also includes:

```bash
build_zm_web_client_war.sh
```

This helper builds the classic web client war without requiring the full
release build.

Typical flow inside the container:

```bash
cd ~/mybuild
./build_zm_web_client_war.sh --init
./build_zm_web_client_war.sh --version 10.1.16
```

The artifact is produced at:

```bash
~/mybuild/zwc-war/zm-web-client/build/dist/jetty/webapps/zimbra.war
```

If `/mnt/zimbra` is mounted, the helper also copies the artifact there.

Detailed notes for that workflow are in:

[BUILD_ZM_WEB_CLIENT_WAR.md](./BUILD_ZM_WEB_CLIENT_WAR.md)

## Notes on the Build Environment

- The Docker image contains Java 8, Ant, Maven, Git, Perl, Ruby, compilers,
  RPM tooling, SSH, and various network/debug utilities.
- The container can be used both for full Zimbra release builds and for direct
  `zm-web-client` war builds.
- The direct war helper is designed to piggyback on the same build model used
  by `build_zimbra.sh --init` and `zm-build/build.pl`.

## Common Commands

Show help:

```bash
./docker.sh --help
```

Remove the container:

```bash
docker rm zimbra
```

Remove the image:

```bash
docker rmi oracle8/zimbra
```

Prune Docker volumes and unused objects:

```bash
./docker.sh --purge
```

## Troubleshooting

If SSH login does not work:

- verify the container is running
- verify port `717` is not blocked or already remapped differently
- verify your public key exists at `~/.ssh/id_rsa.pub` before `./docker.sh --build`

If the `/mnt/zimbra` mount is empty:

- verify `~/Zimbra` exists on the host
- rerun `./docker.sh --init` if needed

If a build behaves differently in the Docker console than over SSH:

- use SSH and treat that as the supported build path

## License

MIT
