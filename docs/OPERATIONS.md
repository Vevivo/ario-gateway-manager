# Gateway işletimi ve ileri özellikler

Bu sayfa, ilk kurulumu tamamlayan operatörler içindir. Yeni kurulum için önce ana [README](../README.md) dosyasındaki kolay kurulum yolunu izleyin.

## Güvenli otomatik disk koruması

Araç diski yüzde 90 olduğunda `rm -rf`, `docker system prune -a` veya SQLite silme işlemi yapmaz. `gateway-storage-setup`, güncel `ar-io-node` içindeki iki profili sunar:

- **Indexed eviction:** Üretim ve büyük cache için varsayılan profildir. Contiguous LRU index, chunk için yaş korumalı index ve drift uzlaştırıcısı kullanır.
- **TTL filesystem walk:** Küçük SSD cache için 14.400 saniyelik varsayılan yaş politikasını disk baskısına göre daraltır.

Varsayılan koruma:

- disk kullanımı `%90` olduğunda reclaim başlar;
- kullanım `%85` altına inene kadar devam eder;
- en az 20 GiB boş alan korunur;
- cache yalnız node'un kendi reclaimer mekanizmasıyla temizlenir;
- servis yalnız sağlıksız olduğunda mevcut autoheal davranışıyla yeniden başlatılır.

Mevcut gateway'de yeniden yapılandırmak için:

```bash
gateway-storage-setup
```

Eski cache için başlatılan index backfill tamamlandığında:

```bash
gateway-storage finalize-backfill
```

`data/sqlite` index ve moderation verisini, `data/redis` rate-limit/x402 durumunu taşır. Bu dizinlerin topluca silinmesi normal bakım değildir.

## Namecheap wildcard SSL

Yeni kolay kurulum Namecheap DNS API kullanır:

1. Namecheap kullanıcı adı ve API key, her domain için ayrı `/etc/letsencrypt/ar-io-DOMAIN-namecheap.ini` dosyasında `0600` izinle saklanır.
2. Apex ve wildcard sertifika DNS challenge ile alınır.
3. `certbot renew --dry-run` gerçek yenileme yolunu test eder.
4. `certbot.timer` sertifikayı düzenli kontrol eder.
5. Yenileme başarılı olduğunda deploy hook önce `nginx -t`, sonra `systemctl reload nginx` çalıştırır.

Kontrol komutları:

```bash
gateway-cert-check
gateway-cert-manual
gateway-renew-cert --dry-run
gateway-cert-setup
```

`gateway-cert-check` bitime 30 gün kala uyarı, son 5 günde kritik durum gösterir. `gateway-cert-manual`, Namecheap Advanced DNS ekranındaki TXT kaydı adımlarını göstererek DNS-01 doğrulaması yapar. Bu sırada gateway container'larını veya NGINX'i durdurmaz. Sertifika başarıyla alındıktan sonra `nginx -t` çalıştırır, NGINX'i `reload` eder ve yeni tarihi gösterir. Manuel DNS gözetimsiz yenilenemez; her yenilemede bu komut yeniden çalıştırılmalıdır.

## Observer teşhisi

| Komut | Gösterdiği bilgi |
|---|---|
| `gateway-observer-check` | Observer env değerleri, keypair yolları, izinler, current report ve son hatalar |
| `gateway-check` | Public gateway verisi, `/ar-io/info`, observer raporu ve servisler |
| `gateway-balance` | Observer veya argüman olarak verilen Solana wallet bakiyesi |
| `gateway-network-info` | AR.IO SDK üzerinden salt-okunur zincir üstü gateway kaydı |
| `gateway-network-readiness` | Domain, test verisi, wildcard TLS ve wallet hazırlığı |
| `gateway-logs` | Core, observer ve envoy logları |

Yaygın durumlar:

- **Key file missing:** `.env` içindeki keypair yolu sunucuda bulunamıyor.
- **Wallet mismatch/signature:** Keypair'in public adresi yapılandırılmış operator veya observer adresiyle eşleşmiyor.
- **Report pending:** Değerlendirme tamamlanmamış veya observer o epoch için seçilmemiş olabilir.
- **RPC timeout/rate limit:** Özel mainnet RPC kullanılması gerekebilir.
- **Insufficient funds:** İşlem imzalayan wallet'ın SOL bakiyesi yetersizdir.
- **Not prescribed:** Observer zincir üstü ön kontrol nedeniyle işlem göndermemiş olabilir.

Bu durumlarda cache veya veritabanı silmeden önce `gateway-doctor`, `gateway-observer-check` ve log çıktıları birlikte incelenmelidir.

## Opsiyonel özellikler

Tüm özellikler şu menüden yönetilir:

```bash
gateway-features
```

| Özellik | Komut | Davranış |
|---|---|---|
| x402 USDC egress | `gateway-enable-x402`, `gateway-x402-check` | Base/Base Sepolia, rate limiter, Redis persistence, fiyat ve allowlist |
| Grafana | `gateway-grafana` | Resmi dashboard; varsayılan olarak yalnız `127.0.0.1:1024` |
| ANS-104 filtreleri | `gateway-filters` | Kapalı, tümünü indexle veya doğrulanan özel JSON filtre |
| Apex içerik | `gateway-apex` | ArNS adı veya sabit transaction ID |
| Verification | `gateway-verification` | Trust, digest, cache headers ve opsiyonel HTTP signatures |
| CDB64 | `gateway-cdb64-check` | Root transaction index durumunu kontrol eder |
| Moderation | `gateway-block-name`, `gateway-unblock-name` | Local admin API üzerinden ArNS adı yönetir |
| Zincir üstü durum | `gateway-network-info` | AR.IO SDK ile salt-okunur kayıt ve epoch bilgisi |
| NGINX cache | `gateway-cache-advisor` | Disk ve x402 etkisini değerlendirir |

### x402 notu

x402 rate limiter olmadan çalışmaz. NGINX cache'den dönen cevaplar node rate limiter'a ulaşmadığı için gelişmiş NGINX cache, ödeme ve rate-limit politikası ölçülmeden açılmamalıdır.

## Güncelleme

```bash
gateway-update
```

Güncelleme:

- yerel tracked değişiklik varsa durur;
- `main` dalını fast-forward günceller;
- Compose yapılandırmasını doğrular;
- image'ları çeker ve servis sağlığını kontrol eder;
- persistent veri dizinlerini silmez.

Yeniden başlatma:

```bash
gateway-restart
```

Bu komut volume silmeden servisleri yeniden oluşturur.

## Release 83 doğrulaması

```bash
gateway-release-check
```

Komut çalışan `/ar-io/info` sürümünü GitHub'daki son resmi sürümle karşılaştırır ve şu Release 83 tabanını denetler:

- `ARNS_RESOLVER_PRIORITY_ORDER=on-demand,gateway`;
- `ARNS_COMPOSITE_LAST_RESOLVER_TIMEOUT_MS=5000`;
- `SKIP_LEAVING_GATEWAYS=true` veya Release 83'ün aynı davranıştaki varsayılanı;
- index tabanlı chunk cache eviction;
- kısa okuma reddi, leaving peer ve foreground request coalescing metrikleri.

Truncated-response doğrulaması, manifest/ArNS blocklist düzeltmesi, x402 CDP düzeltmeleri ve ADR-0029 rent refund desteği node/observer koduyla gelir; bunlar için ayrı bir kurucu seçeneği yoktur. `gateway-update` güncel resmi kodu ve sabitlenmiş container image'larını uygular.

Release 83, farklı büyük objelerin aynı anda cache'e yazılmasını sınırlayan `FOREGROUND_CACHE_MAX_SIZE` ve `FOREGROUND_CACHE_CONCURRENCY` değerlerini bilinçli olarak `0` yani sınırsız bırakır. Trafik profili ölçülmeden evrensel bir sayı seçilmemelidir. `gateway-cache-advisor` mevcut değerleri gösterir fakat canlı ayarı otomatik değiştirmez.

## Resmi yönetim konularının karşılığı

| Resmi konu | Repo karşılığı |
|---|---|
| Solana migration | Keyfile, RPC, observer, bakiye ve SDK kontrolleri |
| Upgrading | Güvenli fast-forward güncelleme ve health check |
| SSL certificates | Namecheap/Cloudflare otomasyonu, dry-run, timer ve NGINX hook |
| Environment variables | `.env` yedekleme ve anahtar bazlı güncelleme |
| Verification headers | Cache, verified, digest ve HTTP signatures kontrolü |
| Gateway filters | ANS-104 filtre profilleri ve JSON doğrulama |
| CDB64 | Index ve log kontrolü |
| Content moderation | Local admin API ile ArNS block/unblock |
| Apex content | ArNS veya transaction seçimi |
| x402 | Kurulum sonrası rehberli yapılandırma |
| Troubleshooting | `gateway-doctor`, `gateway-check`, `gateway-logs` |
| Grafana | Localhost-only izleme servisi |

## Kurulum dizini ve paylaşımlı sunucu

Yeni kurulumun varsayılan dizini `/opt/ar-io-gateway` konumudur. Docker Compose proje adı domain'e göre ayrılır ve node servis portları yalnız `127.0.0.1` üzerinde yayınlanır. NGINX yapılandırması domain'e özel bir site dosyasında tutulur; mevcut `default` sitesi değiştirilmez.

Mevcut gateway başka bir dizinde kuruluysa yalnız yönetim araçlarını eklerken:

```bash
curl -fsSL https://raw.githubusercontent.com/Vevivo/ario-gateway-manager/main/update-tools.sh | sudo env INSTALL_DIR=/srv/ar-io-node bash
```

Tam kurucu mevcut `.env` veya gateway verisi görürse ayarları ezmemek için durur. Mevcut kurulumlarda tam kurucuyu yeniden çalıştırmak yerine `gateway-update` veya `update-tools.sh` kullanılmalıdır.

## Güvenlik sınırları

1. `docker compose down -v` kullanılmaz.
2. Normal bakımda SQLite, Redis, cache veya wallet dizinleri topluca silinmez.
3. `.env` her ayar değişikliğinden önce zaman damgalı yedeklenir.
4. Wallet dosyaları `0600`, secret dizinleri `0700` izinle tutulur.
5. Grafana, Prometheus ve node-exporter public porta açılmaz.
6. Zincir üstü para, stake ve ağ kayıt işlemleri otomatik yapılmaz.
7. NGINX reload öncesinde yapılandırma doğrulanır.
8. Kurucu mevcut NGINX sitelerini, başka projelerin portlarını veya kapalı bir UFW yapılandırmasını zorla değiştirmez.
