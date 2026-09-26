#!/usr/bin/env bash
# Download Manager — Native Messaging Host
# Tarayıcı bu scripti stdin/stdout üzerinden çağırır.
# Mesaj formatı: 4 byte little-endian uzunluk + JSON body

# Gelen mesajı oku ve HTTP API'ye ilet
read_message() {
  # İlk 4 byte = mesaj uzunluğu (little-endian uint32)
  local len_bytes
  len_bytes=$(dd bs=1 count=4 2>/dev/null | od -A n -t u1 | tr -d ' \n')
  if [[ -z "$len_bytes" ]]; then exit 0; fi

  local b0 b1 b2 b3
  read -r b0 b1 b2 b3 <<< "$len_bytes"
  local length=$(( b0 + b1*256 + b2*65536 + b3*16777216 ))

  # JSON body oku
  dd bs=1 count="$length" 2>/dev/null
}

send_message() {
  local body="$1"
  local len="${#body}"
  # 4 byte little-endian length
  printf "\\x$(printf '%02x' $((len & 0xFF)))"
  printf "\\x$(printf '%02x' $(((len >> 8) & 0xFF)))"
  printf "\\x$(printf '%02x' $(((len >> 16) & 0xFF)))"
  printf "\\x$(printf '%02x' $(((len >> 24) & 0xFF)))"
  printf '%s' "$body"
}

PORT=60315

while true; do
  MESSAGE=$(read_message)
  [[ -z "$MESSAGE" ]] && break

  # HTTP API'ye POST /add
  RESPONSE=$(curl -s -m 3 \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$MESSAGE" \
    "http://127.0.0.1:$PORT/add" 2>/dev/null || echo '{"ok":false,"error":"app not running"}')

  send_message "$RESPONSE"
done
