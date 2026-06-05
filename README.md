# e-Devlet E-İmza — Native Apple Silicon (arm64) .app

[e-Devlet E-İmza Uygulaması](https://www.turkiye.gov.tr) (Türksat), bir Java Web
Start (JNLP) uygulamasıdır. Java Web Start, Java 11+ ile kaldırıldığından
uygulama modern Mac'lerde kolayca açılamıyor. Bu depo, uygulamayı **gömülü
arm64 Java 11 runtime'ı** ile **çift tıklayıp açabileceğiniz native bir
`.app`'e** paketler — Rosetta gerektirmez, ayrıca Java kurmanıza gerek kalmaz.

> Resmî değildir; hiçbir kamu kurumu tarafından geliştirilmemiş/onaylanmamıştır.
> "Olduğu gibi" sunulur.

> ⚠️ **E-imza:** Uygulama açılıyor ve kart seçim ekranı (Retina'da keskin)
> sorunsuz geliyor; PKCS#11 katmanı yükleniyor (kart tipi listesinde "TÜBİTAK
> AKİS" görünüyor). **Tam imzalama akışı gerçek kartla doğrulanmalıdır.**

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

Kart işlemleri için sistemde **arm64 PKCS#11 token middleware** (TÜBİTAK AKİS
vb.) kurulu olmalıdır.

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
  arm64). Wrapper `os.arch`'a göre arm64'ü seçer → native çalışır. (UDE'deki
  gibi bir native-swap gerekmez.)
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
