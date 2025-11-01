---
trigger: always_on
description: "Elite-level Zig best practices: safety, security, and performance"
globs: ["*.zig"]
---

# Zig Best Practices & Security Rules

## Memory Safety

<memory_safety>
- **Avoid `@ptrCast` unless absolutely necessary** - Type punning hides bugs
- **Never use `@ptrFromInt` with arbitrary values** - Creates invalid pointers
- **Validate all pointer arithmetic** - Out-of-bounds access is UB
- **Use slices over raw pointers** - Slices carry length information
- **Prefer `std.mem.Allocator` interface** - Abstraction over raw malloc/free
- **Always check allocation results**:
  ```zig
  const buffer = allocator.alloc(u8, size) catch |err| {
      log.err("Allocation failed: {}", .{err});
      return error.OutOfMemory;
  };
  ```
- **Use `defer` for cleanup immediately after allocation**
- **Initialize all memory** - Uninitialized memory is UB
</memory_safety>

## Avoiding `unsafe` Operations

<safety_first>
- **Minimize use of `@intFromPtr`** - Pointer to integer conversion
- **Avoid `@bitCast` unless type layout is identical** - UB if sizes mismatch
- **Never ignore alignment** - Use `@alignOf` and `@alignCast` correctly
- **Validate `@intCast`** - Check for overflow before casting
- **Don't use `@as` to bypass type safety** - Find proper solution
- **Avoid inline assembly** - Last resort only, with extensive testing
- **Never use `unreachable` speculatively** - Only when provably unreachable
- **Validate all `@fieldParentPtr` usage** - Pointer math can go wrong
</safety_first>

## Integer Safety

<integer_safety>
- **Use wrapping operators explicitly** when overflow is intentional:
  - `+%`, `-%`, `*%` for wrapping arithmetic
  - Never rely on undefined overflow behavior
- **Check for overflow in critical paths**:
  ```zig
  const result = @addWithOverflow(a, b);
  if (result[1] != 0) return error.Overflow;
  ```
- **Use sized integers** - `u32`, `i64`, not `usize` unless needed
- **Saturating arithmetic** where appropriate:
  ```zig
  const safe_value = @min(calculated_value, MAX_ALLOWED);
  ```
- **Validate all integer casts**:
  ```zig
  const small: u8 = @intCast(big_value); // panics on overflow in safe modes
  ```
</integer_safety>

## Undefined Behavior Prevention

<ub_prevention>
- **Never access array out of bounds** - Always check indices
- **No null pointer dereference** - Use optionals (`?T`)
- **Avoid signed integer overflow** - Check before arithmetic
- **No use-after-free** - Track lifetimes carefully
- **No uninitialized variables** - Always assign before use
- **Respect alignment requirements** - Use `@alignOf` when needed
- **No data races** - Synchronize shared mutable state
- **Validate all enum values from external sources**:
  ```zig
  const tag = std.meta.intToEnum(MyEnum, raw_value) catch {
      log.err("Invalid enum value: {}", .{raw_value});
      return error.InvalidData;
  };
  ```
</ub_prevention>

## Comptime Best Practices

<comptime_rules>
- **Use `comptime` for validation** - Catch errors at compile time
- **Comptime assertions** for invariants:
  ```zig
  comptime {
      assert(@sizeOf(Header) == 24);
      assert(@alignOf(Header) == 8);
  }
  ```
- **Type-level programming** for zero-cost abstractions
- **Avoid runtime computation when comptime possible**
- **Document comptime parameters clearly**
</comptime_rules>

## Error Handling

<error_best_practices>
- **Define specific error sets** - Not just `anyerror`
- **Document error conditions** in function comments
- **Use `errdefer` for partial cleanup**:
  ```zig
  const resource = try acquire();
  errdefer release(resource);
  const other = try acquireOther();
  errdefer releaseOther(other);
  ```
- **Never swallow errors silently**
- **Propagate errors with context** when possible
- **Use error unions** (`!T`) over sentinel values
</error_best_practices>

## Optionals Best Practices

<optional_rules>
- **Use optionals for "might not exist"** - `?T`
- **Use error unions for "might fail"** - `!T`
- **Unwrap safely**:
  ```zig
  // Good
  const value = optional orelse return error.NotFound;
  
  // Also good
  if (optional) |value| {
      // use value
  } else {
      return error.NotFound;
  }
  
  // AVOID
  const value = optional.?; // panics if null
  ```
- **Document whether null is meaningful or impossible**
</optional_rules>

## Standard Library Usage

<stdlib_best_practices>
- **Use `std.mem` for memory operations** - Safer than manual
- **Use `std.mem.eql` for equality** - Don't use `==` on slices
- **Use `std.fmt` for formatting** - Type-safe
- **Use `std.debug.assert` for debug assertions**
- **Use `std.testing` for tests** - Structured testing
- **Use `std.ArrayList` over manual slice management**
- **Use `std.StringHashMap` for string keys**
- **Prefer standard algorithms** over hand-rolled versions
</stdlib_best_practices>

## Performance & Optimization

<performance_rules>
- **Profile before optimizing** - Don't guess
- **Hot paths should be**:
  - Allocation-free (use arena or pre-allocated buffers)
  - Inline-able (keep small)
  - Branchless when possible
- **Use `@setCold` for error paths**
- **Use `inline` for small, frequently-called functions**
- **Use `noinline` to prevent code bloat**
- **Consider cache locality** - Group related data
- **Use SoA over AoS for performance-critical code** (if proven beneficial)
- **Avoid allocations in loops** - Pre-allocate or use arena
</performance_rules>

## Packed Structs & Bit Manipulation

<packed_structs>
- **Use `packed struct` only when necessary** (wire formats, hardware)
- **Document memory layout explicitly**
- **Be aware of target endianness** for wire formats
- **Use `std.mem.bytesAsSlice` for safe reinterpretation**
- **Validate packed struct sizes at comptime**:
  ```zig
  comptime assert(@sizeOf(PackedHeader) == 16);
  ```
</packed_structs>

## Testing

<testing_best_practices>
- **Test all error paths** - Not just happy path
- **Test boundary conditions** - Min, max, zero, one-off
- **Use `testing.expect` for assertions**
- **Use `testing.expectEqual` for exact matches**
- **Use `testing.expectError` for error cases**
- **Write integration tests** for critical flows
- **Fuzz test parsers** - At least 1M inputs
- **Test platform-specific code** on all targets
</testing_best_practices>

## Build System

<build_rules>
- **Use `build.zig` for configuration** - Not preprocessor
- **Support cross-compilation** - Don't assume native
- **Specify dependencies explicitly**
- **Use build options** for compile-time configuration:
  ```zig
  const options = b.addOptions();
  options.addOption(bool, "enable_logging", true);
  ```
- **Test all build modes** - Debug, ReleaseSafe, ReleaseFast
</build_rules>

## Security Considerations

<security_rules>
- **Validate all external input** - Never trust user data
- **Use constant-time comparison for secrets** - Prevent timing attacks:
  ```zig
  std.crypto.utils.timingSafeEql([32]u8, expected, actual)
  ```
- **Clear sensitive data** - Zero memory after use:
  ```zig
  std.crypto.utils.secureZero(u8, password_buffer);
  ```
- **Avoid format string vulnerabilities** - Use type-safe formatting
- **Check buffer sizes** - Prevent overflows
- **Limit resource usage** - Prevent DoS
- **Use cryptographic primitives correctly** - From `std.crypto`
</security_rules>

## Code Organization

<organization_rules>
- **One struct per file** for major types
- **Group related functions** with their types
- **Use `pub` intentionally** - Minimal public API
- **Document public API thoroughly**
- **Keep internal functions private**
- **Use namespacing** - Structs as namespaces for related functions
</organization_rules>

## Common Pitfalls to Avoid

<pitfalls>
- ❌ Using `catch unreachable` on fallible operations
- ❌ Ignoring alignment when casting pointers
- ❌ Assuming `usize` is 64-bit (it's platform-dependent)
- ❌ Using `@import` with dynamic paths
- ❌ Forgetting to free allocated memory
- ❌ Using `==` on slices (use `std.mem.eql`)
- ❌ Mutating slices passed as `const`
- ❌ Assuming function evaluation order (undefined in Zig)
- ❌ Using `@as` when `@intCast` or `@floatCast` should be used
- ❌ Copying large structs by value (use pointers)
</pitfalls>

## Elite-Level Patterns

<elite_patterns>
- **Use comptime for zero-cost abstractions**
- **Leverage type inference** - But not at cost of clarity
- **Generic programming with comptime parameters**
- **Error sets as documentation** - Explicit failure modes
- **Arena allocators for request-scoped memory**
- **Defer for RAII-like patterns**
- **Tagged unions for state machines**
- **Sentinel-terminated arrays** when appropriate
- **Inline assembly** only when profiling proves necessary
</elite_patterns>

---

**Remember:** Zig gives you the power to write unsafe code, but the goal is to use that power to build safe abstractions. Be explicit, validate everything, and let the compiler help you.