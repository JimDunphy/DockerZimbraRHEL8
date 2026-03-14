# DockerZimbraRHEL8

This repository provides an Oracle Linux 8 Docker environment for:

- building Zimbra releases
- testing Zimbra installs and upgrade behavior
- building static assets for Project Z Bridge, including `zimbra.war`

The container is intended for development and test work. It is not a
production Zimbra runtime.

## Admin Workflow

For most users, this is the only workflow that matters.

Run this from the repository root:

```bash
./docker.sh --build-war 10.1
```

That single command:

1. creates `./Zimbra` inside this repository if needed
2. builds the Docker image if needed
3. starts a temporary container if needed
4. builds `zimbra.war` inside the container using a container-local source tree
5. copies the finished war back beside `docker.sh`
6. prints the host path to the artifact

The returned artifact will be here:

```bash
./zimbra-<resolved-version>.war
```

The important behavior is:

- admins ask for `10.1`
- the script resolves that to the latest available `10.1.x`
- the returned file name tells you the exact resolved version
- deploy that returned file
- for redeploy or rollback, reuse that exact artifact instead of rerunning `10.1`

Notes:

- no SSH login to the container is required for this path
- no preexisting workspace directory is required
- no staged GitHub keys are required for this path
- no packages are installed on the host for this path
- the host-side `./Zimbra` directory is only a bind-mounted workspace
- package installation and compilation happen inside the Docker container
- source checkouts are not copied to the host in this admin mode
- if you want a different local workspace, use `--zimbra-dir /path/to/workdir`

Examples:

```bash
./docker.sh --build-war 10.1
```

Version behavior:

- `10.1` resolves to the latest available `10.1.x` tag
- `10.1` is re-resolved from GitHub on every run, so six months later it may move from `10.1.16` to `10.1.17`
- the returned `zimbra-<resolved-version>.war` is the exact artifact to keep and deploy
- if you need a fixed version instead of the latest one, request an exact version such as `10.1.16`

If a container named `zimbra` already exists with a different mounted
workspace, `docker.sh --build-war` exits without changing it and tells you how
to proceed.

## Developer Workflow

Most admins can ignore this section.

Developer-oriented examples:

```bash
./docker.sh --build-war 10.1.16 --developer-mode
./docker.sh --build-war 10.1.16 --developer-mode --allow-dirty
```

Developer behavior:

- exact versions such as `10.1.16` are pinned
- `--developer-mode` persists the source tree under `./Zimbra/zwc-war`
- `--allow-dirty` requires `--developer-mode`
- `--allow-dirty` reuses local edits only when the existing checkout is already on the resolved tag
- `--allow-dirty` will not switch a dirty checkout to a newer tag
- local source checkouts live under `./Zimbra/zwc-war`

## Overview

The main entry point is:

```bash
./docker.sh
```

That wrapper handles:

- host-side initialization of a repo-local workspace
- image builds
- attached container runs
- detached container runs
- one-shot `zimbra.war` builds
- opening a root shell in a running container

The default SSH port for the container is `717`.

## Host Mount

By default, the container uses this bind mount:

```text
./Zimbra -> /mnt/zimbra
```

This mount is used to share:

- helper scripts such as `build_zimbra.sh` and `build_zm_web_client_war.sh`
- optional SSH material used for Git access
- build artifacts
- logs and other working files you want to keep on the host

This directory is a workspace, not a host install target. The build toolchain,
package installs, and compilation all happen inside the container.

If needed, the mount directory can be overridden with:

```bash
./docker.sh --zimbra-dir /path/to/workdir ...
```

That lets another project use a different local workspace instead of the
repo-local `./Zimbra` default.

## Quick Start

### 1. Initialize the host mount

This creates `./Zimbra` and copies the helper scripts into it.

```bash
./docker.sh --init
```

If you need GitHub SSH keys inside the mounted workspace for other build flows:

```bash
./docker.sh --init --copy-ssh-keys
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

For full release builds and manual work, we recommend SSH vs the attached
Docker console.

```bash
ssh -p 717 <user>@localhost
```

If you initialized the workspace, then inside the container run:

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

If that full-build workflow needs GitHub SSH credentials inside the container,
stage them first with:

```bash
./docker.sh --init --copy-ssh-keys
```

## Maintainer Notes For `zimbra.war`

This repository also includes:

```bash
build_zm_web_client_war.sh
```

This helper builds the classic web client war without running the full release
build.

For the direct `zimbra.war` automation path, Docker now uses `docker exec`
as the normal container user. It does not require SSH login to the container
and does not require staging GitHub keys into the mounted workspace.

The helper also stamps About-dialog metadata into the generated war. The repo
defaults are:

- build number: `1010000`
- build release: `20260119141248`

Those values can be overridden when running `build_zm_web_client_war.sh`
directly with `--build-num`, `--build-release`, and `--build-date`.

When the helper is run inside this container and `/mnt/zimbra` is available, it
now uses `/mnt/zimbra/zwc-war` as its default source workspace. That keeps the
checkout tree under the mounted host workspace instead of under the container
user's home directory.

For local development on the checked-out sources:

```bash
./docker.sh --build-war 10.1.16 --developer-mode --allow-dirty
```

That mode is intended for the loop of:

- build the assets
- test them with Project Z Bridge
- edit files under `./Zimbra/zwc-war`
- rerun the same pinned-version command

It is intentionally conservative:

- it reuses dirty checkouts only if they are already on the resolved tag
- it refuses to switch a dirty checkout from `10.1.16` to a newer tag such as `10.1.17`

`--init` is not a standalone environment bootstrap. It reuses
`build_zimbra.sh --init` when the build environment is not already prepared.
This repository ships a copy of `build_zimbra.sh`. If someone copies only
`build_zm_web_client_war.sh` elsewhere, they should also bring
`build_zimbra.sh` or obtain it from:

```text
https://github.com/JimDunphy/build_zimbra.sh
```

Typical flow inside the container:

```bash
cd /mnt/zimbra
./build_zm_web_client_war.sh --init
./build_zm_web_client_war.sh --version 10.1.16
```

The artifact is produced at:

```bash
/mnt/zimbra/zwc-war/zm-web-client/build/dist/jetty/webapps/zimbra.war
```

If `/mnt/zimbra` is mounted, the helper also copies the artifact there.

For one-shot automation from another project, use:

```bash
./docker.sh --build-war 10.1.16
```

That command:

- initializes the mounted workspace
- ensures a suitable container is available
- runs the war build inside the container as the normal user
- copies the artifact back beside `docker.sh`
- prints the host path to the resulting `zimbra.war`

If you want to use a different workspace than the default repo-local
`./Zimbra`, use:

```bash
./docker.sh --zimbra-dir ./docker-zimbra-work --build-war 10.1.16
```

Detailed notes for that workflow are in:

[BUILD_ZM_WEB_CLIENT_WAR.md](./BUILD_ZM_WEB_CLIENT_WAR.md)

## Notes on the Build Environment

- The Docker image contains Java 8, Ant, Maven, Git, Perl, Ruby, compilers,
  RPM tooling, SSH, and various network/debug utilities.
- The container can be used both for full Zimbra release builds and for direct
  `zm-web-client` war builds.
- The direct war helper is designed to piggyback on the same build model used
  by `build_zimbra.sh --init` and `zm-build/build.pl`.
- Container SSH access is optional. If `~/.ssh/id_rsa.pub` exists when
  `./docker.sh --build` runs, it will be added for container login. If not,
  the image still builds and the war-only workflow still works.

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
- verify your public key existed at `~/.ssh/id_rsa.pub` when `./docker.sh --build` ran,
  or rebuild with `SSH_KEY=/path/to/public_key ./docker.sh --build`

If the `/mnt/zimbra` mount is empty:

- verify `./Zimbra` exists in the repo, or that your overridden `--zimbra-dir`
  path exists on the host
- rerun `./docker.sh --init` if needed

If a build behaves differently in the Docker console than over SSH:

- use SSH and treat that as the supported build path

If you only need `zimbra.war` for Project Z Bridge:

- prefer `./docker.sh --zimbra-dir ./Zimbra --build-war 10.1.16`
- this path does not require SSH login to the container

## License

MIT
