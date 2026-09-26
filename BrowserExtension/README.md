# Download Manager — Browser Extension

IDM tarzı Chrome/Firefox/Brave/Edge eklentisi.

## Özellikler
- Sayfadaki her video elementinin üzerine **"DM ile İndir"** butonu enjekte eder
- Video oynatılmaya başlayınca ekranın köşesinde **toast** çıkar → tek tıkla indir
- `.mp4 .zip .pdf .dmg` vb. linklere tıklayınca otomatik yakalar, tarayıcıya bırakmaz
- Sağ tık → **"Download Manager ile İndir"** context menu
- Popup'tan manuel URL ekle
- Uygulama kapalıysa bildirim gösterir

## Kurulum

### 1. Mac uygulamasını çalıştır
Xcode'dan `⌘R` ile başlat. HTTP API port 60315'te dinlemeye başlar.

### 2. Native Messaging host kurulumu (isteğe bağlı, fallback için)
```bash
cd NativeBridge
bash install.sh
```

### 3. Chrome / Brave / Edge
1. `chrome://extensions` → **Geliştirici modu** → **Paketlenmemiş uzantı yükle**
2. `BrowserExtension/` klasörünü seç
3. Eklenti ID'sini kopyala
4. `NativeBridge/` içindeki manifest dosyalarında `EXTENSION_ID_PLACEHOLDER` yerine yapıştır:
   ```
   ~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.localdownloadmanager.host.json
   ```

### 4. Firefox
1. `about:debugging` → **Bu Firefox** → **Geçici Eklenti Yükle**
2. `BrowserExtension/manifest.json` dosyasını seç
3. Firefox Native Messaging zaten `downloadmanager@local` ID ile eşleşir

## API Endpoint'leri (port 60315)

| Method | Path     | Body                                          |
|--------|----------|-----------------------------------------------|
| POST   | `/add`   | `{ "url": "...", "referer": "...", "filename": "..." }` |
| GET    | `/status`| —                                             |

## Dosya Yapısı
```
BrowserExtension/
├── manifest.json     — Eklenti tanımı (MV3)
├── background.js     — Service worker (API iletişimi, context menu)
├── content.js        — Sayfa enjeksiyonu (video butonu, link yakalama)
├── popup.html        — Popup arayüzü
├── popup.js          — Popup mantığı
└── icons/            — 16/48/128px ikonlar (kendin ekle)
```

## İkon oluşturma
`icons/` klasörü oluştur ve üç PNG dosyası koy:
- `icon16.png`  (16×16)
- `icon48.png`  (48×48)
- `icon128.png` (128×128)

Geçici test için boş PNG dosyaları da çalışır:
```bash
mkdir -p BrowserExtension/icons
for s in 16 48 128; do
  python3 -c "
import struct, zlib
def png(w,h):
    def chunk(t,d): c=zlib.crc32(t+d)&0xffffffff; return struct.pack('>I',len(d))+t+d+struct.pack('>I',c)
    hdr=struct.pack('>IIBBBBB',w,h,8,2,0,0,0)
    raw=b''.join(b'\x00'+bytes([0,180,160]*w) for _ in range(h))
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',hdr)+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b'')
open('BrowserExtension/icons/icon${s}.png','wb').write(png(${s},${s}))
"
done
```
