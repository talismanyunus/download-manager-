#!/usr/bin/env bash
# Download Manager — Native Messaging Host Kurulum Scripti
# Çalıştır: bash install.sh
# Chrome ve Firefox için manifest dosyalarını doğru konumlara kopyalar.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_NAME="com.localdownloadmanager.host"
HOST_BINARY="$SCRIPT_DIR/native_host.sh"

# native_host.sh çalıştırılabilir yap
chmod +x "$HOST_BINARY" 2>/dev/null || true

# ── Chrome / Chromium ──────────────────────────────────────────────────────────
CHROME_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
CHROMIUM_DIR="$HOME/Library/Application Support/Chromium/NativeMessagingHosts"
BRAVE_DIR="$HOME/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts"
EDGE_DIR="$HOME/Library/Application Support/Microsoft Edge/NativeMessagingHosts"

CHROME_MANIFEST='{
  "name": "com.localdownloadmanager.host",
  "description": "Download Manager Native Bridge",
  "path": "'"$HOST_BINARY"'",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://EXTENSION_ID_PLACEHOLDER/"
  ]
}'

# ── Firefox ───────────────────────────────────────────────────────────────────
FIREFOX_DIR="$HOME/Library/Application Support/Mozilla/NativeMessagingHosts"

FIREFOX_MANIFEST='{
  "name": "com.localdownloadmanager.host",
  "description": "Download Manager Native Bridge",
  "path": "'"$HOST_BINARY"'",
  "type": "stdio",
  "allowed_extensions": [
    "downloadmanager@local"
  ]
}'

install_manifest() {
  local dir="$1"
  local content="$2"
  local browser="$3"
  mkdir -p "$dir"
  echo "$content" > "$dir/${HOST_NAME}.json"
  echo "✓ $browser → $dir/${HOST_NAME}.json"
}

echo ""
echo "📦 Download Manager — Native Messaging Kurulumu"
echo "================================================"

install_manifest "$FIREFOX_DIR" "$FIREFOX_MANIFEST" "Firefox"

for pair in "$CHROME_DIR:Chrome" "$CHROMIUM_DIR:Chromium" "$BRAVE_DIR:Brave" "$EDGE_DIR:Edge"; do
  dir="${pair%%:*}"
  browser="${pair##*:}"
  install_manifest "$dir" "$CHROME_MANIFEST" "$browser"
done

echo ""
echo "✅ Kurulum tamamlandı."
echo ""
echo "Sonraki adım:"
echo "  1. Chrome/Firefox'a eklentiyi yükle (BrowserExtension/ klasörü)"
echo "  2. Eklenti ID'sini öğren ve Chrome manifest'indeki"
echo "     EXTENSION_ID_PLACEHOLDER değerini güncelle:"
echo "     $CHROME_DIR/${HOST_NAME}.json"
echo ""
echo "  Firefox için eklenti ID'si manifest.json'daki browser_specific_settings.gecko.id"
echo "  değeriyle otomatik eşleşir (downloadmanager@local)."
echo ""
