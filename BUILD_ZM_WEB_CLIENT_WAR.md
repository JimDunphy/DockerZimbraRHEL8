# Building `zimbra.war` Without a Full Release Build

This is a maintainer and developer reference.

If you are an admin who just needs the latest `10.1.x` asset bundle, use the
one-shot command in [README.md](./README.md):

```bash
./docker.sh --build-war 10.1
```

and deploy the returned `zimbra-<resolved-version>.war` artifact.

That admin path uses a container-local source tree by default and does not
persist `zwc-war` back to the host.

## Goal

This document records the workflow used to build `zm-web-client` and produce
`zimbra.war` inside the Docker-based Oracle Linux 8 environment without running
the full `build_zimbra.sh --version 10.1` release build.

The intent is to:

- build the classic web client war inside the container
- reuse as much of the normal Zimbra build model as possible
- keep a documented path for comparing the war against the full build output

## Environment

- Repository: `DockerZimbraRHEL8`
- Container SSH port: `717`
- Host mount: `./Zimbra` -> `/mnt/zimbra` by default
- Recommended automation path: `docker exec` as the normal container user

For the one-shot `docker.sh --build-war` path, Docker runs the helper inside
the container with `docker exec` and does not require SSH login to the
container. The host-side `./Zimbra` directory is only the bind-mounted
workspace; the returned `zimbra.war` is copied back beside `docker.sh`.

Admin mode uses `/tmp/zwc-war` inside the container. Developer mode uses
`/mnt/zimbra/zwc-war`.

Manual shell work can still be done over SSH if the image was built with a
container login key:

```bash
ssh -p 717 jad@localhost
```

## Helper Script

The helper for this workflow is:

```bash
./build_zm_web_client_war.sh
```

Current behavior:

- `--init` reuses `build_zimbra.sh --init` if the environment is not already present
- normal builds do not install OS packages behind the user's back
- if `ant-contrib` is missing, the helper follows the same jar/bootstrap model used by `zm-build/build.pl`
- when `/mnt/zimbra` is available, the helper defaults its checkout workspace to `/mnt/zimbra/zwc-war`
- `zm-web-client` is built from a clean build tree so metadata tokens are restamped on every run
- `--allow-dirty` can reuse local edits if an existing checkout is already on the resolved tag
- build metadata can be stamped explicitly with:
  - `--build-num`
  - `--build-release`
  - `--build-date`
  - `--build-type`
  - `--build-host`

Important caveat:

- `build_zm_web_client_war.sh --init` depends on `build_zimbra.sh --init`
- this repository ships a copy of `build_zimbra.sh`
- if someone copies only `build_zm_web_client_war.sh` by itself, `--init` may fail until `build_zimbra.sh` is also available
- if needed, `build_zimbra.sh` can be obtained from `https://github.com/JimDunphy/build_zimbra.sh`

Example usage:

```bash
cd /mnt/zimbra
./build_zm_web_client_war.sh --init
./build_zm_web_client_war.sh --version 10.1.16
./build_zm_web_client_war.sh --version 10.1.16 \
  --build-num 1010000 \
  --build-release 20260119141248 \
  --build-date 20260119141248
./build_zm_web_client_war.sh --version 10.1.16 --allow-dirty
```

If `/mnt/zimbra` is mounted, the helper copies the resulting artifact to:

```bash
/mnt/zimbra/zimbra-10.1.16.war
```

The in-tree build artifact remains at:

```bash
/mnt/zimbra/zwc-war/zm-web-client/build/dist/jetty/webapps/zimbra.war
```

## Minimal Repository Set

The direct war build is not a single-repo build. These repositories were needed:

- `zm-build`
  - provides `RE/MAJOR`, `RE/MINOR`, `RE/MICRO`
- `zm-zcs`
  - provides `ant-global.xml` and Ivy settings
- `zm-mailbox`
  - publishes `zm-native`, `zm-common`, `zm-soap`, `zm-client`, `zm-store`
- `zm-taglib`
  - published locally before the war build
- `zm-ajax`
  - published locally before the war build
- `zm-web-client`
  - produces `zimbra.war`

For the validated `10.1.16` build, the resolved tags were:

- `zm-build` -> `10.1.16`
- `zm-zcs` -> `10.1.13`
- `zm-mailbox` -> `10.1.16`
- `zm-taglib` -> `10.1.16`
- `zm-ajax` -> `10.1.16`
- `zm-web-client` -> `10.1.16`

`zm-zcs` fell back to `10.1.13` because that was the highest matching tag at or
below the requested release for that repository.

## Local Development Workflow

For a local edit and rebuild loop, pin an exact version and use
`--developer-mode --allow-dirty`.

Example:

```bash
./docker.sh --build-war 10.1.16 --developer-mode --allow-dirty
```

That allows you to:

- build the war
- test it with Project Z Bridge
- modify files under `./Zimbra/zwc-war`
- rerun the same command without recloning

Important behavior:

- `10.1` is a moving target and is re-resolved from GitHub each run
- `10.1.16` is pinned to that exact release
- `--allow-dirty` requires `--developer-mode`
- `--allow-dirty` only reuses dirty checkouts that are already on the resolved tag
- if GitHub later resolves `10.1` to `10.1.17`, a dirty local `10.1.16` tree is not switched automatically

## Dependency Model

The Docker/container workflow should piggyback on the same dependency model used
by `build_zimbra.sh --init` and `zm-build/build.pl`.

Important distinction:

- `ant-tar-patched` is Zimbra's patched Ant/ziputil piece
- `ant-contrib` is a separate Ant task library jar

On Oracle Linux 8, `zimbra-build-scripts/zimbra-build-helper.sh --install-deps`
does not install the OS `ant-contrib` package. That matters because the direct
war build should not assume a distro package is the only valid source for
`ant-contrib`.

Instead, `zm-build/build.pl` bootstraps jars such as:

- `ant-1.7.0-ziputil-patched-1.0.jar`
- `ant-contrib-1.0b1.jar`

into:

```bash
~/.zcs-deps
```

The helper was adjusted to follow that model instead of assuming Zimbra is
installed or that `ant-contrib` must come from the RPM database.

## Relationship to the Full Build

The full build does not call `prod-war` directly for `zm-web-client`.

`zm-build` stages `zm-web-client` with:

- target `pkg`

and `zm-web-client` defines:

- `pkg` -> `clean-pkg, prod-war, jspc.build`

That means:

- `prod-war` is still the war-producing target
- `pkg` adds packaging work around the war
- `pkg-builder.pl` unpacks `build/dist/jetty/webapps/zimbra.war` into package staging
- `pkg-builder.pl` also adds `build/dist/jetty/work` and template files

Conclusion:

- for the `zimbra.war` file itself, `prod-war` is the right direct artifact
- for package-level parity beyond the war, also compare `build/dist/jetty/work`
  and staged template files

## What We Learned

### 1. A stale full-build war is not a useful comparison target

An older `zm-web-client/build/dist/jetty/webapps/zimbra.war` from a previous
full build can remain in place and look valid. File timestamp and tag must be
checked before comparing sizes or hashes.

### 2. Tag parity matters first

Once both trees were checked, both repos were on:

```bash
10.1.16
```

Do not compare war files from different tags.

### 3. File size alone is not enough

After rebuilding both paths on the same tag, the war sizes were:

- direct war build: `31290586`
- full-build tree war: `31290533`

That is a `53-byte` difference, which is small enough that it should not be
treated as evidence of missing static content by itself.

Likely causes include:

- build-time metadata
- cache-buster values
- generated `web.xml` differences
- ZIP metadata or file ordering

### 4. The right verification is on extracted contents

If raw war size or hash differs, extract both wars and compare contents:

```bash
mkdir -p /tmp/warcmp/a /tmp/warcmp/b
rm -rf /tmp/warcmp/a/* /tmp/warcmp/b/*

cd /tmp/warcmp/a && jar xf /path/to/direct/zimbra.war
cd /tmp/warcmp/b && jar xf /path/to/full-build/zimbra.war

diff -qr /tmp/warcmp/a /tmp/warcmp/b
```

If differences remain, inspect the likely metadata files first:

```bash
diff -u /tmp/warcmp/a/WEB-INF/web.xml /tmp/warcmp/b/WEB-INF/web.xml
diff -u /tmp/warcmp/a/META-INF/MANIFEST.MF /tmp/warcmp/b/META-INF/MANIFEST.MF
```

This is the correct confidence check for the Z-Bridge use case. A tiny raw war
difference is not enough to conclude that the direct build omitted required
static assets.

## Recommended Comparison Workflow

1. Build the direct war with `build_zm_web_client_war.sh --version 10.1.16`
2. Run a fresh `build_zimbra.sh --version 10.1`
3. Confirm both `zm-web-client` trees are on the same tag
4. Compare extracted war contents
5. If needed, compare package-side extras such as `build/dist/jetty/work`

## Current Status

- Container workflow works over SSH on port `717`
- Direct helper script exists and is staged into `~/Zimbra` and the container
- `zimbra.war` was built successfully from the direct workflow
- Direct and full-build war outputs are now close enough that extracted-content
  comparison is the next meaningful step
