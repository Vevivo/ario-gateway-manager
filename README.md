# AR.IO Gateway Manager

## Tek komutla başla

Ubuntu veya Debian sunucunuza bağlanın ve bu komutu yapıştırın:

```bash
curl -fsSL https://raw.githubusercontent.com/Vevivo/ario-gateway-manager/main/install-gateway.sh | sudo bash
```

Kurulum ekranı açılınca ilk soruda **Kolay kurulum** için yalnızca `Enter` tuşuna basın. Kurucu ne istendiğini ve örnek cevabı her sorudan önce gösterir.

> Bu araç sunucuyu kurar; gateway'i AR.IO Network'e kaydetmez, stake taşımaz ve sizin adınıza zincir üstü kayıt işlemi yapmaz.

## Aynı sunucuda başka projeler varsa

Ek bir klasör oluşturmanız gerekmez. Yeni gateway varsayılan olarak tek bir dizine kurulur:

```text
/opt/ar-io-gateway
```

Bu dizinin içinde resmi `ar-io-node` kodu, `.env`, wallet dosyaları, cache, veritabanları, loglar ve gateway'e ait Compose ek ayarı bulunur. Docker projesine domain'e özel bir ad verilir; böylece container, network ve volume adları diğer Compose projeleriyle karışmaz.

Kurucu ayrıca:

- `3000`, `4000` ve `5050` portlarını yalnızca `127.0.0.1` üzerinde yayınlar; internete doğrudan açmaz;
- `/etc/nginx/sites-available/default` dosyasını değiştirmez;
- `/etc/nginx/sites-available/ar-io-DOMAIN.conf` biçiminde ayrı bir NGINX site dosyası oluşturur;
- NGINX çalışıyorsa `restart` yerine yapılandırmayı doğrulayıp `reload` yapar;
- UFW kapalıysa kendiliğinden etkinleştirmez; açıksa yalnız gerekli `22`, `80` ve `443` kurallarını ekler;
- sistem genelinde `apt upgrade` çalıştırmaz;
- var olan Docker motorunu yükseltmez veya değiştirmez; Compose eklentisi eksik ya da eskiyse güvenli biçimde durur;
- `80`, `443`, `3000`, `4000` veya `5050` üzerinde güvenli biçimde paylaşamayacağı bir çakışma görürse diğer projeyi durdurmak yerine kurulumu keser.

Başka NGINX siteleri aynı sunucuda çalışabilir. Fakat Apache, Caddy veya Docker içindeki başka bir reverse proxy `80/443` portlarını kullanıyorsa kurucu o servisin ayarını değiştirmez; önce mevcut reverse proxy ile nasıl birleştirileceğine karar verilmelidir.

## Başlamadan önce hazırlayın

| Gerekli bilgi | Ne hazırlamalısınız? |
|---|---|
| Sunucu | Ubuntu/Debian ve root veya sudo erişimi |
| Domain | Namecheap DNS'te sunucu IP'sine yönlendirilmiş ana domain ve wildcard kayıt |
| Operator wallet | AR.IO gateway kaydınızdaki Solana public adresi ve ona ait keypair |
| Observer wallet | Ayrı kullanıyorsanız observer public adresi ve keypair; aynıysa tekrar gerekmez |
| Solana RPC | Tercihen özel mainnet RPC URL'si |
| Namecheap | Kullanıcı adı, API key ve whitelist'e eklenmiş sunucu IPv4 adresi |

Resmi minimum sistem gereksinimi 4 CPU, 4 GB RAM, 500 GB depolama ve 50 Mbps bağlantıdır. Üretim için önerilen yapı 12 CPU, 32 GB RAM, 2 TB SSD ve 1 Gbps bağlantıdır.

### Namecheap DNS kayıtları

Bu bölümün amacı satın aldığınız domaini gateway sunucusuna bağlamaktır.

Örnek olarak:

- satın aldığınız domain: `example.com`
- gateway sunucunuzun public IPv4 adresi: `SUNUCU_IP_ADRESINIZ`

Namecheap hesabınızda şu yolu açın:

`Domain List > Manage > Advanced DNS > Host Records`

`Add New Record` düğmesiyle aşağıdaki iki kaydı oluşturun.

**Birinci kayıt, ana domain için:**

```text
Type:  A Record
Host:  @
Value: SUNUCU_IP_ADRESINIZ
TTL:   Automatic
```

Bu kayıt `example.com` adresini sunucunuza yönlendirir.

**İkinci kayıt, gateway alt alan adları için:**

```text
Type:  A Record
Host:  *
Value: SUNUCU_IP_ADRESINIZ
TTL:   Automatic
```

Bu kayıt `herhangi-bir-ad.example.com` biçimindeki adresleri aynı sunucuya yönlendirir. AR.IO gateway'in wildcard alan adlarıyla çalışabilmesi için gereklidir.

Her iki kayıtta da `SUNUCU_IP_ADRESINIZ` yerine kendi gateway sunucunuzun public IPv4 adresini yazın. Kayıtları kaydettikten sonra DNS'in etkinleşmesi için yaklaşık 30 dakika bekleyin.

Namecheap ekranında `Host Records` bölümü düzenlenemiyorsa DNS'iniz Namecheap tarafından yönetilmiyor olabilir. Bu durumda kolay kuruluma devam etmeden önce nameserver ayarınızı kontrol edin.

Resmi anlatımlar: [AR.IO ağ kurulumu](https://docs.ar.io/build/run-a-gateway/quick-start/#set-up-networking) ve [Namecheap A kaydı rehberi](https://www.namecheap.com/support/knowledgebase/article.aspx/319/2237/how-can-i-set-up-an-a-address-record-for-my-domain/).

## Kolay kurulumda sorulara ne yazılacak?

Aşağıdaki sıra terminalde göreceğiniz kolay kurulum akışıdır.

### 1. Kurulum modu

```text
Seciminiz [1]:
```

**Cevap:** Yalnızca `Enter` tuşuna basın. `1`, yeni kullanıcı için önerilen kolay kurulumdur.

Kolay mod otomatik olarak şunları seçer:

- güvenli indexed disk koruması;
- `%90` temizleme başlangıcı, `%85` hedefi ve 20 GiB boş alan rezervi;
- Namecheap üzerinden otomatik SSL yenileme;
- observer yüklemeleri için Turbo;
- kapalı epoch cranking ve kapalı x402.

### 2. Gateway alan adı

```text
Gateway alan adi:
```

**Cevap örneği:** `example.com`

`https://`, `/` ile biten yol veya `*.` yazmayın.

### 3. Ana Solana gateway adresi

```text
Ana Solana gateway adresi:
```

**Cevap:** AR.IO Network kaydınızdaki operator wallet'ın public adresi. Buraya seed phrase veya private key yazılmaz.

### 4. Observer Solana adresi

```text
Observer Solana adresi (Enter = ana wallet ile ayni) [operator-adresiniz]:
```

- Observer ve operator aynı wallet ise yalnızca `Enter` tuşuna basın.
- AR.IO kaydınızda ayrı observer tanımlıysa onun public adresini yazın.

### 5. Solana RPC

```text
Solana RPC URL [https://api.mainnet-beta.solana.com]:
```

**Önerilen cevap:** Sağlayıcınızdan aldığınız tam mainnet RPC URL'sini yapıştırın.

Helius örneği:

```text
https://mainnet.helius-rpc.com/?api-key=ANAHTARINIZ
```

Yalnızca API key veya `/v0/transactions` gibi Enhanced API adresi yazmayın. Özel RPC'niz henüz yoksa `Enter` public RPC ile kurulumu sürdürür.

### 6. Namecheap API ve IPv4 whitelist

Kurucu sunucunun public IPv4 adresini gösterecek:

```text
Sunucu public IPv4: SUNUCU_IP_ADRESINIZ
API erisimi acik ve bu IPv4 whitelist'e eklendi mi [y/N]:
```

Namecheap'te `Profile > Tools > Namecheap API Access > Whitelisted IPs` yolunu açın, ekranda gösterilen IPv4 adresini ekleyin ve sonra terminale `y` yazın.

Ardından:

```text
Namecheap kullanici adi:
Namecheap API key (yazdiginiz gorunmez):
```

Namecheap kullanıcı adınızı ve API key'inizi girin. API key terminalde görünmez; yazdıktan sonra `Enter` tuşuna basın.

### 7. Kurulum özeti

Terminal domain, operator, observer, disk, SSL, cranking ve x402 seçimlerini gösterecek:

```text
Bu ayarlarla kurulumu baslatayim mi [Y/n]:
```

Bilgiler doğruysa yalnızca `Enter` tuşuna basın. Yanlışsa `n` yazıp kurulumu yeniden başlatın.

### 8. Sunucu ve DNS ön kontrolü

Sunucu resmi minimumların altındaysa şu soru görünür:

```text
Resmi minimumlardan dusuk olmasina ragmen devam edilsin mi [y/N]:
```

Yeni kullanıcı için önerilen cevap `n` değeridir. Sunucu özelliklerini düzelttikten sonra kurulumu yeniden çalıştırın.

Ana domain veya wildcard DNS henüz çözümlenmiyorsa:

```text
DNS hala yayiliyor; yine de devam edilsin mi [y/N]:
```

`n` yazın veya yalnızca `Enter` tuşuna basın. İki DNS kaydı da sunucu IP'sine ulaşınca kurulumu yeniden çalıştırın. DNS tamamlanmadan wildcard sertifika alınamaz.

### 9. Keypair

Operator keypair adımında üç seçenek çıkar:

```text
1) Sunucudaki keypair JSON dosyasinin yolu (onerilen)
2) JSON array, seed phrase veya base58 private key yapistir
3) Simdilik atla
Seciminiz [1]:
```

Önerilen yöntem:

1. `Enter` ile birinci seçeneği seçin.
2. Keypair dosyanız sunucuda `/root/id.json` ise bu yolu yazın.
3. Kurucu dosyadan türetilen public adresi kontrol eder. Girdiğiniz operator adresiyle eşleşmiyorsa anahtarı kabul etmez.

Ayrı observer wallet kullandıysanız aynı adım observer keypair için de sorulur. `3` ile atlarsanız gateway veri sunabilir fakat observer veya gerekli protokol imzaları çalışmaz.

Seed phrase ve private key'i sohbetlere, destek kanallarına veya web formlarına yazmayın.

## Kurulum bitince

Şu komutları sırayla çalıştırın:

```bash
gateway-release-check
gateway-doctor
gateway-check
gateway-observer-check
gateway-cert-check
gateway-balance
```

| Komut | Beklenen sonuç |
|---|---|
| `gateway-release-check` | Çalışan sürüm, son resmi sürüm ve Release 83 temel kontrolleri |
| `gateway-doctor` | Temel kontrollerin `OK` görünmesi |
| `gateway-check` | Test verisi olarak `1984`, gateway bilgisi ve çalışan servisler |
| `gateway-observer-check` | Observer yapılandırması, keypair ve rapor durumu |
| `gateway-cert-check` | Namecheap authenticator, sertifika tarihi ve aktif yenileme timer'ı |
| `gateway-balance` | Observer wallet'ın SOL bakiyesi |

## Gateway'i kullanmak

İnteraktif yönetim menüsü:

```bash
gateway
```

Tüm kısa yollar ve açıklamaları:

```bash
gateway-help
```

Günlük kullanımda en çok gerekenler:

| Komut | Ne yapar? |
|---|---|
| `gateway-status` | Servis, CPU, RAM, disk ve inode durumunu gösterir |
| `gateway-logs` | Gateway ve observer loglarını canlı gösterir; `Ctrl+C` servisleri durdurmaz |
| `gateway-release-check` | Çalışan node sürümünü son resmi sürümle karşılaştırır ve yeni retrieval metriklerini kontrol eder |
| `gateway-check` | Public veri, gateway info, observer raporu ve servisleri test eder |
| `gateway-doctor` | Sağlık, TLS, disk, anahtarlar ve yapılandırma için kapsamlı teşhis yapar |
| `gateway-update` | Gateway'i güvenli biçimde günceller; persistent veriyi silmez |
| `gateway-restart` | Volume silmeden servisleri yeniden oluşturur ve kontrol eder |
| `gateway-storage` | Disk koruması ve cache durumunu gösterir |
| `gateway-cert-check` | Sertifika süresini ve otomatik yenilemeyi kontrol eder |
| `gateway-cert-manual` | Gateway çalışırken Namecheap TXT kaydıyla manuel wildcard sertifika yeniler |
| `gateway-observer-check` | Observer, keypair, epoch ve son hataları kontrol eder |
| `gateway-balance` | Observer veya verilen Solana adresinin bakiyesini gösterir |

## Observer kısa açıklama

Observer, AR.IO Network içindeki gateway'lerin erişilebilirliğini ve performansını değerlendirir. Gateway'in içerik sunması ile observer'ın rapor üretmesi farklı görevlerdir.

| Wallet | Görevi |
|---|---|
| Operator wallet | Gateway'in ağ kaydı ve gerekli operator işlemleri |
| Observer wallet | Observer kimliği ve gözlem işlemlerinin imzalanması |
| Upload signer | Observer rapor verisinin yüklenmesi |

`ENABLE_EPOCH_CRANKING=false` observer'ı kapatmaz. Cranking yalnızca opsiyonel epoch ilerletme işlemleridir.

Observer kontrolü için:

```bash
gateway-observer-check
gateway-balance
gateway-network-info
gateway-logs
```

İlk açılışta raporun bir süre hazır olmaması gateway'in bozuk olduğu anlamına gelmez. Keypair eşleşmesi, servis sağlığı ve loglar birlikte kontrol edilmelidir.

## Release 83 kontrolü

Yeni kurulum Release 83 ile gelen önerilen temeli açıkça uygular: ArNS önce zincirden çözülür, son resolver bekleme süresi 5 saniyedir, `leaving` durumundaki gateway'ler peer olarak kullanılmaz, chunk cache index tabanlı temizlenir ve aynı veriye gelen eşzamanlı istekler birleştirilir.

Kurulu sürümü, ayarları ve `short_reads_rejected_total` dahil yeni metrikleri görmek için:

```bash
gateway-release-check
```

Mevcut bir gateway'i Release 83'e geçirmek için sırasıyla:

```bash
gateway-tools-update
gateway-update
gateway-storage-setup
gateway-release-check
```

`FOREGROUND_CACHE_MAX_SIZE` ve `FOREGROUND_CACHE_CONCURRENCY` için tek bir doğru değer yoktur. Resmi sürüm bunları varsayılan olarak sınırsız bırakır; bu repo da sunucunun trafik ve disk yapısını bilmeden rastgele sınır koymaz. Durumu görmek için `gateway-cache-advisor` kullanılabilir.

## Sertifikayı manuel yenilemek

Namecheap API kullanmak istemeyen bir operatör wildcard sertifikayı gateway'i kapatmadan yenileyebilir:

```bash
sudo gateway-cert-manual
```

Komut önce mevcut son kullanma tarihini ve kalan gün sayısını gösterir. Sertifikanın bitmesine 30 günden fazla varsa gereksiz Let's Encrypt isteğini önlemek için varsayılan cevap `Hayır` olur. Devam edilirse Certbot DNS TXT doğrulaması başlatılır; `docker compose down`, NGINX `stop` veya `restart` çalıştırılmaz.

Certbot ekranda bir kayıt adı ve uzun bir TXT değeri gösterdiğinde Namecheap'te şu yolu açın:

`Domain List > Manage > Advanced DNS > Host Records > Add New Record > TXT Record`

| Sertifika alan adı | Namecheap `Host` alanı |
|---|---|
| `example.com` | `_acme-challenge` |
| `gateway.example.com` ve satın alınan domain `example.com` | `_acme-challenge.gateway` |

`Value` alanına Certbot'un o adımda gösterdiği değeri eksiksiz yapıştırın, `TTL` değerini `Automatic` bırakın. Certbot aynı Host için ikinci bir değer isterse ilkini silmeyin; iki TXT kaydını da doğrulama tamamen bitene kadar tutun.

İkinci bir SSH penceresinde komutun ekranda verdiği `dig` kontrolünü çalıştırın. Beklenen TXT değeri görünmeden Certbot ekranında `Enter` tuşuna basmayın. Certbot başarı bildirdikten sonra yardımcı komut:

1. NGINX yapılandırmasını `nginx -t` ile doğrular.
2. NGINX'i kesintisiz `reload` eder.
3. Yeni sertifika bitiş tarihini tekrar gösterir.

Eski sertifika doğrulama başarısız olduğunda yerinde kalır ve gateway çalışmayı sürdürür. Başarılı işlemden sonra geçici `_acme-challenge` TXT kayıtlarını silebilirsiniz. Manuel sertifika kendi kendine yenilenmez; sonraki yenilemede aynı komutu tekrar çalıştırın. Otomatiğe geçmek isterseniz `sudo gateway-cert-setup` ile Namecheap DNS API seçeneğini kullanın.

## Mevcut gateway'e yalnız yönetim araçlarını eklemek

Gateway'i yeniden kurmadan kısa yolları eklemek veya güncellemek için:

```bash
curl -fsSL https://raw.githubusercontent.com/Vevivo/ario-gateway-manager/main/update-tools.sh | sudo bash
```

## İleri özellikler

x402, Grafana, ANS-104 filtreleri, apex içerik, verification headers, CDB64, moderation, gelişmiş depolama ve SSL işlemleri ilk kurulum ekranını kalabalıklaştırmaz. Kurulumdan sonra şu menüden açılır:

```bash
gateway-features
```

Ayrıntılı işletim rehberi: [Gateway işletimi ve ileri özellikler](docs/OPERATIONS.md)

Planlanan geliştirmeler: [Geliştirme yol haritası](docs/ROADMAP.md)

## Güvenlik

- Gateway uygulama verileri `/opt/ar-io-gateway` altında tutulur ve Docker kaynakları domain'e özel proje adıyla ayrılır.
- Node'un `3000`, `4000` ve `5050` portları yalnız localhost'a bağlıdır; public giriş NGINX üzerinden `80/443` ile yapılır.
- Mevcut NGINX varsayılan sitesi, başka site dosyaları ve kapalı UFW durumu değiştirilmez.
- Otomatik bakım `data/sqlite`, `data/redis` veya wallet dosyalarını silmez.
- `docker compose down -v`, kontrolsüz `rm -rf` ve `docker volume prune` kullanılmaz.
- Disk baskısı ar-io-node'un kendi cache reclaimer mekanizmasıyla yönetilir.
- `.env` değişiklik öncesinde yedeklenir ve secret dosyaları kısıtlı izinlerle saklanır.
- Sertifika Certbot tarafından kontrol edilir; başarılı yenilemede NGINX yapılandırması doğrulanıp reload edilir.
- Zincir üstü kayıt, stake ve para transferleri otomatik çalıştırılmaz.

## Resmi kaynaklar

- [Gateway Installation & Setup](https://docs.ar.io/build/run-a-gateway/quick-start/)
- [Manage your Gateway](https://docs.ar.io/build/run-a-gateway/manage/)
- [Automating SSL](https://docs.ar.io/build/run-a-gateway/manage/ssl-certs/)
- [AR.IO SDK](https://docs.ar.io/sdks/ar-io-sdk/)
- [Official ar-io-node repository](https://github.com/ar-io/ar-io-node)
- [AR.IO Node Release 83](https://github.com/ar-io/ar-io-node/releases/tag/r83)

Bu repo resmi AR.IO yazılımının yerine geçmez; resmi `ar-io-node` kurulumunu ve operasyonunu kolaylaştıran bir topluluk aracıdır.
