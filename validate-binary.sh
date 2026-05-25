#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2025-2026 ecoPrimals Collective
#
# benchScale/validate-binary.sh — Validate a primal binary for a target triple
#
# Checks: ELF format, architecture, static linkage, no dynamic deps,
#          QEMU runtime smoke test (for cross-arch targets).
#
# Usage:
#   ./validate-binary.sh <binary-path> [--target <triple>] [--qemu]
#   ./validate-binary.sh target/aarch64-unknown-linux-musl/release/nestgate --qemu
#
# Exit codes:
#   0 — all checks pass
#   1 — validation failure
#   2 — missing tools

set -euo pipefail

BINARY=""
TARGET=""
DO_QEMU=false
VERBOSE=false

usage() {
    echo "Usage: $0 <binary-path> [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --target TRIPLE   Expected target triple (auto-detected from path if omitted)"
    echo "  --qemu            Run QEMU smoke test for cross-arch binaries"
    echo "  --verbose         Show detailed inspection output"
    echo "  --help            Show this help"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)   TARGET="$2"; shift 2 ;;
        --qemu)     DO_QEMU=true; shift ;;
        --verbose)  VERBOSE=true; shift ;;
        --help|-h)  usage; exit 0 ;;
        -*)         echo "Unknown option: $1"; usage; exit 2 ;;
        *)          BINARY="$1"; shift ;;
    esac
done

if [[ -z "$BINARY" ]]; then
    echo "ERROR: No binary path provided"
    usage
    exit 2
fi

if [[ ! -f "$BINARY" ]]; then
    echo "ERROR: Binary not found: $BINARY"
    exit 1
fi

for tool in file readelf; do
    if ! command -v "$tool" &>/dev/null; then
        echo "ERROR: Required tool '$tool' not found"
        exit 2
    fi
done

if [[ -z "$TARGET" ]]; then
    if [[ "$BINARY" == *aarch64-unknown-linux-musl* ]]; then
        TARGET="aarch64-unknown-linux-musl"
    elif [[ "$BINARY" == *x86_64-unknown-linux-musl* ]]; then
        TARGET="x86_64-unknown-linux-musl"
    elif [[ "$BINARY" == *aarch64-linux-android* ]]; then
        TARGET="aarch64-linux-android"
    else
        TARGET="unknown"
    fi
fi

PRIMAL_NAME=$(basename "$BINARY")
passed=0
failed=0
total=0

check() {
    local name="$1" result="$2" expected="$3"
    ((total++)) || true
    if [[ "$result" == "$expected" ]]; then
        echo "  [PASS] $name"
        ((passed++)) || true
    else
        echo "  [FAIL] $name — expected '$expected', got '$result'"
        ((failed++)) || true
    fi
}

check_contains() {
    local name="$1" haystack="$2" needle="$3"
    ((total++)) || true
    if echo "$haystack" | grep -q "$needle"; then
        echo "  [PASS] $name"
        ((passed++)) || true
    else
        echo "  [FAIL] $name — '$needle' not found"
        ((failed++)) || true
    fi
}

echo "=== benchScale binary validation ==="
echo "Binary:  $BINARY"
echo "Target:  $TARGET"
echo "Size:    $(du -h "$BINARY" | cut -f1)"
echo ""

FILE_OUT=$(file "$BINARY")

echo "--- ELF Format ---"
check_contains "ELF 64-bit" "$FILE_OUT" "ELF 64-bit"
check_contains "statically linked" "$FILE_OUT" "statically linked"

case "$TARGET" in
    aarch64-*)
        check_contains "ARM aarch64" "$FILE_OUT" "ARM aarch64"
        ;;
    x86_64-*)
        check_contains "x86-64" "$FILE_OUT" "x86-64"
        ;;
esac

ELF_TYPE=$(readelf -h "$BINARY" 2>/dev/null | grep "Type:" | awk '{print $2}')
check "ELF type is EXEC (not DYN/PIE)" "$ELF_TYPE" "EXEC"

echo ""
echo "--- Dynamic Dependencies ---"
DYN_SECTION=$(readelf -d "$BINARY" 2>&1)
((total++)) || true
if echo "$DYN_SECTION" | grep -q "no dynamic section"; then
    echo "  [PASS] No dynamic section (fully static)"
    ((passed++)) || true
else
    echo "  [FAIL] Dynamic section found — binary has dynamic deps"
    ((failed++)) || true
    if $VERBOSE; then
        echo "$DYN_SECTION" | head -10
    fi
fi

echo ""
echo "--- Binary Properties ---"
BIN_SIZE=$(stat --printf="%s" "$BINARY" 2>/dev/null || stat -f "%z" "$BINARY" 2>/dev/null)
((total++)) || true
if [[ "$BIN_SIZE" -gt 1000000 ]] && [[ "$BIN_SIZE" -lt 100000000 ]]; then
    echo "  [PASS] Size reasonable ($(numfmt --to=iec "$BIN_SIZE" 2>/dev/null || echo "${BIN_SIZE} bytes"))"
    ((passed++)) || true
else
    echo "  [WARN] Size unusual: $BIN_SIZE bytes"
    ((passed++)) || true
fi

if $DO_QEMU; then
    echo ""
    echo "--- QEMU Runtime Smoke Test ---"

    QEMU_BIN=""
    case "$TARGET" in
        aarch64-unknown-linux-musl)
            QEMU_BIN="qemu-aarch64-static"
            ;;
        x86_64-unknown-linux-musl)
            QEMU_BIN=""
            ;;
    esac

    if [[ -n "$QEMU_BIN" ]]; then
        if ! command -v "$QEMU_BIN" &>/dev/null; then
            echo "  [SKIP] $QEMU_BIN not installed (apt install qemu-user-static)"
        else
            ((total++)) || true
            if HELP_OUT=$($QEMU_BIN "$BINARY" --help 2>&1); then
                echo "  [PASS] --help executes without segfault"
                ((passed++)) || true
            else
                EXIT_CODE=$?
                if [[ $EXIT_CODE -eq 139 ]] || [[ $EXIT_CODE -eq 134 ]]; then
                    echo "  [FAIL] --help segfaulted (exit $EXIT_CODE)"
                    ((failed++)) || true
                else
                    echo "  [PASS] --help exited with $EXIT_CODE (non-zero but no segfault)"
                    ((passed++)) || true
                fi
            fi
        fi
    else
        ((total++)) || true
        if "$BINARY" --help &>/dev/null; then
            echo "  [PASS] --help executes natively"
            ((passed++)) || true
        else
            EXIT_CODE=$?
            if [[ $EXIT_CODE -eq 139 ]] || [[ $EXIT_CODE -eq 134 ]]; then
                echo "  [FAIL] --help segfaulted (exit $EXIT_CODE)"
                ((failed++)) || true
            else
                echo "  [PASS] --help exited with $EXIT_CODE (non-zero but no segfault)"
                ((passed++)) || true
            fi
        fi
    fi
fi

echo ""
echo "=== Results: $passed/$total passed, $failed failed ==="

if [[ $failed -gt 0 ]]; then
    exit 1
fi
