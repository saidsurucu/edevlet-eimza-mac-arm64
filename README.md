# e-Devlet E-İmza — Native Apple Silicon (arm64) .app

[e-Devlet E-İmza Uygulaması](https://www.turkiye.gov.tr) (Türksat), bir Java Web
Start (JNLP) uygulamasıdır. Java Web Start, Java 11+ ile kaldırıldığından
uygulama modern Mac'lerde kolayca açılamıyor. Bu depo, uygulamayı **gömülü
arm64 Java 11 runtime'ı** ile **çift tıklayıp açabileceğiniz native bir
`.app`'e** paketler — Rosetta gerektirmez, ayrıca Java kurmanıza gerek kalmaz.

> Resmî değildir; hiçbir kamu kurumu tarafından geliştirilmemiş/onaylanmamıştır.
> "Olduğu gibi" sunulur.

> ✅ Apple Silicon'da **gerçek kartla tam imzalama** (sertifika → PIN → imza →
> UYAP girişi) doğrulandı. (Tek bir kurulumda test edildi; yine de farklı
> kart/sürücü sürümlerinde değişiklik olabilir.)

> ⚠️ **E-imza için arm64 AKİS sürücüsü ŞART** (aşağıdaki adım 4). Uygulama
> native arm64'tür; kart sürücünüz de arm64 olmalıdır, yoksa kart işlemleri
> sırasında `libakisp11.dylib … yüklenemedi` hatası alırsınız.

---

## Kurulum (son kullanıcı)

1. [Releases](../../releases) sayfasından **zip'i indirin** ve çift tıklayarak
   açın (içinden `E-Devlet E-İmza.app` çıkar).
2. Çıkan uygulamayı **Uygulamalar (Applications)** klasörüne sürükleyin.
3. İlk açılışta macOS "geliştirici doğrulanamadı" diyebilir. Bir kez aşmak için
   **Terminal**'i açıp (`⌘ + Boşluk` → `Terminal` → Enter) şu satırı yapıştırıp
   Enter'a basın:
   ```
   xattr -dr com.apple.quarantine "/Applications/E-Devlet E-İmza.app"
   ```
   Komut bir şey yazmadan biter (normaldir). Artık çift tıklayarak açabilirsiniz.
4. **Apple Silicon (arm64) AKİS kart sürücüsünü kurun** — aşağıdaki bölüme bakın.

---

## ⚠️ Apple Silicon (arm64) AKİS sürücüsü kurulumu (zorunlu)

Bu uygulama native arm64 çalışır. Kart erişimi, sistemdeki AKİS PKCS#11 modülünü
(`/usr/local/lib/libakisp11.dylib`) yükleyerek olur. **Bir arm64 uygulama, yalnızca
Intel (x86_64) derlenmiş bir sürücüyü yükleyemez** (mimari uyuşmazlığı). TÜBİTAK
AKİS'in macOS için **ayrı Intel ve Apple Silicon paketleri** vardır; çoğu kullanıcıda
eski/Intel sürüm kuruludur.

**Belirti:** Kart tipi olarak "Tubitak AKİS" seçip DEVAM'a basınca:

> `/usr/local/lib/libakisp11.dylib kütüphanesi yüklenemedi. Lütfen doğru kart
> tipini seçtiğinize ve akıllı kartınıza ait kurulumların doğru yapıldığına emin olun.`

**Çözüm:** Apple Silicon AKİS paketini kurun:

1. [TÜBİTAK BİLGEM AKİS — Destek/İndirme](https://akiskart.bilgem.tubitak.gov.tr/tr/destek/)
   sayfasından **"Mac OS Arm (Apple Silicon)"** başlığı altındaki güncel paketi indirin
   (ör. `Akia_macos_arm_6_8_9.pkg`). **"Mac OS Intel" paketini değil**, Arm paketini seçin.
2. İndirilen `.pkg`'a çift tıklayıp kurulumu tamamlayın (yönetici şifresi ister).
3. **E-Devlet E-İmza** uygulamasını kapatıp yeniden açın; kart takılıyken
   "Kart Tipi: Tubitak AKİS" → DEVAM.

**Doğru sürümü kurduğunuzu teyit:** Terminal'de şu komut **`x86_64 arm64`** (veya
en azından `arm64`) yazmalı — sadece `x86_64` yazıyorsa hâlâ Intel sürüm kuruludur:

```
lipo -archs /usr/local/lib/libakisp11.dylib
```

---

## Derleme (geliştirici)

Gereksinimler kendiliğinden kurulur (Azul Zulu 11 + 21). Apple Silicon Mac'te:

```bash
make all          # download → icns → package → sign
make run          # üretilen .app'i aç
```

Tek tek hedefler için `make help`.

### Nasıl çalışır

- `jpackage --type app-image` + `--runtime-image <tam arm64 Zulu 11>` ile
  uygulama ve **gömülü Java 11 runtime** tek bir native `.app`'e paketlenir.
  Tam JRE şarttır (jlink-strip değil): smartcardio/pkcs11/crypto provider'ları
  gerekir.
- **Neden Java 11:** otomatik HiDPI (JEP 263) → Retina'da keskin metin
  (arm64 Java 8 Swing bulanık render ediyor). `elektronik-imza.jar` Java 8
  bytecode'dur (major 52) ve Java 11'de sorunsuz çalışır.
- **Kart erişimi:** `javax.smartcardio` değil, **IAIK PKCS#11 wrapper** iledir.
  arm64 native kütüphane jar'ın içinde gömülü ve universal'dır:
  `libs/macos/aarch64/libpkcs11wrapper.jnilib` = Mach-O universal (x86_64 +
  arm64). Wrapper `os.arch`'a göre arm64'ü seçer. (UDE'deki gibi bir
  native-swap gerekmez.)
- **IAIK arm64 connect-fix (zorunlu yama):** jar, macOS için iki farklı çağdan
  IAIK native wrapper taşır — `libs/macos/intel/` **antik** (ppc/i386/x86_64,
  eski Java sınıflarıyla uyumlu) ve `libs/macos/aarch64/` **modern**. Apple
  Silicon'da modern wrapper seçilir ve `connect` sırasında (arm64 slice
  disassembly ile doğrulandı) `FindClass("…/wrapper/PKCS11")` (**arayüz**) +
  `GetMethodID("isDisableBufferPreAllocation","()Z")` yapar. Bu metod eski
  **PKCS11 arayüzünde** yoktur → `jMethod==0` → `assert` (`pkcs11wrapper.h:490`)
  → **SIGABRT** (kart takıp DEVAM deyince çöker). Ayrıca imzalama anında
  (`C_SignInit`) modern wrapper, eski jar'da olmayan bazı `CK_*_PARAMS`
  sınıflarını `FindClass`+`IsInstanceOf` ile arar → `NoClassDefFoundError`.
  Build her ikisini de Javassist ile giderir (`scripts/PreallocPatch.java`):
  **(A)** `isDisableBufferPreAllocation()`'ı PKCS11 arayüzüne `abstract` +
  `PKCS11Implementation`'a gövdeli ekler; **(B)** eksik 11 `CK_*_PARAMS` sınıfını
  boş public stub olarak ekler (imzalamada alan erişimi olmaz, IsInstanceOf false
  döner). Sonra tüm sınıfları yükletip doğrular; sınıflar değiştiği için jar
  imzası geçersizleşir, imza dosyaları (`META-INF/*.SF|RSA`) silinir (app-image'de
  imza doğrulaması yok). Bu fix olmadan paket **hiçbir** arm64 makinede imzalamaya
  ulaşamaz. (Notlar: yamayı yalnız impl'e eklemek yetmez — GetMethodID arayüzde
  yapılır; arayüze `default` eklemek de yetmez — Java 7/major-51 default metodu
  `ClassFormatError` ile reddeder, bu yüzden `abstract`.)
- **codesign + Türkçe karakter:** `.app` adındaki `İ` gibi karakterler imzayı
  bozuyor; bu yüzden executable ASCII tutulur (`EDevletEImza`), görünen ad
  sonradan `CFBundleName`/`CFBundleDisplayName` ile Türkçe yapılır. Ad-hoc imza
  (`codesign -s -`) uygulanır.

### JNLP gerçekleri (kaynak)

| Alan | Değer |
|------|-------|
| codebase | `https://static.turkiye.gov.tr/downloads/e-imza` |
| ana jar | `elektronik-imza.jar` (~1.1 MB, self-contained) |
| main-class | `tr.gov.turkiye.esignui.run.StartFrame` |
| j2se | 1.7+ · `java.net.preferIPv4Stack=true` · all-permissions |
| ikon | `e-imza-icon256.png` → `.icns` |

---

## Yayın (GitHub Actions)

`.github/workflows/release.yml` elle tetiklenir (`workflow_dispatch`):
macos-14 (arm64) runner'da `.app` üretir, mimariyi+imzayı doğrular, sürümü
`<APP_VERSION>_<N>` olarak etiketler (`<N>` otomatik artar) ve zip'i release'e
ekler.
