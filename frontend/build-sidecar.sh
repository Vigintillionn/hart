#!/bin/bash

set -e
echo "Building Haskell RISC-V Emulator..."

cd ../emulator
cabal build

BIN_PATH=$(cabal list-bin hart-emulator)
echo "Found compiled binary at: $BIN_PATH"

TARGET_TRIPLE=$(rustc -vV | grep host | awk '{print $2}')
echo "Detected Rust Target Triple: $TARGET_TRIPLE"

EXT=""
if [[ "$TARGET_TRIPLE" == *"windows"* ]]; then
  EXT=".exe"
fi

cd ../frontend
DEST_DIR="./src-tauri/binaries"
mkdir -p "$DEST_DIR"

DEST_FILE="$DEST_DIR/hart-emulator-$TARGET_TRIPLE$EXT"
cp "$BIN_PATH" "$DEST_FILE"

echo "Sidecar successfully deployed to: $DEST_FILE"
