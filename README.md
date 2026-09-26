# Download Manager — macOS

Türkçe SwiftUI arayüzü, özgün uygulama simgesi ve gerçek URLSession indirme motoru.

## Aç ve çalıştır

- Hazır uygulama: bu klasördeki **Download Manager.app** dosyasına çift tıkla.
- Xcode: **DownloadManager.xcodeproj** dosyasını aç, **DownloadManager → My Mac** seç ve **⌘R** kullan.
- macOS 13 ve üzeri. Release uygulaması Apple Silicon ve Intel mimarilerini içerir.
- Harici Swift paketi veya Apple geliştirici hesabı gerekmez. Yerel çalıştırma için ad-hoc imzalıdır; mağaza dağıtımı/noter onayı yapılmamıştır.

## Kullanım

1. **Yeni indirme** veya **⌘N** ile doğrudan HTTP/HTTPS dosya bağlantısını ekle.
2. Her satıra bir URL yazarak toplu indirme başlatabilirsin.
3. İndirme klasörünü seç; istersen başlangıç zamanı belirle.
4. Satırdaki duraklat/devam et düğmelerini kullan. Tamamlanan dosyayı klasör simgesiyle Finder’da göster.
5. Ayarlardan eşzamanlı dosya sayısını 1–8 arasında değiştir.

Arama, dosya türleri, durum filtreleri, hız/boyut/kalan süre, indirme geçmişi ve aynı adlı dosyaları koruyan otomatik numaralandırma bulunur. Listeden kaldırma diskteki tamamlanmış dosyayı silmez.

## Kapsam ve sınırlar

Bu proje bağımsız bir indirme yöneticisidir; IDM’nin tüm özelliklerinin birebir kopyası değildir. Birden fazla dosya eşzamanlı iner; tek dosya için çok parçalı hızlandırma, tarayıcı eklentisi, otomatik video yakalama, HLS/DASH birleştirme, FTP, hız sınırı ve site giriş oturumu aktarımı bu sürümde yoktur.

Devam etme URLSession ve sunucunun Range/ETag desteğine bağlıdır. Sunucu veya geçici veri uygun değilse indirme baştan başlayabilir; hata halinde yeniden dene. Uygulamadan normal çıkış aktif indirmeleri duraklatıp devam bilgisini kaydeder. Zorla kapatma/çökme sonrasında son kısım korunmayabilir. Zamanlama için uygulama açık, bilgisayar uyanık olmalıdır.

Geçmiş ve devam verisi `~/Library/Application Support/DownloadManager/transfers.json` içinde yerel olarak tutulur; bağlantılar bu dosyada bulunabilir. HTTP bağlantıları için ATS istisnası vardır, HTTPS sertifika doğrulaması varsayılandır. Dosyalar otomatik çalıştırılmaz.

## Derleme

```sh
xcodebuild -project DownloadManager.xcodeproj -scheme DownloadManager \
  -configuration Release -derivedDataPath build build
```

`project.yml` yalnızca projeyi yeniden üretmek istersen XcodeGen içindir; mevcut `.xcodeproj` doğrudan açılır.

## Test

```sh
bash Tests/run.sh
```

Testler yalnızca geçici klasör ve loopback HTTP sunucusuyla çalışır: URL doğrulama, duraklat/devam et, dosya içeriği doğrulama, eşzamanlı kuyruk, dosya çakışması, HTTP 404, zamanlama, listeden kaldırma ve geçmişin yeniden okunması. Python 3 ve Xcode komut satırı araçları gerektirir. Test portu: 18764.

## Logo

`Logo.png` orijinal yüksek çözünürlüklü simgedir; Xcode simge boyutları Assets.xcassets içindedir. Dahili imagegen aracıyla üretildi.

Üretim istemi: “Use case: logo-brand. Asset type: production macOS application icon for Download Manager. Create a beautiful polished macOS rounded-square icon, centered on transparent background. Deep midnight navy rounded-square tile, luminous aqua and mint downward arrow cleverly integrated into an open circular swoosh suggesting fast downloads. Bold simple memorable silhouette, subtle premium dimensional glass/metal highlights, sharp clean contours, legible at 32px. Single icon only, front view, generous consistent small outer padding, no words, no letters, no watermark. 1024 square.”
