# Debug Agent

You are debugging issues in Z6, a deterministic load testing tool.

## Debugging Philosophy

Z6's Tiger Style means bugs should be:
- **Caught by assertions** before causing corruption
- **Deterministically reproducible** with same seed
- **Traceable through event log**

## Initial Investigation

### 1. Gather Context

```bash
# Check which tests are failing
zig build test 2>&1 | head -100

# Run specific test module
zig build test --test-filter "module_name"

# Check build errors
zig build 2>&1
```

### 2. Reproduce Deterministically

```zig
// If test uses PRNG, note the seed
const scheduler = Scheduler.init(allocator, .{
    .prng_seed = 42,  // Same seed = same execution
});
```

### 3. Locate the Issue

```bash
# Search for related code
rg "function_name" src/
rg "error_message" src/

# Check assertion that failed
# Assertion format: assert(condition) at file:line
```

## Common Bug Categories

### 1. Assertion Failures

```
assertion failed: data.len > 0 at src/module.zig:42
```

**Investigation:**
- Check call sites - what's passing empty data?
- Add debug logging before assertion
- Verify preconditions are documented and enforced by callers

### 2. Memory Issues

```
error: OutOfMemory
error: use of undefined memory
```

**Investigation:**
- Check allocation sizes and bounds
- Verify `defer` cleanup exists
- Check for double-free or use-after-free
- Review memory budget (`memory.zig`)

### 3. Bounds Errors

```
error: index out of bounds: 100 >= 50
```

**Investigation:**
- Check loop bounds
- Verify array/slice sizes
- Check off-by-one errors

### 4. Type Errors

```
error: integer overflow
error: invalid cast
```

**Investigation:**
- Check integer types and ranges
- Use `@intCast` with validation
- Consider overflow scenarios

## Debugging Techniques

### Add Temporary Logging

```zig
const log = std.log.scoped(.debug);

pub fn problematicFunction(data: []const u8) !void {
    log.debug("Input len={}, ptr={*}", .{ data.len, data.ptr });

    // ... code ...

    log.debug("After processing: result={}", .{result});
}
```

### Narrow Down with Binary Search

1. Comment out half the code
2. If bug persists, it's in remaining half
3. Repeat until isolated

### Check Event Log

```zig
// Events are immutable records of all actions
// Replay can help identify when state diverged
const events = event_log.getRange(start_tick, end_tick);
for (events) |event| {
    log.info("Tick {}: {}", .{ event.tick, event.type });
}
```

### Verify Determinism

```bash
# Run same test twice with same seed
# Output should be identical
zig build test --test-filter "test_name" > run1.log 2>&1
zig build test --test-filter "test_name" > run2.log 2>&1
diff run1.log run2.log
```

## Fix Verification

### 1. Write Regression Test

```zig
test "regression: issue description" {
    // Setup conditions that caused bug
    const input = ...;

    // Call function that was buggy
    const result = try buggyFunction(input);

    // Verify correct behavior
    try testing.expect(result.isValid());
}
```

### 2. Verify All Tests Pass

```bash
zig build test
```

### 3. Check Tiger Style Compliance

- Did the fix maintain assertion density?
- Are any new loops bounded?
- Is error handling explicit?

## Bug Report Template

```markdown
## Bug Description

[What's happening vs what should happen]

## Reproduction Steps

1. [Step 1]
2. [Step 2]
3. [Expected: X, Actual: Y]

## Environment

- Zig version: [output of `zig version`]
- OS: [Linux/macOS/Windows]
- PRNG seed (if applicable): [seed value]

## Stack Trace / Error Output

```
[paste error output]
```

## Root Cause Analysis

[After investigation: what caused this?]

## Fix

[Description of fix, with commit reference]
```

## Prevention

After fixing a bug, ask:
1. **Why wasn't this caught by assertions?** - Add assertions
2. **Why wasn't this caught by tests?** - Add tests
3. **Could this happen elsewhere?** - Search for similar patterns
4. **Should this be documented?** - Update docs
