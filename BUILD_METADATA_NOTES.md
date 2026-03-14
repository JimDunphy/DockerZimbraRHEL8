# Build Metadata Notes

## Scope

This note records how the direct `zimbra.war` helper now handles the version
and build metadata shown by Project Z Bridge in the About dialog.

The comparison is still between:

- a full `build_zimbra.sh --version 10.1` build
- a direct `zimbra.war` build produced by `build_zm_web_client_war.sh`

## Canonical Build Path

The canonical FOSS release identity still comes from `build_zimbra.sh` and the
`zm-build/build.pl` pipeline.

That path owns:

- the builder ID model
- the incrementing `.build.number`
- the release timestamp used for official builds

Example:

```text
Project Z Bridge (ZWC 10.1.15_GA_1011056 (build 20260119141248))
```

## What Was Wrong In The Direct War Path

The first direct war implementation could build the right static assets but was
reusing an existing `zm-web-client/build` tree.

That mattered because `prod-war` does not fully clean the generated web-client
tree. If `build/WebRoot/js/zimbraMail/share/model/ZmSettings.js` already had
older replaced values in it, the next build would keep those stale values.

That is why the About dialog could show:

```text
Project Z Bridge (ZWC 10.1.16_GA_${zimbra.buildinfo.buildnum}.jad (build jad))
```

The source template still had the right tokens, but the generated file was not
being rebuilt cleanly.

## Current Direct War Behavior

`build_zm_web_client_war.sh` now does two things to fix that:

1. it builds `zm-web-client` from a clean build tree
2. it injects explicit Ant metadata for:
   - `zimbra.buildinfo.version`
   - `zimbra.buildinfo.release`
   - `zimbra.buildinfo.date`
   - `DSTAMP`
   - `TSTAMP`

That means the helper can now stamp usable values into `ZmSettings.js` and the
resulting `zimbra.war`.

Example direct build metadata:

```bash
./build_zm_web_client_war.sh --version 10.1.16 \
  --build-num 1010000 \
  --build-release 20260119141248 \
  --build-date 20260119141248
```

Expected stamped values:

- `CLIENT_VERSION` -> `10.1.16_GA_1010000`
- `CLIENT_RELEASE` -> `20260119141248`
- `CLIENT_DATETIME` -> `20260119-141248`

For Project Z Bridge, that provides the values needed for the About dialog.

## Important Distinction

This does not make the direct war path the authoritative release-number source.

It only means the helper can stamp explicit metadata values into the war when
you already know what values you want to present.

So the distinction remains:

- `build_zimbra.sh` is still the canonical release identity path
- `build_zm_web_client_war.sh` can now stamp compatible metadata when needed

## Current Defaults

For this repository, the helper defaults are currently set to:

- build number: `1010000`
- build release: `20260119141248`

Those defaults exist so Project Z Bridge can present real values in the About
dialog without leaving placeholders unresolved.

If different values are needed later, use the helper options instead of editing
the generated files by hand.

## Practical Guidance

- If you want canonical release identity, use `build_zimbra.sh`.
- If you want a direct `zimbra.war` with usable About metadata, use
  `build_zm_web_client_war.sh` with explicit metadata options.
- If Project Z Bridge only needs the values to be present and stable, the
  direct helper is now sufficient for that use case.
