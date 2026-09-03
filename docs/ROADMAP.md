# AR.IO Installer Geliştirme Yol Haritası

Bu dosya resmi AR.IO dokümantasyonu ve `ar-io` GitHub organizasyonundaki güncel projeler incelenerek hazırlanmıştır. Amaç, yeni özellik eklerken çalışan gateway kurulumunu ve persistent veriyi riske atmamak.

## Şu anda güvenle bütünleştirilenler

- Üretim gateway kurulumu, NGINX ve wildcard TLS
- Solana operator, observer ve upload keyfile yolları
- Özel/premium Solana RPC desteği ve URL doğrulama
- Native indexed production profili ve küçük SSD için TTL filesystem-walk profili
- Chunk index drift reconciliation ve ingest confirmation yaş tabanı koruması
- Cache index backfill ve tamamlama takibi
- Certbot Cloudflare/Namecheap DNS otomasyonu, dry-run, timer ve NGINX hook
- Observer, wallet bakiyesi, public veri ve on-chain AR.IO SDK kontrolleri
- x402 + zorunlu rate limiter + Redis persistence + allowlist + CDP onramp
- RFC 9421 HTTP signatures ve trust/verification header kontrolü
- CDB64, ANS-104 filtreleri, apex content ve ArNS moderation
- Localhost-only Grafana
- Kapasite ve x402 etkisini gösteren NGINX cache danışmanı

## Kullanıcı profilleri

| Profil | Varsayılan öneri | Opsiyonel ekler |
|---|---|---|
| Yeni başlayan | Gateway, observer, native disk koruması, otomatik TLS, autoheal | Grafana, apex ArNS |
| Network operator | Özel RPC, benzersiz observer, 0.5 SOL rezerv, SDK registry/epoch kontrolü | Epoch cranking, HTTP signatures |
| Ücretli erişim | Önce testnet x402, Redis persistence, ölçülmüş limitler | Mainnet x402, CDP onramp, allowlist |
| Yoğun trafik | SSD/IOPS ölçümü, CDB64, dar ANS-104 filtreleri | Ölçülmüş NGINX cache, ClickHouse |
| Veri yükleme hizmeti | Güncel GraphQL index ve ayrı finansal cüzdan | Bundler sidecar |
| Uygulama geliştirici | Gateway API ve AR.IO SDK | Wayfinder Router, ar-io-deploy |

## Sonraki güvenli modüller

### 1. Wayfinder Router kurulumu

Wayfinder Router bir gateway özelliği değil, birden çok gateway üzerinden veriyi bulan ve doğrulayan ayrı bir proxy'dir. Aynı makinede varsayılan gateway portu `3000` ile çakışabileceğinden ayrı port/domain planı gerekir.

Planlanan kurulum korumaları:

- resmi release binary ve `checksums.txt` SHA-256 doğrulaması;
- varsayılan `proxy` + `temperature` routing;
- verification açık, top-staked kaynak, 3 gateway / 2 consensus;
- admin UI yalnız localhost;
- disk cache boyutu ve telemetry retention için ayrı limit;
- `SIGTERM` graceful shutdown ve health/readiness testi;
- mevcut gateway NGINX dosyasından bağımsız site dosyası.

Kaynak: https://docs.ar.io/build/run-wayfinder-router/

### 2. ClickHouse ve Parquet profili

ClickHouse büyük GraphQL/analitik iş yükünde yararlıdır; normal gateway için şart değildir. SQLite'ın yerine geçmez. Güncel resmi sayfadaki örnek Parquet dosyası Nisan 2025 tarihli olduğundan “en güncel snapshot” diye otomatik indirilmemelidir.

Planlanan kurulum korumaları:

- CPU, RAM, boş disk ve IOPS preflight;
- rastgele ClickHouse parolası ve `0600` secret dosyası;
- yalnız `docker compose --profile clickhouse` kullanımı;
- kullanıcının mevcut GraphQL upstream seçimini açıkça onaylama;
- snapshot URL/tarih/checksum metadata'sını çalıştırma anında doğrulama;
- `chmod 777` kullanmama;
- import öncesi yedek ve geri dönüş planı.

Kaynak: https://docs.ar.io/build/extensions/clickhouse/

### 3. Bundler sidecar

Bundler upload kabul eder, AR harcar ve yakın zamanlı GraphQL indexine bağımlıdır. Bu nedenle sıradan gateway menüsünde tek onayla açılmamalıdır.

Planlanan kurulum korumaları:

- gateway index yüksekliğinin güncel olduğunu doğrulama;
- ayrı, fonu sınırlı Arweave wallet ve `0600` secret;
- varsayılan-deny allowlist;
- “allow all” için ikinci açık onay;
- owner-address'e daraltılmış ANS-104 unbundle filtresi;
- ödeme/bakiye ve optimistic indexing testleri;
- gateway'den bağımsız start/stop/log komutları.

Kaynak: https://docs.ar.io/build/extensions/bundler/

### 4. Operasyon uyarıları ve makine-okunur rapor

- `gateway-report --json` ile health, release, disk, TLS, observer, epoch ve x402 özeti;
- Prometheus alert rules: disk/inode, sertifika, unhealthy container, observer report deadline, SOL bakiyesi;
- opsiyonel webhook/Telegram/e-posta alıcısı;
- secret değerlerini hiçbir rapora koymama;
- alarm gönderimi başarısız olsa bile gateway'i etkilememe.

### 5. Yedek/geri yükleme manifesti

Cache yedeklenmez. Değerli durum; `.env`, NGINX, Certbot renewal config, wallet referansları ve gerekli SQLite/observer metadata için şifreli, checksummed manifest olarak ele alınır. Private keyleri varsayılan olarak arşive koymamak gerekir.

## Ayrı tutulacak ürünler

- **Verifiable AI** şu anda alpha olarak belgeleniyor ve MLflow/signing/attestation mimarisi gerektiriyor. Varsayılan gateway kurulumu olmamalı.
- **ar-io-deploy** içerik upload/ArNS güncelleme aracıdır; server operator wallet'ıyla otomatik çalıştırmak yerine geliştirici CI veya ayrı sınırlı cüzdanla kullanılmalı.
- **Zincir üstü write işlemleri** (`joinNetwork`, stake artırma/azaltma, leave, settings update) gerçek fon ve imza kullanır. Bu repo önce read-only SDK durumu sunar; write wizard ancak transaction preview, maliyet, ayrı onay ve donanım/harici signer tasarımıyla eklenmelidir.

## Değişmez güvenlik kuralları

1. `docker compose down -v` kullanılmaz.
2. Normal bakımda `data/sqlite`, `data/redis`, cache veya wallet dizinleri topluca silinmez.
3. Güncelleme ve feature değişikliği öncesinde doğrulama/yedek yapılır.
4. Bir servis eklemek mevcut gateway'in portunu, domainini veya ödeme politikasını sessizce değiştirmez.
5. Dokümanda tarihli snapshot varsa güncelliği ve checksum'ı doğrulanmadan indirilmez.
6. Secretlar komut çıktısına, Git'e veya public porta taşınmaz.
7. Zincir üstü fon hareketleri hiçbir zaman varsayılan veya gözetimsiz çalıştırılmaz.
