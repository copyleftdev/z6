# Implementation Agent

You are implementing a feature or fix for Z6, a deterministic load testing tool written in Zig.

## Before Starting

1. **Verify the task context:**
   ```bash
   git branch --show-current
   gh issue view <TASK-XXX>
   ```

2. **Check acceptance criteria** from the linked issue

3. **Review related code** in the target module

## Implementation Workflow

### Step 1: Write Tests First (TDD)

```bash
# Create or update test file
# Write failing tests that define expected behavior
zig build test  # Should fail
```

### Step 2: Implement Feature

Follow Tiger Style requirements:
- Minimum 2 assertions per function
- All loops must be bounded
- Explicit error handling (no `catch {}`)
- Use sized types (`u32`, `u64`, not `usize`)

### Step 3: Verify Implementation

```bash
zig fmt src/ tests/
zig build test  # Should pass
```

### Step 4: Validate Tiger Style

Check manually:
- [ ] Assertion density satisfied
- [ ] No unbounded loops
- [ ] No silent error handling
- [ ] Memory bounds documented
- [ ] All allocations have corresponding frees

## Code Patterns

### Function Template

```zig
/// Brief description of what this function does.
///
/// Preconditions:
/// - data must not be empty
/// - data.len must not exceed MAX_SIZE
///
/// Postconditions:
/// - Returns valid Result or propagates error
///
/// Errors:
/// - InvalidInput: data is empty or too large
/// - ProcessingFailed: computation failed
pub fn process(data: []const u8) !Result {
    // Precondition assertions
    assert(data.len > 0);
    assert(data.len <= MAX_SIZE);

    const result = try compute(data);

    // Postcondition assertions
    assert(result.isValid());
    return result;
}
```

### Error Handling Pattern

```zig
const file = std.fs.openFile(path, .{}) catch |err| {
    log.err("Failed to open {s}: {}", .{ path, err });
    return error.FileOpenFailed;
};
defer file.close();
```

### Memory Pattern

```zig
const buffer = try allocator.alloc(u8, size);
defer allocator.free(buffer);
// Use buffer...
```

## Commit Message Format

```
feat(<module>): <description> (TASK-XXX)

<detailed explanation if needed>

Closes #<issue-number>
```

## Checklist Before Commit

- [ ] Tests written and passing
- [ ] Code formatted with `zig fmt`
- [ ] Minimum 2 assertions per function
- [ ] All loops bounded
- [ ] No `catch {}` statements
- [ ] Memory properly managed
- [ ] Documentation updated if needed
