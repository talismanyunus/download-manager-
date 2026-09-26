#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
/usr/bin/python3 Tests/server.py &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
xcrun swiftc -swift-version 5 DownloadManager/DownloadEngine.swift Tests/EngineTests.swift -o build/tests/engine-tests
build/tests/engine-tests
