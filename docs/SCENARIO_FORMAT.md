# Z6 Scenario Format

> "Pure declarative. No scripting, no surprises."

## Philosophy

Z6 scenarios are **declarations**, not scripts. They specify:

- What to test (endpoints, payloads)
- How to ramp load (VU schedule)
- What to measure (assertions)

They do NOT contain:

- Arbitrary code execution
- Dynamic control flow
- External dependencies

## File Format

Scenarios are defined in **TOML** for clarity and simplicity.

```toml
[metadata]
name = "API Load Test"
description = "Test user API endpoints"
version = "1.0"

[runtime]
duration_seconds = 60
vus = 100
prng_seed = 42  # For determinism

[target]
base_url = "https://api.example.com"
tls = true
http_version = "http2"

[[requests]]
name = "create_user"
method = "POST"
path = "/api/v1/users"
headers = { "Content-Type" = "application/json" }
body = '''{"name": "TestUser", "email": "test@example.com"}'''
timeout_ms = 5000

[[requests]]
name = "get_user"
method = "GET"
path = "/api/v1/users/123"
timeout_ms = 3000

[schedule]
type = "constant"  # constant, ramp, spike
vus = 100

[assertions]
p99_latency_ms = 100
error_rate_max = 0.01
success_rate_min = 0.99
```

## Metadata Section

```toml
[metadata]
name = "Scenario Name"
description = "What this test does"
version = "1.0"
author = "Alice"
tags = ["api", "production"]
```

All fields are optional but recommended for documentation.

## Runtime Configuration

```toml
[runtime]
# Test duration (mutually exclusive with iterations)
duration_seconds = 60

# Number of virtual users
vus = 100

# Deterministic seed (omit for random)
prng_seed = 42

# Event log settings
event_log_path = "./results/events.log"
flush_interval = 10000  # ticks
```

## Target Configuration

```toml
[target]
# Base URL for all requests
base_url = "https://api.example.com"

# TLS settings
tls = true
verify_cert = true
ca_bundle = "/path/to/ca.pem"  # Optional

# HTTP version preference
http_version = "http2"  # http1.1, http2

# Connection pooling
max_connections = 1000
connection_timeout_ms = 10000
```

## Request Definitions

Each request is declared in a `[[requests]]` block:

```toml
[[requests]]
name = "unique_name"
method = "GET"  # GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS
path = "/api/endpoint"

# Optional headers
headers = { 
    "Content-Type" = "application/json",
    "Authorization" = "Bearer token123"
}

# Optional body (string or file reference)
body = '''{"key": "value"}'''
# OR
body_file = "./payloads/request.json"

# Timeout
timeout_ms = 5000

# Weight (for weighted selection)
weight = 1.0
```

### Request Selection

Requests are selected by weight:

```toml
[[requests]]
name = "read"
method = "GET"
path = "/api/users"
weight = 9.0  # 90% of requests

[[requests]]
name = "write"
method = "POST"
path = "/api/users"
body = '''{"name": "User"}'''
weight = 1.0  # 10% of requests
```

## Schedule Types

### Constant Load

Fixed number of VUs for entire duration:

```toml
[schedule]
type = "constant"
vus = 100
```

### Ramp Up

Gradually increase VUs:

```toml
[schedule]
type = "ramp"
start_vus = 10
end_vus = 1000
ramp_duration_seconds = 60
hold_duration_seconds = 120  # Hold at peak
```

### Spike Test

Sudden load increase:

```toml
[schedule]
type = "spike"
baseline_vus = 100
spike_vus = 1000
spike_start_seconds = 30
spike_duration_seconds = 10
```

### Stepped Ramp

Incremental increases:

```toml
[schedule]
type = "steps"

[[schedule.steps]]
vus = 100
duration_seconds = 30

[[schedule.steps]]
vus = 200
duration_seconds = 30

[[schedule.steps]]
vus = 300
duration_seconds = 30
```

## Assertions

Post-run checks:

```toml
[assertions]
# Latency thresholds (milliseconds)
p50_latency_ms = 50
p90_latency_ms = 100
p99_latency_ms = 200
p999_latency_ms = 500

# Error rates (0.0-1.0)
error_rate_max = 0.01      # Max 1% errors
success_rate_min = 0.99    # Min 99% success

# Throughput
rps_min = 1000             # Minimum requests/second

# Specific status codes
status_5xx_max_rate = 0.001  # Max 0.1% 5xx errors
```

Failed assertions are reported but don't stop the test.

## Think Time

Delay between requests per VU:

```toml
[think_time]
type = "constant"
duration_ms = 1000

# OR random within range
[think_time]
type = "random"
min_ms = 500
max_ms = 2000
```

## Advanced: Multiple Targets

Test multiple endpoints:

```toml
[[targets]]
name = "api"
base_url = "https://api.example.com"
weight = 0.8  # 80% of traffic

[[targets]]
name = "cdn"
base_url = "https://cdn.example.com"
weight = 0.2  # 20% of traffic
```

## Advanced: Request Sequences

Define request ordering per VU:

```toml
[sequence]
type = "ordered"  # Execute requests in order

[[sequence.steps]]
request = "login"
repeat = 1

[[sequence.steps]]
request = "get_profile"
repeat = 5

[[sequence.steps]]
request = "logout"
repeat = 1
```

Each VU executes the sequence, then repeats.

## Validation

Scenarios are validated at load time:

```zig
const ScenarioValidator = struct {
    fn validate(scenario: Scenario) !void {
        // Check required fields
        if (scenario.runtime.duration_seconds == 0 and 
            scenario.runtime.iterations == 0) {
            return error.MissingDuration;
        }
        
        // Check VU count
        if (scenario.runtime.vus == 0) {
            return error.NoVirtualUsers;
        }
        
        // Check requests exist
        if (scenario.requests.len == 0) {
            return error.NoRequests;
        }
        
        // Validate URLs
        for (scenario.requests) |req| {
            try validate_url(req.path);
        }
        
        // Validate weights sum
        var total_weight: f64 = 0;
        for (scenario.requests) |req| {
            total_weight += req.weight;
        }
        if (total_weight == 0) {
            return error.InvalidWeights;
        }
    }
};
```

## Example Scenarios

### Simple GET Stress Test

```toml
[metadata]
name = "Simple GET Test"

[runtime]
duration_seconds = 60
vus = 100

[target]
base_url = "https://example.com"

[[requests]]
name = "homepage"
method = "GET"
path = "/"
timeout_ms = 5000

[schedule]
type = "constant"
vus = 100

[assertions]
p99_latency_ms = 100
error_rate_max = 0.01
```

### API Test with Multiple Endpoints

```toml
[metadata]
name = "User API Test"

[runtime]
duration_seconds = 300
vus = 500
prng_seed = 12345

[target]
base_url = "https://api.example.com"
http_version = "http2"

[[requests]]
name = "list_users"
method = "GET"
path = "/api/v1/users"
weight = 5.0

[[requests]]
name = "get_user"
method = "GET"
path = "/api/v1/users/123"
weight = 3.0

[[requests]]
name = "create_user"
method = "POST"
path = "/api/v1/users"
headers = { "Content-Type" = "application/json" }
body = '''{"name": "Test", "email": "test@example.com"}'''
weight = 1.0

[[requests]]
name = "update_user"
method = "PUT"
path = "/api/v1/users/123"
headers = { "Content-Type" = "application/json" }
body = '''{"name": "Updated"}'''
weight = 1.0

[schedule]
type = "ramp"
start_vus = 50
end_vus = 500
ramp_duration_seconds = 60
hold_duration_seconds = 240

[assertions]
p99_latency_ms = 200
error_rate_max = 0.005
success_rate_min = 0.995
```

### Spike Test

```toml
[metadata]
name = "Spike Test"

[runtime]
duration_seconds = 120
vus = 1000

[target]
base_url = "https://api.example.com"

[[requests]]
name = "endpoint"
method = "GET"
path = "/api/health"
timeout_ms = 3000

[schedule]
type = "spike"
baseline_vus = 100
spike_vus = 1000
spike_start_seconds = 60
spike_duration_seconds = 10

[assertions]
p99_latency_ms = 500  # More lenient during spike
```

## Loading Scenarios

```zig
const ScenarioLoader = struct {
    fn load(path: []const u8) !Scenario {
        const file_contents = try std.fs.cwd().readFileAlloc(
            allocator,
            path,
            10 * 1024 * 1024  // 10MB max
        );
        defer allocator.free(file_contents);
        
        const scenario = try toml.parse(Scenario, file_contents);
        try ScenarioValidator.validate(scenario);
        
        return scenario;
    }
};
```

## Comparison to K6

| K6 | Z6 | Difference |
|----|-----|------------|
| JavaScript code | TOML declaration | No scripting |
| Dynamic logic | Static config | Deterministic |
| `__VU`, `__ITER` | No variables | Simpler |
| `check()` functions | Assertions | Post-run only |
| Modular scripts | Single file | Self-contained |

---

## Summary

Z6 scenarios are:

- **Declarative** — What to test, not how
- **Simple** — TOML, not code
- **Deterministic** — No dynamic behavior
- **Validated** — Errors at load time, not runtime

---

**Version 1.0 — October 2025**
