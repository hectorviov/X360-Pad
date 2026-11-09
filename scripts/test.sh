#!/bin/sh
# Runs the unit tests: the driver's settings processing (C) and the app's settings model (Swift).
set -e
cd "$(dirname "$0")/.."
mkdir -p build
clang -Wall -Wextra -IDriver tools/test_settings.c -o build/test_settings
build/test_settings
swift test
