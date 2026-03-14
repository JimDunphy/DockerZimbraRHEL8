# Build Metadata Notes

## Scope

This note records the decision made around the version/build string shown by
Project Z Bridge when using:

- a full `build_zimbra.sh --version 10.1` build
- a direct `zimbra.war` build produced by `build_zm_web_client_war.sh`

The goal is to avoid revisiting the same discussion later.

## Observed Behavior

### Full build via `build_zimbra.sh`

Example:

```text
Project Z Bridge (ZWC 10.1.15_GA_1011056 (build 20260119141248))
```

This is the canonical format for the FOSS build path used here.

### Direct `zimbra.war` build

Example:

```text
Project Z Bridge (ZWC 10.1.16_GA_${zimbra.buildinfo.buildnum}.jad (build jad))
```

This is not the same metadata contract as the full build.

## What the Full Build Is Doing

`build_zimbra.sh` defines the numbering scheme using:

- `.build.builder`
- `.build.number`

The script documents `.build.number` as:

```text
IIInnnn
```

where:

- `III` is the three-digit builder ID
- `nnnn` is the incrementing build counter

Examples from the script:

- `101` = FOSS and `build_zimbra.sh`
- `102` = VSherwood
- `103` = JDunphy
- `150` = Generic

The full build path passes this metadata into `zm-build/build.pl`, which is why
the final artifact can expose values such as:

- release tag, for example `10.1.15`
- release class, for example `GA`
- FOSS build number, for example `1011056`
- build timestamp, for example `20260119141248`

## What the Direct War Build Is Doing

The direct `zimbra.war` build currently compiles the correct web client assets
for the requested tag, but it does not reproduce the full FOSS metadata path.

That is why the direct build can show:

- the correct ZWC tag, for example `10.1.16`
- but an unresolved or fallback build identifier such as:
  - `${zimbra.buildinfo.buildnum}`
  - `jad`

In other words, it behaves like a local/developer build rather than a canonical
FOSS numbered release build.

## Decision

The important thing for the direct `zimbra.war` path is that the ZWC version is
correct, for example:

- `10.1.15`
- `10.1.16`

The direct `zimbra.war` path does not need to pretend to be a canonical
`build_zimbra.sh` release artifact unless there is a real need to reproduce the
entire metadata pipeline.

So the accepted model is:

- `build_zimbra.sh` remains the authoritative source of release/build identity
- the direct `zimbra.war` helper is acceptable if it reports the correct ZWC tag
- if the full FOSS build stamp is missing, Project Z Bridge should tolerate that
  rather than treating the local war build as a canonical numbered release

## Practical Recommendation

For Project Z Bridge:

- always display the correct ZWC version if available
- display the full FOSS build stamp only when it actually exists
- treat direct/local war builds as a different provenance class from full
  `build_zimbra.sh` release builds

This keeps the UI honest:

- users still see the correct asset version
- canonical FOSS build numbers remain reserved for the full build pipeline

## Why This Was Chosen

Trying to make the direct `zimbra.war` helper emit the same identity string as
`build_zimbra.sh` would require reproducing more of the full metadata contract,
not just building the same static assets.

That extra complexity is not currently justified if the main requirement is:

- correct ZWC version display
- not full release-artifact identity

## Summary

- The direct `zimbra.war` build is useful for generating static assets.
- The full `build_zimbra.sh` build remains the canonical release identity path.
- Showing the correct ZWC tag matters most for the direct build.
- Full FOSS numbering and timestamp metadata should remain associated with the
  full build pipeline.
