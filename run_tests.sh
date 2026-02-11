#!/bin/bash
# Run all arena context store tests
set -e

echo "Running arena context store tests..."
echo "======================================"

FAILED=0
TOTAL=0

for test in tests/test_*.nim; do
  TOTAL=$((TOTAL + 1))
  echo ""
  echo "--- $test ---"
  if nim c -r --hints:off --warnings:off "$test" 2>&1; then
    echo "PASS: $test"
  else
    echo "FAIL: $test"
    FAILED=$((FAILED + 1))
  fi
done

echo ""
echo "======================================"
echo "Results: $((TOTAL - FAILED))/$TOTAL test files passed"

if [ $FAILED -gt 0 ]; then
  echo "FAILURES: $FAILED"
  exit 1
else
  echo "All tests passed!"
fi
