#!/bin/bash
#
# Z6 Fuzz Testing Script
#
# Runs all fuzz targets with configurable options.
# Usage: ./scripts/run-fuzz.sh [options]
#
# Options:
#   -t, --target TARGET   Run specific fuzz target (http1, http2, hpack, scenario, event)
#   -v, --verbose         Enable verbose output
#   -h, --help            Show this help message
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Parse arguments
TARGET=""
VERBOSE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--target)
            TARGET="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE="--verbose"
            shift
            ;;
        -h|--help)
            echo "Z6 Fuzz Testing Script"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -t, --target TARGET   Run specific fuzz target (http1, http2, hpack, scenario, event)"
            echo "  -v, --verbose         Enable verbose output"
            echo "  -h, --help            Show this help message"
            echo ""
            echo "Targets:"
            echo "  http1     - HTTP/1.1 Parser (1M iterations)"
            echo "  http2     - HTTP/2 Frame Parser (1M iterations)"
            echo "  hpack     - HPACK Decoder (1M iterations)"
            echo "  scenario  - Scenario Parser (100K iterations)"
            echo "  event     - Event Serialization (1M iterations)"
            echo "  all       - Run all fuzz targets (default)"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}  Z6 Fuzz Testing Suite${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""

# Function to run a specific fuzz target
run_fuzz_target() {
    local name=$1
    local file=$2

    echo -e "${YELLOW}Running $name fuzz tests...${NC}"
    echo ""

    if zig test "tests/fuzz/$file" --dep z6 -Mz6=src/z6.zig $VERBOSE 2>&1; then
        echo -e "${GREEN}✓ $name fuzz tests passed${NC}"
    else
        echo -e "${RED}✗ $name fuzz tests failed${NC}"
        return 1
    fi
    echo ""
}

# Run targets based on selection
if [ -z "$TARGET" ] || [ "$TARGET" = "all" ]; then
    echo "Running all fuzz targets..."
    echo ""

    run_fuzz_target "HTTP/1.1 Parser" "http1_parser_fuzz.zig"
    run_fuzz_target "HTTP/2 Frame Parser" "http2_frame_fuzz.zig"
    run_fuzz_target "HPACK Decoder" "hpack_decoder_fuzz.zig"
    run_fuzz_target "Scenario Parser" "scenario_parser_fuzz.zig"
    run_fuzz_target "Event Serialization" "event_serialization_fuzz.zig"

    echo -e "${GREEN}======================================${NC}"
    echo -e "${GREEN}  All fuzz tests completed!${NC}"
    echo -e "${GREEN}======================================${NC}"
else
    case $TARGET in
        http1)
            run_fuzz_target "HTTP/1.1 Parser" "http1_parser_fuzz.zig"
            ;;
        http2)
            run_fuzz_target "HTTP/2 Frame Parser" "http2_frame_fuzz.zig"
            ;;
        hpack)
            run_fuzz_target "HPACK Decoder" "hpack_decoder_fuzz.zig"
            ;;
        scenario)
            run_fuzz_target "Scenario Parser" "scenario_parser_fuzz.zig"
            ;;
        event)
            run_fuzz_target "Event Serialization" "event_serialization_fuzz.zig"
            ;;
        *)
            echo -e "${RED}Unknown target: $TARGET${NC}"
            echo "Valid targets: http1, http2, hpack, scenario, event, all"
            exit 1
            ;;
    esac
fi
