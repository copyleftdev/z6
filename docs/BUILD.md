# Z6 Build System

> "Simple, reproducible, fast builds."

## Requirements

- **Zig:** 0.11.0 or later
- **OS:** Linux, macOS (Windows support TBD)
- **Memory:** 4 GB RAM minimum for build
- **Disk:** 500 MB for build artifacts

## Quick Start

```bash
# Clone repository
git clone https://github.com/yourorg/z6.git
cd z6

# Build release
zig build -Doptimize=ReleaseFast

# Run tests
zig build test

# Install
zig build install --prefix /usr/local
```

## Build Modes

### Debug

Development build with assertions and debug symbols:

```bash
zig build -Doptimize=Debug
```

- Assertions enabled
- Debug symbols included
- No optimizations
- Slower execution

### ReleaseSafe

Release with runtime safety checks:

```bash
zig build -Doptimize=ReleaseSafe
```

- Bounds checking enabled
- Assertions disabled
- Optimizations enabled
- Recommended for production

### ReleaseFast

Maximum performance:

```bash
zig build -Doptimize=ReleaseFast
```

- No runtime checks
- Maximum optimizations
- Use only if profiled and safe

### ReleaseSmall

Smallest binary size:

```bash
zig build -Doptimize=ReleaseSmall
```

- Size optimizations
- Use for embedded/constrained environments

## Build Targets

### Main Binary

```bash
zig build
```

Produces: `zig-out/bin/z6`

### Tests

```bash
# Unit tests
zig build test

# Integration tests
zig build test-integration

# All tests
zig build test-all
```

### Fuzz Targets

```bash
zig build fuzz-targets
```

Produces:
- `zig-out/bin/fuzz_http1_response`
- `zig-out/bin/fuzz_http2_frame`
- `zig-out/bin/fuzz_event_serialization`
- etc.

### Documentation

```bash
zig build docs
```

Generates API documentation in `zig-out/docs/`

### Coverage

```bash
zig build test -Dcoverage
```

Generates coverage report.

## Build Options

```bash
# Enable LTO (Link-Time Optimization)
zig build -Dlto=true

# Static linking
zig build -Dstatic=true

# Strip debug symbols
zig build -Dstrip=true

# Enable sanitizers
zig build -Dsanitize=address
zig build -Dsanitize=undefined
zig build -Dsanitize=memory

# Specify target
zig build -Dtarget=x86_64-linux-gnu
zig build -Dtarget=aarch64-macos
```

## build.zig

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    // Main executable
    const exe = b.addExecutable(.{
        .name = "z6",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    
    // Dependencies
    const clap = b.dependency("clap", .{});
    exe.addModule("clap", clap.module("clap"));
    
    // Install
    b.installArtifact(exe);
    
    // Tests
    const test_step = b.step("test", "Run unit tests");
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_tests.step);
}
```

## Dependencies

Z6 has minimal dependencies:

### Core (Zero Dependencies)

The core runtime has **no external dependencies**:

- Event log
- Scheduler
- VU management
- Memory management

### Protocol Handlers

- **BoringSSL** — TLS support (vendored)
- **zlib** — HTTP compression (vendored)

### CLI

- **clap** — Argument parsing (Zig package)

### Testing

- **HDR Histogram** — Latency metrics (vendored, C)

All dependencies are either:
- Vendored (included in repo)
- Fetched via Zig package manager
- Audited for supply chain security

## Vendored Dependencies

```
vendor/
├── boringssl/
│   ├── ssl/
│   └── crypto/
├── zlib/
│   └── zlib.c
└── hdrhistogram/
    └── hdr_histogram.c
```

### Why Vendor?

- **Supply chain security** — No external fetches at build time
- **Reproducibility** — Same source, always
- **Auditability** — Dependencies are reviewed
- **Offline builds** — No network required

## Cross-Compilation

### Linux → Windows

```bash
zig build -Dtarget=x86_64-windows-gnu
```

### Linux → macOS

```bash
zig build -Dtarget=x86_64-macos
```

### x86_64 → ARM64

```bash
zig build -Dtarget=aarch64-linux-gnu
```

## Static Linking

Build fully static binary:

```bash
zig build -Dstatic=true -Dtarget=x86_64-linux-musl
```

Useful for:
- Containers (scratch images)
- Portability (no libc dependency)
- Deployment simplicity

## Reproducible Builds

Ensure bit-for-bit reproducible builds:

### 1. Pin Zig Version

```bash
# Use exact Zig version
zig version  # 0.11.0
```

### 2. Pin Dependencies

```zig
// build.zig.zon
.{
    .name = "z6",
    .version = "1.0.0",
    .dependencies = .{
        .clap = .{
            .url = "https://github.com/Hejsil/zig-clap/archive/0.7.0.tar.gz",
            .hash = "1220d17e...",  // Exact hash
        },
    },
}
```

### 3. Verify

```bash
# Build twice
zig build -Doptimize=ReleaseSafe
cp zig-out/bin/z6 z6-build1

zig build clean
zig build -Doptimize=ReleaseSafe
cp zig-out/bin/z6 z6-build2

# Compare
sha256sum z6-build1 z6-build2
# Should be identical
```

## Build Performance

Typical build times on modern hardware:

| Build Type | Time | Notes |
|------------|------|-------|
| Debug | 15s | Full rebuild |
| ReleaseFast | 45s | Full rebuild |
| Incremental | 2-5s | After changes |
| Tests | 30s | All tests |
| Fuzz targets | 60s | All targets |

### Build Cache

Zig caches build artifacts:

```
~/.cache/zig/
├── h/          # Header cache
├── o/          # Object files
└── z/          # Compiled artifacts
```

Clear cache if needed:

```bash
rm -rf ~/.cache/zig/
```

## CI/CD Builds

### GitHub Actions

```yaml
name: Build

on: [push, pull_request]

jobs:
  build:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
        optimize: [Debug, ReleaseSafe]
    
    runs-on: ${{ matrix.os }}
    
    steps:
      - uses: actions/checkout@v3
      
      - uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.11.0
      
      - name: Build
        run: zig build -Doptimize=${{ matrix.optimize }}
      
      - name: Test
        run: zig build test
      
      - name: Upload artifact
        uses: actions/upload-artifact@v3
        with:
          name: z6-${{ matrix.os }}-${{ matrix.optimize }}
          path: zig-out/bin/z6
```

### Docker Build

```dockerfile
FROM alpine:latest AS build

RUN apk add --no-cache curl tar xz

# Install Zig
RUN curl -L https://ziglang.org/download/0.11.0/zig-linux-x86_64-0.11.0.tar.xz | tar -xJ
ENV PATH="/zig-linux-x86_64-0.11.0:$PATH"

WORKDIR /build
COPY . .

RUN zig build -Doptimize=ReleaseSafe -Dstatic=true

FROM scratch
COPY --from=build /build/zig-out/bin/z6 /z6
ENTRYPOINT ["/z6"]
```

## Build Troubleshooting

### Issue: "zig: command not found"

**Solution:** Install Zig from https://ziglang.org/download/

### Issue: Build fails with "OutOfMemory"

**Solution:** Increase system memory or use smaller build:

```bash
zig build -Doptimize=ReleaseSmall
```

### Issue: Tests fail sporadically

**Solution:** Tests may have race conditions (shouldn't happen in Z6):

```bash
zig build test --summary all
```

### Issue: Slow builds

**Solution:** Enable LTO only for release builds:

```bash
# Fast dev builds
zig build -Doptimize=Debug

# Optimized release
zig build -Doptimize=ReleaseFast -Dlto=true
```

## Install

### System-Wide

```bash
zig build install --prefix /usr/local
```

Installs to:
- Binary: `/usr/local/bin/z6`
- Docs: `/usr/local/share/doc/z6/`

### User-Local

```bash
zig build install --prefix ~/.local
```

### Package Managers

#### Homebrew (macOS/Linux)

```ruby
class Z6 < Formula
  desc "Deterministic load testing tool"
  homepage "https://github.com/yourorg/z6"
  url "https://github.com/yourorg/z6/archive/v1.0.0.tar.gz"
  sha256 "..."
  
  depends_on "zig" => :build
  
  def install
    system "zig", "build", "-Doptimize=ReleaseSafe", "--prefix", prefix
  end
  
  test do
    assert_match "z6 1.0.0", shell_output("#{bin}/z6 version")
  end
end
```

#### APT (Debian/Ubuntu)

```bash
# Build .deb package
dpkg-buildpackage -b -uc -us
```

## Development Workflow

### Setup

```bash
git clone https://github.com/yourorg/z6.git
cd z6

# Build debug
zig build

# Run tests on save (using entr)
find src -name '*.zig' | entr -c zig build test
```

### Pre-Commit

```bash
# Format code
zig fmt src/

# Run tests
zig build test

# Run linter (if available)
zig build lint
```

### Release Build

```bash
# Clean
zig build clean

# Build release
zig build -Doptimize=ReleaseSafe -Dstrip=true

# Verify
./zig-out/bin/z6 version

# Package
tar czf z6-1.0.0-linux-x86_64.tar.gz -C zig-out/bin z6
```

---

## Summary

Z6's build system is:

- **Simple** — Standard Zig build
- **Fast** — Incremental compilation
- **Reproducible** — Vendored dependencies
- **Portable** — Cross-compilation support

---

**Version 1.0 — October 2025**
