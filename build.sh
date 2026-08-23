#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
cargo build --release --manifest-path "$root/backend/Cargo.toml"
mkdir -p "$root/bin"
cp "$root/backend/target/release/omarchy-mail-helper" "$root/bin/omarchy-mail-helper"
