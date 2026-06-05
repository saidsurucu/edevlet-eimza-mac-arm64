#!/bin/bash
#
# build.sh — e-Devlet E-İmza (Türksat) için native Apple Silicon (arm64) .app üretir.
#
# Kaynak: https://static.turkiye.gov.tr/downloads/e-imza/edevlet-eimza.jnlp
#   Java Web Start uygulaması; JWS Java 11+'da kaldırıldığı için Mac'te açılamıyor.
#   Çözüm: ana jar + main-class'ı jpackage ile arm64 **Java 11** runtime'ı GÖMÜLEREK
#   çift-tıkla açılan native .app'e paketle.
#
# Neden Java 11 (Java 8 değil):
#   - Java 11 = otomatik HiDPI (JEP 263) → Retina'da KESKİN metin (Java 8 arm64 Swing bulanık).
#   - elektronik-imza.jar = Java 8 bytecode (major 52) → Java 11'de sorunsuz çalışır.
#
# Kart erişimi (KRİTİK FARK — UDE'den):
#   - e-İmza, javax.smartcardio DEĞİL, **IAIK PKCS#11 wrapper** ile karta erişir.
#   - arm64 native kütüphane jar'da GÖMÜLÜ ve universal:
#       libs/macos/aarch64/libpkcs11wrapper.jnilib = Mach-O universal (x86_64 + arm64).
#     Wrapper os.arch'a göre seçer → Apple Silicon'da native arm64 yüklenir.
#   - Bu yüzden UDE'deki sqlite native-swap / PCSC -D bayrağı GEREKMEZ.
#   - AKİS PKCS#11 modülü (libakisp11.dylib) uygulama içi ayardan seçilir;
#     kullanıcıda arm64 AKİS middleware kurulu olmalı.
#
# Tam JRE şart (jlink-strip DEĞİL): smartcardio/pkcs11/crypto provider'ları için
#   --runtime-image <tam arm64 Zulu 11>.
#
# Engeller ve çözümleri:
#   1) JWS (jnlp) doğrudan açılmıyor -> jpackage in-process JVM'li native launcher
#   2) Java 8 arm64 Retina yok      -> Java 11 runtime gömülür
#   3) all-permissions / kripto refl.-> gerekirse --add-opens (açılışta hata olursa)
#   4) IAIK arm64 wrapper ↔ Java sınıfı sürüm tutarsızlığı (jar'daki Java sınıfları
#      Java 7/major51 ESKİ; libs/macos/aarch64 wrapper MODERN). İki belirti:
#      (A) connect: checkBufferPreAllocation -> FindClass("…/PKCS11") (ARAYÜZ) +
#          GetMethodID("isDisableBufferPreAllocation","()Z") -> arayüzde yok ->
#          jMethod==0 -> SIGABRT. (B) C_SignInit: modern CK_*_PARAMS sınıflarını
#          FindClass+IsInstanceOf ile arar -> eski jar'da olmayanlar ->
#          NoClassDefFoundError. Çözüm: 'patch' adımı (Javassist) (A) için metodu
#          PKCS11 arayüzüne ABSTRACT + impl'e gövdeli ekler, (B) için eksik 11
#          param sınıfını boş stub olarak ekler ve hepsini yükletip doğrular;
#          bkz. scripts/PreallocPatch.java.
#   + ASCII executable adı (codesign Türkçe karakterle bozuluyor) + ad-hoc imza
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD="$ROOT/build"
DOWNLOADS="$ROOT/downloads"

APP_NAME="E-Devlet E-İmza"          # görünen ad (Türkçe)
APP="$BUILD/$APP_NAME.app"
ASCII_NAME="EDevletEImza"           # executable/CFBundleExecutable (ASCII şart, codesign)
BUNDLE_ID="tr.gov.turkiye.esignui"
MAIN_CLASS="tr.gov.turkiye.esignui.run.StartFrame"
MAIN_JAR="elektronik-imza.jar"
# Görünen ürün sürümü (uygulama pencere başlığından doğrulandı: "… Uygulaması 3.1.2").
# CFBundleVersion buna eşitlenir; yayın etiketi <APP_VERSION>_<N> olur.
APP_VERSION="${APP_VERSION:-3.1.2}"

CODEBASE="https://static.turkiye.gov.tr/downloads/e-imza"
JAR_URL="${JAR_URL:-$CODEBASE/$MAIN_JAR}"
ICON_URL="${ICON_URL:-$CODEBASE/e-imza-icon256.png}"
JAR_FILE="$DOWNLOADS/$MAIN_JAR"
ICON_PNG="$DOWNLOADS/e-imza-icon256.png"
ICNS="$BUILD/EDevletEImza.icns"

# Gömülecek arm64 Java 11 (runtime). 'jdk' hedefi Azul Zulu 11'i kurar.
JDK11_DEST="$HOME/Library/Java/JavaVirtualMachines/zulu-11-arm64.jdk"
# jpackage için 17+ JDK. 'jpackage-jdk' Zulu 21 kurar.
JDK21_DEST="$HOME/Library/Java/JavaVirtualMachines/zulu-21-arm64.jdk"

# IAIK arm64 connect-çökmesi patch'i (bkz. üstteki engel #4 + scripts/PreallocPatch.java).
# Eksik metodu bytecode'a eklemek için Javassist gerekir; sürüm + sha256 pinli.
JAVASSIST_VER="3.30.2-GA"
JAVASSIST_URL="https://repo1.maven.org/maven2/org/javassist/javassist/${JAVASSIST_VER}/javassist-${JAVASSIST_VER}.jar"
JAVASSIST_SHA256="eba37290994b5e4868f3af98ff113f6244a6b099385d9ad46881307d3cb01aaf"
JAVASSIST_JAR="$DOWNLOADS/javassist-${JAVASSIST_VER}.jar"
PATCHER_SRC="$SCRIPT_DIR/PreallocPatch.java"
# Wrapper GetMethodID'yi FindClass("…/PKCS11") (ARAYÜZ) üzerinde yapar → doğrulama hedefi arayüz.
PATCH_VERIFY_FQCN="iaik.pkcs.pkcs11.wrapper.PKCS11"
PATCH_METHOD="isDisableBufferPreAllocation"

c_ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
c_info() { printf '\033[36m▸\033[0m %s\n' "$*"; }
c_warn() { printf '\033[33m!\033[0m %s\n' "$*"; }
c_err()  { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; }
die()    { c_err "$*"; exit 1; }

# Gerçekten istenen major sürüm mü (java_home yanlış sürüm döndürebiliyor)
jhome() {  # $1=major  $2=hedef .jdk
	if [ -x "$2/Contents/Home/bin/java" ]; then echo "$2/Contents/Home"; return 0; fi
	local h; h="$(/usr/libexec/java_home -v "$1" -a arm64 2>/dev/null || true)"
	if [ -n "$h" ] && "$h/bin/java" -version 2>&1 | grep -q "version \"$1"; then echo "$h"; fi
	return 0
}
jdk11_home() { jhome 11 "$JDK11_DEST"; }

find_jpackage() {
	local v jh
	for v in 25 24 23 22 21 20 19 18 17; do
		jh="$(/usr/libexec/java_home -v "$v" -a arm64 2>/dev/null || true)"
		[ -n "$jh" ] && [ -x "$jh/bin/jpackage" ] && { echo "$jh/bin/jpackage"; return 0; }
	done
	local home
	for home in $(/usr/libexec/java_home -V 2>&1 | grep -oE '/[^ ]+/Contents/Home' | sort -u); do
		[ -x "$home/bin/jpackage" ] && { echo "$home/bin/jpackage"; return 0; }
	done
	return 1
}

install_zulu() {  # $1=java_version  $2=hedef .jdk
	c_info "Azul Zulu $1 (aarch64) indiriliyor…"
	local url
	url="$(curl -s "https://api.azul.com/metadata/v1/zulu/packages/?java_version=$1&os=macos&arch=aarch64&archive_type=tar.gz&java_package_type=jdk&javafx_bundled=false&latest=true&release_status=ga&availability_types=CA&page=1&page_size=1" \
		| /usr/bin/python3 -c 'import sys,json;d=json.load(sys.stdin);print(d[0]["download_url"])')"
	[ -n "$url" ] || die "Zulu $1 URL'si alınamadı."
	mkdir -p "$DOWNLOADS"; local tmp="$DOWNLOADS/zulu$1.tgz"
	curl -fSL --retry 5 -o "$tmp" "$url"
	gzip -t "$tmp" 2>/dev/null || die "Zulu $1 indirme bozuk."
	local stage; stage="$(mktemp -d)"; tar xzf "$tmp" -C "$stage"
	local b; b="$(find "$stage" -maxdepth 1 -type d -name 'zulu*' | head -1)"
	[ -n "$b" ] || die "Zulu $1 arşiv yapısı farklı."
	mkdir -p "$(dirname "$2")"; rm -rf "$2"; mv "$b" "$2"; rm -rf "$stage"
}

# jpackage'lı JDK'nın kök dizini (javac/jar/javap patch için lazım)
jpackage_home() {
	local jp; jp="$(find_jpackage)" || return 1
	echo "${jp%/bin/jpackage}"
}

# Javassist'i (sürüm + sha256 pinli) önbelleğe indirir/doğrular.
fetch_javassist() {
	if [ -s "$JAVASSIST_JAR" ] && shasum -a 256 "$JAVASSIST_JAR" | grep -q "$JAVASSIST_SHA256"; then
		c_ok "Javassist önbellekten (checksum OK)"; return 0
	fi
	c_info "Javassist $JAVASSIST_VER indiriliyor…"
	mkdir -p "$DOWNLOADS"
	curl -fL --retry 3 -o "$JAVASSIST_JAR" "$JAVASSIST_URL"
	shasum -a 256 "$JAVASSIST_JAR" | grep -q "$JAVASSIST_SHA256" \
		|| die "Javassist checksum uyuşmadı (beklenen $JAVASSIST_SHA256)."
	c_ok "Javassist doğrulandı"
}

# IAIK modern-wrapper uyumsuzluğunu giderir: (A) PKCS11 arayüzüne+impl'e
# isDisableBufferPreAllocation() (connect SIGABRT), (B) eksik CK_*_PARAMS stub'ları
# (C_SignInit NoClassDefFoundError). $1 = staged jar. İmza geçersizleşir → silinir.
patch_jar() {  # $1 = jar yolu
	local jar="$1"
	[ -s "$jar" ] || die "patch: jar yok: $jar"
	local jph; jph="$(jpackage_home)" || die "patch için jpackage'lı JDK yok → scripts/build.sh jpackage-jdk"
	[ -x "$jph/bin/javac" ] || die "javac bulunamadı: $jph/bin"
	[ -f "$PATCHER_SRC" ]   || die "patcher kaynağı yok: $PATCHER_SRC"
	fetch_javassist

	c_info "IAIK arm64 connect-fix uygulanıyor ($PATCH_METHOD)…"
	local work; work="$(mktemp -d)"
	"$jph/bin/javac" -cp "$JAVASSIST_JAR" -d "$work" "$PATCHER_SRC" \
		|| { rm -rf "$work"; die "patcher derlenemedi."; }
	"$jph/bin/java" -cp "$JAVASSIST_JAR:$work" PreallocPatch "$jar" "$work/out" \
		|| { rm -rf "$work"; die "patch çalışmadı."; }
	# patcher'ın yazdığı tüm patchli .class'ları (PKCS11 arayüzü + impl) jar'a yaz
	local rel found=0
	while IFS= read -r rel; do
		"$jph/bin/jar" uf "$jar" -C "$work/out" "$rel" \
			|| { rm -rf "$work"; die "jar güncellenemedi: $rel"; }
		found=1
	done < <(cd "$work/out" && find iaik -name '*.class' 2>/dev/null)
	[ "$found" = 1 ] || { rm -rf "$work"; die "patcher hiç .class üretmedi."; }
	# Sınıf değişti → imza tutmaz; imza dosyaları kalırsa classloader SecurityException atar.
	zip -dq "$jar" 'META-INF/*.SF' 'META-INF/*.RSA' 'META-INF/*.DSA' >/dev/null 2>&1 || true
	rm -rf "$work"
	# Doğrula: metod, wrapper'ın GetMethodID hedefi olan PKCS11 ARAYÜZÜNDE mi?
	"$jph/bin/javap" -p -classpath "$jar" "$PATCH_VERIFY_FQCN" 2>/dev/null | grep -q "$PATCH_METHOD" \
		|| die "patch doğrulanamadı: $PATCH_METHOD, $PATCH_VERIFY_FQCN içinde görünmüyor."
	c_ok "Patch uygulandı + doğrulandı (connect-fix + eksik CK_*_PARAMS sınıfları, imza temizlendi)"
}

# ----- Hedefler -----

check_deps() {
	c_info "Ön koşullar denetleniyor…"
	local t
	for t in curl unzip zip codesign plutil sips iconutil shasum; do
		command -v "$t" >/dev/null 2>&1 || die "Gerekli araç yok: $t"
	done
	c_ok "Araçlar mevcut"
	local ok=0
	[ -n "$(jdk11_home)" ] && c_ok "arm64 Java 11 (runtime): $(jdk11_home)" || { c_warn "arm64 Java 11 YOK → scripts/build.sh jdk"; ok=1; }
	if jp="$(find_jpackage)"; then c_ok "jpackage: $jp"; else c_warn "jpackage'lı 17+ JDK YOK → scripts/build.sh jpackage-jdk"; ok=1; fi
	return $ok
}

jdk() {
	[ -n "$(jdk11_home)" ] && { c_ok "arm64 Java 11 zaten kurulu."; return 0; }
	install_zulu 11 "$JDK11_DEST"
	[ -n "$(jdk11_home)" ] && c_ok "Kuruldu: $JDK11_DEST" || die "Java 11 kurulum sonrası görünmüyor."
}

jpackage_jdk() {
	find_jpackage >/dev/null 2>&1 && { c_ok "jpackage zaten var."; return 0; }
	install_zulu 21 "$JDK21_DEST"
	find_jpackage >/dev/null 2>&1 && c_ok "jpackage hazır." || die "jpackage bulunamadı."
}

download() {
	c_info "elektronik-imza.jar + ikon indiriliyor (codebase: $CODEBASE)…"
	mkdir -p "$DOWNLOADS" "$BUILD"
	[ -s "$JAR_FILE" ] && c_ok "Önbellekten: $JAR_FILE ($(du -h "$JAR_FILE" | cut -f1))" \
		|| { c_info "İndiriliyor: $JAR_URL"; curl -fL --retry 3 -o "$JAR_FILE" "$JAR_URL"; }
	# Doğrula: main-class + gömülü arm64 native kütüphane
	# (içeriği önce değişkene al; grep -q erken çıkıp pipefail'i tetiklemesin)
	local mf list
	mf="$(unzip -p "$JAR_FILE" META-INF/MANIFEST.MF)"
	[[ "$mf" == *"$MAIN_CLASS"* ]] || die "Main-Class bulunamadı (bozuk jar?)."
	list="$(unzip -l "$JAR_FILE")"
	[[ "$list" == *"libs/macos/aarch64/libpkcs11wrapper.jnilib"* ]] || die "arm64 PKCS#11 native kütüphanesi jar'da yok!"
	c_ok "jar doğrulandı (main-class + arm64 native lib mevcut)"
	[ -s "$ICON_PNG" ] || { c_info "İkon indiriliyor: $ICON_URL"; curl -fL --retry 3 -o "$ICON_PNG" "$ICON_URL"; }
	c_ok "İkon hazır: $ICON_PNG"
}

icns() {
	[ -s "$ICON_PNG" ] || die "Önce 'download' çalıştır (ikon yok)."
	c_info ".icns üretiliyor (e-imza-icon256.png)…"
	mkdir -p "$BUILD"
	local set; set="$BUILD/EDevletEImza.iconset"; rm -rf "$set"; mkdir -p "$set"
	# Kaynak 256x256 → küçültmeler (256'nın üstünü upscale etmeyiz)
	local s
	for s in 16 32 128 256; do
		sips -z "$s" "$s" "$ICON_PNG" --out "$set/icon_${s}x${s}.png" >/dev/null
		local d=$((s*2))
		[ "$d" -le 256 ] && sips -z "$d" "$d" "$ICON_PNG" --out "$set/icon_${s}x${s}@2x.png" >/dev/null
	done
	# 256 @2x (512) ve 512 — kaynak 256 olduğundan upscale; yine de tam iconset için ekle
	sips -z 512 512 "$ICON_PNG" --out "$set/icon_256x256@2x.png" >/dev/null
	sips -z 512 512 "$ICON_PNG" --out "$set/icon_512x512.png" >/dev/null
	iconutil -c icns "$set" -o "$ICNS" || die "iconutil başarısız."
	rm -rf "$set"
	c_ok ".icns üretildi: $ICNS"
}

package() {
	[ -s "$JAR_FILE" ] || die "Önce 'download' çalıştır."
	[ -s "$ICNS" ] || icns
	local jp; jp="$(find_jpackage)" || die "jpackage yok → scripts/build.sh jpackage-jdk"
	local rt; rt="$(jdk11_home)"; [ -n "$rt" ] || die "Java 11 yok → scripts/build.sh jdk"
	[ -f "$rt/lib/jli/libjli.dylib" ] || die "Java 11 runtime layout farklı: $rt"

	c_info "jpackage girdisi hazırlanıyor…"
	local in="$BUILD/_input"; rm -rf "$in"; mkdir -p "$in"
	cp "$JAR_FILE" "$in/"
	# Apple Silicon connect-çökmesi düzeltmesi (IAIK arm64 wrapper ↔ Java sınıfı uyumsuzluğu).
	# Pristine downloads/ kopyasına değil, staged kopyaya uygulanır.
	patch_jar "$in/$MAIN_JAR"

	c_info "jpackage ile .app paketleniyor (Java 11 gömülü, v$APP_VERSION)…"
	rm -rf "$APP" "$BUILD/$ASCII_NAME.app"
	"$jp" --type app-image --name "$ASCII_NAME" --app-version "$APP_VERSION" \
		--input "$in" --main-jar "$MAIN_JAR" --main-class "$MAIN_CLASS" \
		--runtime-image "$rt" \
		--java-options '-Djava.net.preferIPv4Stack=true' \
		--icon "$ICNS" \
		--mac-package-identifier "$BUNDLE_ID" \
		--dest "$BUILD" 2>&1 | grep -viE 'NoSuchElement|No value' || true
	[ -d "$BUILD/$ASCII_NAME.app" ] || die "jpackage .app üretemedi."

	local plist="$BUILD/$ASCII_NAME.app/Contents/Info.plist"
	plutil -replace CFBundleName -string "$APP_NAME" "$plist"
	plutil -replace CFBundleDisplayName -string "$APP_NAME" "$plist" 2>/dev/null \
		|| plutil -insert CFBundleDisplayName -string "$APP_NAME" "$plist"
	# Retina keskinlik (JEP 263 + bu bayrak)
	plutil -replace NSHighResolutionCapable -bool true "$plist"
	mv "$BUILD/$ASCII_NAME.app" "$APP"
	c_ok "Paketlendi: $APP ($(du -sh "$APP" | cut -f1))"
}

sign() {
	[ -d "$APP" ] || die "Önce 'package' çalıştır."
	c_info "ad-hoc imzalanıyor…"
	find "$APP" -name '._*' -delete 2>/dev/null || true
	codesign --force -s - --identifier "$BUNDLE_ID" "$APP"
	codesign --verify --strict "$APP" 2>/dev/null && c_ok "İmza geçerli (adhoc, strict)" || die "İmza doğrulanamadı."
}

run() {
	[ -d "$APP" ] || die "Önce 'all' çalıştır."
	c_info "Açılıyor: $APP"
	open "$APP"
}

all() {
	check_deps || die "Ön koşul eksik (jdk / jpackage-jdk)."
	download; icns; package; sign
	echo
	c_ok "BİTTİ → $APP"
	c_info "Çalıştır: open \"$APP\"   |   Kur: /Applications'a sürükle"
	c_warn "E-imza ancak gerçek kart + arm64 PKCS#11 middleware (AKİS) ile test edilebilir."
}

clean()     { c_info "build/ temizleniyor…"; rm -rf "$BUILD"; c_ok "temiz"; }
distclean() { c_info "build/ + downloads/ temizleniyor…"; rm -rf "$BUILD" "$DOWNLOADS"; c_ok "temiz"; }

help() {
	cat <<EOF
build.sh — e-Devlet E-İmza native arm64 .app üretici (Java 11 gömülü)

Hedefler:
  all          Tüm hattı çalıştır (varsayılan): download → icns → package → sign
  check-deps   Araç + arm64 Java 11 + jpackage denetimi
  jdk          Gömülecek arm64 Java 11 yoksa Azul Zulu 11 kur
  jpackage-jdk jpackage'lı 17+ JDK yoksa Azul Zulu 21 kur
  download     elektronik-imza.jar + ikon indir + doğrula
  icns         .icns ikon üret
  package      jpackage ile .app üret (Java 11 gömülü + IAIK arm64 connect-fix)
  sign         ad-hoc codesign
  run          üretilen .app'i aç
  clean / distclean

Ortam: JAR_URL / ICON_URL (kaynak), APP_VERSION (vars: $APP_VERSION)
EOF
}

case "${1:-all}" in
	all) all ;; check-deps) check_deps ;; jdk) jdk ;; jpackage-jdk) jpackage_jdk ;;
	download) download ;; icns) icns ;; package) package ;; sign) sign ;; run) run ;;
	clean) clean ;; distclean) distclean ;;
	help|-h|--help) help ;;
	*) die "Bilinmeyen hedef: $1  (scripts/build.sh help)" ;;
esac
