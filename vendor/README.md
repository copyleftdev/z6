# Vendored Dependencies

This directory contains vendored C/C++ dependencies for Z6.

## Philosophy

Z6 vendors critical dependencies for:

1. **Supply Chain Security** — No external fetches at build time
2. **Reproducibility** — Same source, always
3. **Auditability** — Dependencies are reviewed and tracked
4. **Offline Builds** — No network required

## Planned Dependencies

These will be added in later tasks as features are implemented:

### BoringSSL (TLS Support) — TASK-200+
```
vendor/boringssl/
├── ssl/
├── crypto/
├── LICENSE
└── README.chromium
```

**Purpose:** TLS 1.3 support for HTTPS/HTTP2  
**Version:** To be determined based on audit  
**License:** OpenSSL/ISC-style license

### zlib (HTTP Compression) — TASK-200+
```
vendor/zlib/
├── zlib.c
├── zlib.h
├── LICENSE
└── README
```

**Purpose:** Gzip compression/decompression for HTTP  
**Version:** To be determined  
**License:** zlib License

### HDR Histogram (Metrics) — TASK-400+
```
vendor/hdrhistogram/
├── hdr_histogram.c
├── hdr_histogram.h
├── LICENSE.txt
└── README.md
```

**Purpose:** High Dynamic Range histogram for latency metrics  
**Version:** To be determined  
**License:** BSD/Public Domain

## Audit Process

Before vendoring any dependency:

1. **Security audit** — Review for CVEs and vulnerabilities
2. **Code review** — Understand what code does
3. **License verification** — Ensure compatibility with MIT
4. **Minimal subset** — Only include what's needed
5. **Document provenance** — Track source, version, modifications

## Build Integration

Vendored C/C++ code will be compiled via `build.zig`:

```zig
// Example (not yet implemented):
const boringssl = b.addStaticLibrary(.{
    .name = "boringssl",
    .target = target,
    .optimize = optimize,
});
boringssl.addCSourceFiles(.{
    .root = b.path("vendor/boringssl"),
    .files = &.{
        "ssl/ssl_lib.c",
        "crypto/crypto.c",
        // ... more files
    },
});
exe.linkLibrary(boringssl);
```

## Current Status

**No vendored dependencies yet.** This directory structure is prepared for future tasks.

Core Z6 runtime has **zero external dependencies**.

---

**Last Updated:** TASK-002 (Repository structure preparation)
