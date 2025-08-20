# Logging Fix Summary

## Problem
The Zig ReleaseFast builds were not showing any output from `std.log` functions, making the demo and benchmark programs appear to do nothing when run in optimized mode. This was caused by Zig's default log level being set higher in release modes, filtering out `.info` level messages.

## Solution
Replaced `std.log.info()` calls with `std.debug.print()` function calls throughout the demo and benchmark applications. `std.debug.print()` works consistently across all build modes (Debug, ReleaseSafe, ReleaseFast, ReleaseSmall).

## Changes Made

### 1. Updated `/Users/ewan/Developer/OhMyApps/Poker/poker_ai/zig/src/demo.zig`
- Added helper function `print()` that wraps `std.debug.print()`
- Replaced all `std.log.info()` calls with `print()` calls
- Removed complex `std_options` configuration

### 2. Updated `/Users/ewan/Developer/OhMyApps/Poker/poker_ai/zig/bench/main.zig`
- Added helper function `print()` that wraps `std.debug.print()`
- Replaced all `std.log.info()` calls with `print()` calls for benchmark output
- Removed complex `std_options` configuration

### 3. Cleaned up `/Users/ewan/Developer/OhMyApps/Poker/poker_ai/zig/build.zig`
- Removed unnecessary log level configuration options
- Removed build_options dependencies
- Simplified build configuration

## Verification
- ✅ Demo works in ReleaseFast mode: `zig build -Doptimize=ReleaseFast && ./zig-out/bin/poker_ai_demo`
- ✅ Benchmark works in ReleaseFast mode: `zig build bench`
- ✅ Demo still works in Debug mode: `zig build -Doptimize=Debug && ./zig-out/bin/poker_ai_demo`
- ✅ Build succeeds in all optimization modes
- ✅ All output is visible in all build modes

## Technical Details
The issue was that Zig's `std.log` functions are controlled by a compile-time log level. In ReleaseFast mode, the default log level filters out `.info` messages. The `std.debug.print()` function bypasses this filtering and works consistently across all build modes.

## Commands to Test
```bash
# Test ReleaseFast mode
zig build -Doptimize=ReleaseFast
./zig-out/bin/poker_ai_demo
zig build bench

# Test Debug mode
zig build -Doptimize=Debug
./zig-out/bin/poker_ai_demo

# Test other modes
zig build -Doptimize=ReleaseSafe
zig build -Doptimize=ReleaseSmall
```

All modes now produce the expected output.