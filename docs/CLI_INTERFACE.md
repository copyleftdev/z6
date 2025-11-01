# Z6 CLI Interface

> "Simple commands, clear output, predictable behavior."

## Command Structure

```bash
z6 <command> [options] [arguments]
```

## Commands

### `z6 run`

Execute a load test scenario.

```bash
z6 run <scenario.toml> [options]
```

**Options:**

- `--seed <number>` — PRNG seed for determinism (default: random)
- `--output <path>` — Output directory (default: `./results/`)
- `--log-level <level>` — Logging level: `error`, `warn`, `info`, `debug` (default: `info`)
- `--live` — Show live metrics during run
- `--no-summary` — Skip summary report
- `--json` — Output metrics as JSON
- `--csv` — Output time-series as CSV

**Examples:**

```bash
# Basic run
z6 run scenario.toml

# Deterministic run with specific seed
z6 run scenario.toml --seed 42

# Run with live metrics
z6 run scenario.toml --live

# Run and output JSON
z6 run scenario.toml --json --output ./results.json
```

**Exit Codes:**

- `0` — Success (all assertions passed)
- `1` — Assertion failure
- `2` — Configuration error
- `3` — Runtime error
- `4` — Internal error

### `z6 replay`

Replay a previous run from event log.

```bash
z6 replay <event.log> [options]
```

**Purpose:** Verify determinism, re-compute metrics, debug issues

**Options:**

- `--verify` — Verify replay matches original (default: true)
- `--output <path>` — New output directory
- `--metrics-only` — Skip replay, just recompute metrics

**Examples:**

```bash
# Verify deterministic replay
z6 replay ./results/events.log --verify

# Recompute metrics only
z6 replay ./results/events.log --metrics-only
```

**Exit Codes:**

- `0` — Replay successful, events match
- `1` — Replay failed, events differ
- `2` — Invalid event log

### `z6 analyze`

Analyze event log without replay.

```bash
z6 analyze <event.log> [options]
```

**Options:**

- `--format <format>` — Output format: `summary`, `json`, `csv` (default: `summary`)
- `--filter <expr>` — Filter events (e.g., `status_code >= 500`)
- `--percentiles <list>` — Custom percentiles (e.g., `50,90,95,99,99.9`)

**Examples:**

```bash
# Basic analysis
z6 analyze ./results/events.log

# JSON output
z6 analyze ./results/events.log --format json

# Filter 5xx errors
z6 analyze ./results/events.log --filter "status_code >= 500"

# Custom percentiles
z6 analyze ./results/events.log --percentiles 25,50,75,90,99
```

### `z6 diff`

Compare two test runs.

```bash
z6 diff <run1> <run2> [options]
```

**Arguments:**

- `<run1>` — First run (directory or event log)
- `<run2>` — Second run (directory or event log)

**Options:**

- `--format <format>` — Output format: `text`, `json` (default: `text`)
- `--threshold <percent>` — Highlight differences > threshold (default: 5%)

**Examples:**

```bash
# Compare two runs
z6 diff ./run1/ ./run2/

# JSON diff
z6 diff ./run1/ ./run2/ --format json

# Highlight differences > 10%
z6 diff ./run1/ ./run2/ --threshold 10
```

**Output:**

```
Comparing run1 vs run2:

Requests: 120,000 → 125,000 (+4.2%)
Success Rate: 99.6% → 99.8% (+0.2pp)

Latency (ms):
  p50: 38.5 → 35.2 (-8.6%) ✓
  p99: 142.7 → 128.3 (-10.1%) ✓

Throughput:
  RPS: 2,000 → 2,083 (+4.2%)

Errors: 500 → 250 (-50.0%) ✓

Legend: ✓ = improved, ✗ = regressed
```

### `z6 validate`

Validate a scenario file without running.

```bash
z6 validate <scenario.toml>
```

**Checks:**

- TOML syntax
- Required fields
- Value ranges
- URL formats
- Schedule logic

**Examples:**

```bash
z6 validate scenario.toml
```

**Output:**

```
✓ Scenario valid
  Name: User API Test
  Duration: 60s
  VUs: 100
  Requests: 4
  Assertions: 3
```

Or:

```
✗ Scenario invalid
  Error: Missing required field 'runtime.vus'
  Line: 12
```

### `z6 version`

Show version information.

```bash
z6 version [options]
```

**Options:**

- `--verbose` — Show build info

**Examples:**

```bash
z6 version
# Output: z6 1.0.0

z6 version --verbose
# Output:
# z6 1.0.0
# Zig: 0.11.0
# Build: 2025-10-31T12:00:00Z
# Commit: abc123
```

### `z6 help`

Show help information.

```bash
z6 help [command]
```

**Examples:**

```bash
z6 help          # General help
z6 help run      # Help for 'run' command
```

## Global Options

Available for all commands:

- `-h, --help` — Show help
- `-v, --version` — Show version
- `--no-color` — Disable colored output
- `--quiet` — Suppress non-error output
- `--verbose` — Verbose logging

## Output Formats

### Summary (Default)

Human-readable summary:

```
Z6 Load Test Results
====================

Duration: 60.0s
Virtual Users: 100

Requests
--------
Total: 120,000
Success: 119,500 (99.6%)
Failed: 500 (0.4%)

Latency (ms)
------------
Min: 5.2
Max: 523.1
Mean: 42.3
p50: 38.5
p90: 67.2
p95: 89.4
p99: 142.7
p999: 318.2

Throughput
----------
RPS: 2,000
Peak RPS: 2,341

Errors
------
Timeouts: 300
Connection Errors: 150
HTTP 5xx: 50

Assertions
----------
✓ p99 latency under 100ms
✓ error rate under 1%
✓ success rate above 99%
```

### JSON

Machine-readable JSON:

```json
{
  "version": "1.0",
  "duration_seconds": 60.0,
  "vus": 100,
  "requests": {
    "total": 120000,
    "success": 119500,
    "failed": 500
  },
  "latency": {
    "min_ns": 5200000,
    "p99_ns": 142700000
  },
  "assertions": [
    {
      "name": "p99 latency under 100ms",
      "passed": true
    }
  ]
}
```

### CSV (Time-Series)

```csv
tick,rps,latency_p50,latency_p99,errors
0,1850,35.2,98.3,2
1000,2100,38.1,105.7,3
...
```

## Environment Variables

- `Z6_LOG_LEVEL` — Default log level
- `Z6_OUTPUT_DIR` — Default output directory
- `Z6_NO_COLOR` — Disable colors (any value)

**Example:**

```bash
export Z6_LOG_LEVEL=debug
export Z6_OUTPUT_DIR=./my_results
z6 run scenario.toml
```

## Configuration File

Global config at `~/.z6/config.toml`:

```toml
[defaults]
log_level = "info"
output_dir = "./results"
no_color = false

[limits]
max_vus = 100000
max_event_log_size_mb = 5000
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Assertion failure |
| 2 | Configuration error (invalid scenario) |
| 3 | Runtime error (network, timeout, etc.) |
| 4 | Internal error (bug in Z6) |
| 130 | SIGINT (Ctrl+C) |

## Signal Handling

- `SIGINT` (Ctrl+C) — Graceful shutdown, flush event log
- `SIGTERM` — Graceful shutdown
- `SIGKILL` — Immediate termination (event log may be incomplete)

On graceful shutdown:

```
^C
Received SIGINT, shutting down gracefully...
Flushing event log...
Computing metrics...
Done.
```

## Progress Indicators

### Live Mode

When `--live` is enabled:

```
Z6 Running...  [30s / 60s]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 50%

VUs: 100
RPS: 2,034
Latency p99: 89.2ms
Errors: 12 (0.06%)
```

Updates every second.

### Non-Live Mode

Periodic updates:

```
[10s] 20,000 requests, 1,999 RPS, p99=92ms
[20s] 40,000 requests, 2,001 RPS, p99=88ms
[30s] 60,000 requests, 2,003 RPS, p99=91ms
...
```

## Logging

Log levels:

- `error` — Only errors
- `warn` — Errors and warnings
- `info` — Normal operation (default)
- `debug` — Detailed debugging

Logs go to stderr, results to stdout.

**Example:**

```bash
# Redirect output
z6 run scenario.toml --json > results.json 2> run.log
```

## Shell Completion

Generate completion scripts:

```bash
# Bash
z6 completion bash > /etc/bash_completion.d/z6

# Zsh
z6 completion zsh > ~/.zsh/completions/_z6

# Fish
z6 completion fish > ~/.config/fish/completions/z6.fish
```

## Examples

### Run and Save Results

```bash
z6 run api_test.toml --output ./results/$(date +%Y%m%d_%H%M%S)/
```

### Deterministic Run with Replay Verification

```bash
# Run with seed
z6 run scenario.toml --seed 42 --output ./run1/

# Replay and verify
z6 replay ./run1/events.log --verify

# Should output: ✓ Replay successful, events match
```

### CI/CD Integration

```bash
#!/bin/bash
set -e

# Run load test
z6 run scenario.toml --json --output ./results.json

# Check exit code
if [ $? -ne 0 ]; then
    echo "Load test failed"
    exit 1
fi

# Parse results
p99=$(jq '.latency.p99_ns / 1000000' ./results.json)

if (( $(echo "$p99 > 100" | bc -l) )); then
    echo "p99 latency too high: ${p99}ms"
    exit 1
fi

echo "Load test passed"
```

### Compare Before/After Deployment

```bash
# Before deployment
z6 run scenario.toml --output ./before/

# Deploy new version
./deploy.sh

# After deployment
z6 run scenario.toml --output ./after/

# Compare
z6 diff ./before/ ./after/
```

---

## Summary

Z6's CLI is:

- **Simple** — Few commands, clear purpose
- **Composable** — Unix philosophy, pipeable
- **Deterministic** — Explicit seeds, reproducible
- **CI-friendly** — Exit codes, JSON output

---

**Version 1.0 — October 2025**
