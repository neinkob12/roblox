#!/usr/bin/env bash
# Strict type check of src/ against the Roblox API definitions using luau-lsp.
# Usage: tools/typecheck.sh   (needs rojo on PATH; downloads luau-lsp into .typecheck/)
set -euo pipefail

LUAU_LSP_VERSION="${LUAU_LSP_VERSION:-1.53.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$ROOT/.typecheck"
mkdir -p "$CACHE"
cd "$ROOT"

BIN="$CACHE/luau-lsp-$LUAU_LSP_VERSION"
if [ ! -x "$BIN" ]; then
	echo "Downloading luau-lsp $LUAU_LSP_VERSION"
	curl -fsSL -o "$CACHE/luau-lsp.zip" \
		"https://github.com/JohnnyMorganz/luau-lsp/releases/download/$LUAU_LSP_VERSION/luau-lsp-linux-x86_64.zip"
	unzip -o -q "$CACHE/luau-lsp.zip" -d "$CACHE/unzip"
	mv "$CACHE/unzip/luau-lsp" "$BIN"
	chmod +x "$BIN"
	rm -rf "$CACHE/unzip" "$CACHE/luau-lsp.zip"
fi

# Definitions pinned to the same luau-lsp release tag.
DEFS="$CACHE/globalTypes-$LUAU_LSP_VERSION.d.luau"
if [ ! -f "$DEFS" ]; then
	curl -fsSL -o "$DEFS" \
		"https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/$LUAU_LSP_VERSION/scripts/globalTypes.d.luau"
fi

rojo sourcemap default.project.json -o "$CACHE/sourcemap.json"

# luau-lsp exits non-zero when it reports errors, which fails CI.
"$BIN" analyze \
	--sourcemap="$CACHE/sourcemap.json" \
	--definitions="$DEFS" \
	--ignore="Packages/**" \
	--ignore="**/Packages/**" \
	src
