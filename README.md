# Spatial Field Converter

Bulk-convert Zoom H8 + VRH-8 4-channel ambisonic field recordings into the spatial-mix schema, push to R2 via Cloud Uploader, play back head-tracked in Fascinated Field.

See `docs/superpowers/specs/2026-05-14-spatial-field-converter-v0.1-design.md` for the full design.

## Build

Requires XcodeGen (`brew install xcodegen`) and Xcode 15+.

```bash
xcodegen generate
xcodebuild -scheme SpatialFieldConverter -configuration Debug build
```

## Test

```bash
xcodebuild -scheme SpatialFieldConverter -configuration Debug test
```
