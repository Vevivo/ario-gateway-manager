# AR.IO Gateway Manager

AR.IO gateway kurulumunu ve günlük işletimini terminalde sorularla yöneten, resmi `ar-io-node` yapısını bozmadan çalışan kurulum ve operatör araçları.

Bu proje gateway'i AR.IO ağına kaydetmez, stake taşımaz ve zincir üstünde kullanıcı adına işlem imzalamaz. Sunucuyu hazırlar; gateway, observer, NGINX, wildcard TLS, disk koruması ve seçilen opsiyonel özellikleri yönetir.

## Tek komutla kurulum

Önce [resmi sistem gereksinimlerini](https://docs.ar.io/build/run-a-gateway/quick-start/#system-requirements) karşılayan temiz bir Ubuntu/Debian sunucuda domainin apex ve wildcard DNS kayıtlarını sunucuya yönlendirin.

```bash
curl -fsSL https://raw.githubusercontent.com/Vevivo/ario-gateway-manager/main/install-gateway.sh | sudo bash
```

Kurulum size domain, Solana operator/observer cüzdanı, RPC, disk koruması, SSL ve isteğe bağlı x402 hakkında sorular sorar. Varsayılan yol yeni başlayanlar için uygundur; ileri ayarlar sorular içinden seçilebilir.

Resmi minimum: 4 CPU, 4 GB RAM, 500 GB depolama ve 50 Mbps bağlantı. Önerilen: 12 CPU, 32 GB RAM, 2 TB SSD ve 1 Gbps. Üretimde public Solana RPC yerine özel/premium RPC kullanılması önerilir. Observer cüzdanının benzersiz olması ve protokol işlemleri için SOL bulundurması gerekir.

> Güvenlik: Scripti doğrudan çalıştırmadan önce indirip incelemek isterseniz `curl -fsSLO <URL>` ile kaydedip `sudo bash install-gateway.sh` kullanın. Seed phrase/private key yalnız size ait güvenli terminalde girilmelidir.

## Tek merkezden yönetim

Kurulumdan sonra:

```bash
gateway
```

Tüm kısa yollar:

```bash
gateway-help
```

En sık kullanılan komutlar:

| Komut | İşlev |
|---|---|
| `gateway-doctor` | Docker, NGINX, yerel/public sağlık, TLS, disk, inode, key dosyaları, autoheal, x402 ve CDB64 kontrolü |
| `gateway-check` | Gerçek veri (`1984`), gateway info, observer raporu ve servis testi |
| `gateway-status` | Servis, CPU/RAM, disk ve inode görünümü |
| `gateway-logs` | Core, observer ve envoy loglarını canlı izleme |
| `gateway-update` | Stable `main` dalını fast-forward güncelleme; persistent veriye dokunmaz |
| `gateway-restart` | Volume silmeden servisleri yeniden oluşturma ve health check |
| `gateway-storage` | Disk, cache boyutları, eviction ve backfill durumu |
| `gateway-cert-check` | Sertifika bitişi, authenticator ve timer durumu |
| `gateway-observer-check` | Observer anahtarları, rapor, epoch ve hata teşhisi |
| `gateway-balance` | Operator/observer Solana bakiyesi |
| `gateway-network-info` | Node içindeki `@ar.io/sdk` ile zincir üstü gateway kaydı ve performans durumu |
| `gateway-features` | Opsiyonel özellik menüsü |
| `gateway-guides` | Resmi yönetim sayfalarını ilgili yerel komutlarla eşleştirir |

## Güvenli otomatik disk koruması

Bu repo diski yüzde 90 olduğunda `rm -rf`, `docker system prune -a` veya SQLite silme işlemi yapmaz. `gateway-storage-setup` güncel `ar-io-node` içindeki iki resmi profili sorar:

- **Indexed eviction (varsayılan):** üretim, büyük cache veya spinning disk için; contiguous LRU index, chunk için yaş korumalı index ve resmi drift uzlaştırıcısı.
- **TTL filesystem walk:** küçük SSD cache için; varsayılan 14.400 saniyelik yaş politikasını disk basıncına göre dinamik daraltır. Dosya sayısı büyüdükçe metadata I/O maliyeti artar.

Her iki profilde:

- yüksek eşik varsayılan `%90`;
- temizleme hedefi varsayılan `%85`;
- ayrıca varsayılan `20 GiB` boş alan rezervi;
- cache yalnız AR.IO node’un kendi reclaimer’larıyla temizlenir;
- indexed profil seçilir ve eski cache varsa resumable tek seferlik backfill çalışır;
- servis ancak sağlıksız olursa mevcut `autoheal` davranışıyla yeniden başlatılır.

Kurulu bir gateway'e eklemek için:

```bash
gateway-storage-setup
```

Eski cache bulunduysa loglarda hem `Cache index backfill complete` hem `Chunk cache index backfill complete` görüldükten sonra:

```bash
gateway-storage finalize-backfill
```

Discord’da paylaşılan `ENABLE_CHUNK_DATA_CACHE_CLEANUP=true` ve `CHUNK_DATA_CACHE_CLEANUP_THRESHOLD=14400` yaklaşımı TTL profilinin temelidir. Güncel upstream, cache büyüdüğünde indeksli profili önerir; chunk tarafındaki TTL walker’ı da index dışı kalmış dosyaları uzlaştırmak için korur. Chunk ingest açıksa araç, yaş tabanını confirmation penceresinin altına indirmez.

`data/sqlite` indexleme ilerlemesini ve moderation verisini, `data/redis` rate-limit/x402 durumunu, contiguous/chunk dizinleri ise cache'i taşır. Bunların körlemesine silinmesi normal bakım değildir. Docker'ın kullanılmayan image/cache katmanlarını kontrolsüz silmek veya `docker volume prune` çalıştırmak da gateway data-retention politikası değildir.

## Kesintisiz wildcard TLS yenileme

Yeni kurulumda önerilen seçenek Cloudflare DNS API'dir. Token yalnız ilgili zone için `Zone:Read` ve `DNS:Edit` izinleriyle oluşturulmalıdır. `gateway-cert-setup` ayrıca resmi dokümana uygun Namecheap DNS API seçeneği sunar; Namecheap'in API hesap şartları vardır.

Otomatik akış:

1. API bilgileri `/etc/letsencrypt/*.ini` altında `0600` izinle saklanır.
2. Apex ve wildcard sertifika DNS challenge ile alınır.
3. `certbot renew --dry-run` gerçek yenileme yolu üzerinde çalıştırılır.
4. `certbot.timer` düzenli kontrol eder; Certbot 30 gün veya daha az süre kaldığında yeniler.
5. Başarılı yenilemede deploy hook önce `nginx -t`, sonra kesintisiz `systemctl reload nginx` çalıştırır.

```bash
gateway-cert-check
gateway-renew-cert --dry-run
gateway-cert-setup
```

Manuel DNS seçeneği her sağlayıcıyla çalışır fakat TXT kaydı insan müdahalesi gerektirdiğinden otomatik yenilenemez. `gateway-cert-check` bitime 30 gün kala uyarır, son 5 günde kritik hata döndürür.

## Opsiyonel özellikler

`gateway-features` aşağıdaki yetenekleri kurulumdan sonra açıp kontrol eder:

| Özellik | Komut | Davranış |
|---|---|---|
| x402 USDC egress | `gateway-enable-x402`, `gateway-x402-check` | Base/Base Sepolia, zorunlu rate limiter, Redis persistence, fiyat, allowlist, paywall ve opsiyonel CDP onramp |
| Grafana | `gateway-grafana` | Resmi dashboard/Prometheus dosyalarını kullanır; rastgele admin parolasıyla yalnız `127.0.0.1:1024` üzerinde açılır |
| ANS-104 filtreleri | `gateway-filters` | Kapalı, tümünü indexle veya doğrulanan özel JSON filtre |
| Apex içerik | `gateway-apex` | Önerilen ArNS adı ya da sabit 43 karakterli transaction ID; aynı anda ikisini yazmaz |
| Verification | `gateway-verification` | Trust/digest/cache başlıklarını inceler; opsiyonel RFC 9421 HTTP signatures açar |
| CDB64 | `gateway-cdb64-check` | Release 67+ ile varsayılan gelen O(1) root transaction index durumunu kontrol eder |
| Moderation | `gateway-block-name`, `gateway-unblock-name` | `ADMIN_API_KEY` ile yalnız local admin API üzerinden ArNS adı yönetir |
| Zincir üstü durum | `gateway-network-info` | AR.IO SDK ile salt-okunur kayıt, stake ve epoch istatistikleri |
| NGINX cache | `gateway-cache-advisor` | Disk ve x402 etkisini değerlendirir; canlı NGINX dosyasını körlemesine değiştirmez |

### x402 ve NGINX cache notu

x402, rate limiter olmadan çalışmaz. NGINX tarafından cache'den dönen başarılı cevaplar node rate limiter'a ulaşmadığı için ödeme/rate-limit politikasını değiştirir. Gelişmiş NGINX cache yalnız yüksek trafikte, `429` ve `Cache-Control: no-store` bypass kuralları, cache kapasitesi ve moderation purge süreci tasarlandıktan sonra eklenmelidir.

## Resmi yönetim menüsü kapsamı

| Resmi konu | Repo karşılığı |
|---|---|
| Solana migration | Solana keyfile doğrulama, canonical program IDs, RPC doğrulama, observer teşhisi, bakiye ve SDK registry sorgusu |
| Upgrading | Dirty tracked dosya koruması, `main` fast-forward, Compose doğrulama, image pull ve health check |
| SSL certs | Cloudflare/Namecheap otomasyon, dry-run, timer ve NGINX deploy hook |
| Environment variables | Güvenli `.env` yedekleme ve anahtar bazlı güncelleme; `.env` shell olarak source edilmez |
| Verification headers | İki HEAD isteğiyle cache/verified/digest görünümü ve HTTP signatures |
| Advanced NGINX caching | Uygunluk danışmanı; yüksek trafik ve x402 çakışması açıkça gösterilir |
| Gateway filters | ANS-104 filtre profilleri ve JSON doğrulama |
| CDB64 | Varsayılan index/lookup ve log kontrolü |
| Content moderation | ArNS block/unblock local admin API |
| SQLite snapshots | Bilerek otomatikleştirilmez; gateway'i durdurup index DB'lerini değiştiren bakım penceresi işlemidir |
| Apex domain content | ArNS veya transaction seçimi, karşılıklı dışlama ve kontrollü recreate |
| x402 | Kurulum sırasında veya sonradan tam rehberli yapılandırma |
| Troubleshooting | `gateway-doctor`, `gateway-check`, `gateway-logs` |
| Grafana | Localhost-only güvenli sidecar |

Resmi ana kaynaklar:

- [Gateway Installation & Setup](https://docs.ar.io/build/run-a-gateway/quick-start/)
- [Manage your Gateway](https://docs.ar.io/build/run-a-gateway/manage/)
- [Automating SSL](https://docs.ar.io/build/run-a-gateway/manage/ssl-certs/)
- [AR.IO SDK](https://docs.ar.io/sdks/ar-io-sdk/)
- [Official ar-io-node repository](https://github.com/ar-io/ar-io-node)

## Var olan kuruluma yalnız araçları ekleme

Gateway'i yeniden kurmadan operatör komutlarını güncellemek için:

```bash
curl -fsSL https://raw.githubusercontent.com/Vevivo/ario-gateway-manager/main/update-tools.sh | sudo bash
```

Kurulum dizini standart değilse:

```bash
curl -fsSL https://raw.githubusercontent.com/Vevivo/ario-gateway-manager/main/update-tools.sh | sudo env INSTALL_DIR=/srv/ar-io-node bash
```

Sonra `gateway-storage-setup`, `gateway-cert-setup` ve `gateway-doctor` çalıştırın.

## Güvenlik modeli

- `docker compose down -v`, SQLite silme ve geniş kapsamlı `rm -rf` bakım komutlarında yoktur.
- Güncelleme yerel tracked değişiklik varsa durur; veri dizinlerini silmez.
- `.env` her değişiklik öncesinde zaman damgalı olarak yedeklenir ve `0600` tutulur.
- Cüzdan dosyaları `0600`, secret dizinleri `0700` olur.
- Grafana, Prometheus ve node-exporter public porta açılmaz.
- Zincir üstü para/stake işlemleri otomatik yapılmaz.
- NGINX reload öncesinde yapılandırma doğrulanır.

## Geliştirme ve test

```bash
bash -n install-gateway.sh gateway-manager.sh update-tools.sh
bash tests/smoke.sh
```

Bu repo resmi AR.IO yazılımının yerine geçmez; `ar-io-node` kurulumunu ve operasyonunu kolaylaştıran bir topluluk aracıdır.

İleri seviye Wayfinder Router, ClickHouse/Parquet, Bundler ve Verifiable AI değerlendirmeleri [geliştirme yol haritasında](docs/ROADMAP.md) bulunur.
