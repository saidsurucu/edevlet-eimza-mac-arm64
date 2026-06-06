# e-Devlet E-İmza — Native Apple Silicon (arm64) .app

[e-Devlet E-İmza Uygulaması](https://www.turkiye.gov.tr) (Türksat), bir Java Web
Start (JNLP) uygulamasıdır. Java Web Start, Java 11+ ile kaldırıldığından
uygulama modern Mac'lerde kolayca açılamıyor. Bu depo, uygulamayı **gömülü
arm64 Java 11 runtime'ı** ile **çift tıklayıp açabileceğiniz native bir
`.app`'e** paketler — Rosetta gerektirmez, ayrıca Java kurmanıza gerek kalmaz.

> ⚠️ **Bu depo e-Devlet E-İmza uygulamasının kaynak kodunu içermez.** Tamamen
> bağımsız, **gayriresmî** bir Mac **paketleyicisidir**: hiçbir kamu kurumu
> tarafından geliştirilmemiş/onaylanmamıştır. Burada bulunan yalnızca paketleme
> ve build betikleridir; resmî `elektronik-imza.jar` build sırasında
> turkiye.gov.tr'den **siz** indirir ve native `.app`'i **siz** üretirsiniz.
> "Olduğu gibi" sunulur.

> ✅ Apple Silicon'da **gerçek kartla tam imzalama** (sertifika → PIN → imza →
> UYAP girişi) doğrulandı. (Tek bir kurulumda test edildi; yine de farklı
> kart/sürücü sürümlerinde değişiklik olabilir.)

> 📦 **Hazır (paketlenmiş) uygulama dağıtılmaz.** İşgüzarlarla uğraşmak
> istemediğim için paketlenmiş hâlini dağıtmıyorum; uygulamayı **kendiniz
> derleyip paketlersiniz**. Bu sayfada bir "Releases" / hazır indirme bağlantısı
> **bulmazsınız**. Aşağıdaki adımlar derlemeyi olabildiğince kolaylaştırır —
> komutları kopyala-yapıştır ile çalıştırmanız yeterli.

---

# 👩‍⚖️ Kolay kurulum — kendiniz derleyin

Programcı olmanıza gerek yok; aşağıdaki komutları sırayla **kopyalayıp
yapıştırmanız** yeterli. Java vb. ayrıca kurmanıza gerek yoktur — gereken Java
sürümleri build sırasında **otomatik** indirilir.

### 1) Geliştirici araçlarını kurun (bir kez)

**Terminal** uygulamasını açın: klavyede `Command (⌘) + Boşluk`'a basın, açılan
kutuya **Terminal** yazıp **Enter**'a basın. Sonra şu satırı yapıştırıp
**Enter**'a basın:

```bash
xcode-select --install
```

Bir pencere açılırsa **"Yükle"**ye basıp bitmesini bekleyin. (Zaten kuruluysa
"already installed" der; sorun değil.)

### 2) Kaynak kodu indirin

İki yol var; **A yolu** en kolayıdır (tıkla-indir).

**A) ZIP olarak indirin (önerilir)**

1. Bu sayfanın sağ üstündeki yeşil **`< > Code`** düğmesine tıklayın.
2. Açılan menünün en altındaki **"Download ZIP"**e tıklayın. Dosya
   **İndirilenler** (Downloads) klasörünüze iner
   (`edevlet-eimza-mac-arm64-main.zip`).
3. İnen ZIP dosyasına **çift tıklayın**; yanında `edevlet-eimza-mac-arm64-main`
   adında bir klasör açılır.

Sonra **Terminal**'i açıp (`⌘ + Boşluk` → `Terminal` → Enter) şu satırı yapıştırın
ve **Enter**'a basın — bu, az önce açılan klasörün içine girer:

```bash
cd ~/Downloads/edevlet-eimza-mac-arm64-main
```

**B) Tek komutla indirin (Terminal'i biliyorsanız)**

```bash
git clone https://github.com/saidsurucu/edevlet-eimza-mac-arm64.git
cd edevlet-eimza-mac-arm64
```

### 3) Derleyin

Klasöre girdikten sonra (yukarıdaki `cd …` adımı) aşağıdaki bloğun **tamamını**
kopyalayıp Terminal'e yapıştırın, **Enter**'a basın:

```bash
make jdk           # gömülecek arm64 Java 11'i otomatik indirir
make jpackage-jdk  # paketleyici JDK'yı otomatik indirir
make all           # uygulamayı indirir + derler + paketler + imzalar
```

İlk derleme internet hızınıza göre birkaç dakika sürebilir. Bittiğinde uygulama
`build/E-Devlet E-İmza.app` olarak hazırdır.

### 4) Uygulamayı Applications'a taşıyın

```bash
mv "build/E-Devlet E-İmza.app" /Applications/
```

Artık **Launchpad** veya **Applications** klasöründen çift tıklayarak
açabilirsiniz. (Kendiniz derleyip imzaladığınız için macOS "geliştirici
doğrulanamadı" uyarısı **çıkmaz**; `xattr` ile uğraşmanıza gerek yoktur.)

> İsterseniz sürükle-bırak yerleşimli bir `.dmg` de üretebilirsiniz:
> `brew install create-dmg` sonrası `make dmg`.

> ⚠️ **E-imza için arm64 AKİS sürücüsü ŞART** (aşağıdaki bölüm). Uygulama native
> arm64'tür; kart sürücünüz de arm64 olmalıdır, yoksa kart işlemleri sırasında
> `libakisp11.dylib … yüklenemedi` hatası alırsınız.

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

# 🛠️ Mühendisler için — Teknik ayrıntı

Yukarıdaki adımlar derlemek için yeterlidir. Bu bölüm, tek tek build hedeflerini
ve dönüşümün **neyi nasıl** çözdüğünü açıklar. Gereksinimler kendiliğinden kurulur
(Azul Zulu 11 + 21). Apple Silicon Mac'te:

```bash
make all          # download → icns → package → sign
make run          # üretilen .app'i aç
make dmg          # sürükle-bırak yerleşimli .dmg üret (brew install create-dmg gerekir)
```

DMG arka planı `assets/dmg-background.svg`'den üretilir; düzenleyip `make assets`
ile yeniden render edebilirsiniz (`brew install librsvg`). Tek tek hedefler için `make help`.

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

## CI build (isteğe bağlı)

`.github/workflows/release.yml` elle tetiklenir (`workflow_dispatch`):
macos-14 (arm64) runner'da `.app` üretir ve mimariyi+imzayı doğrular. Bu yalnızca
derlemenin doğrulanması/kişisel kullanım içindir; bu depo **hazır paket dağıtmaz**
(bkz. en üstteki not).
