# e-Devlet E-İmza (Türksat) — native Apple Silicon (arm64) build
# Asıl mantık scripts/build.sh içinde. Bu Makefile ince bir sarmalayıcıdır.

SH := bash scripts/build.sh

.PHONY: all check-deps jdk jpackage-jdk download icns package sign run clean distclean help

all: ## ARM64 .app'i üret (varsayılan)
	@$(SH) all

check-deps: ## Araçları, arm64 Java 11 ve jpackage'ı denetle
	@$(SH) check-deps

jdk: ## Gömülecek arm64 Java 11 yoksa Azul Zulu 11 kur
	@$(SH) jdk

jpackage-jdk: ## jpackage'lı 17+ JDK yoksa Azul Zulu 21 kur
	@$(SH) jpackage-jdk

download: ## elektronik-imza.jar + ikon indir + doğrula
	@$(SH) download

icns: ## .icns ikon üret
	@$(SH) icns

package: ## jpackage ile .app üret (Java 11 gömülü)
	@$(SH) package

sign: ## ad-hoc codesign
	@$(SH) sign

run: ## üretilen .app'i aç
	@$(SH) run

clean: ## build/ sil (indirilenleri korur)
	@$(SH) clean

distclean: ## build/ + indirilenler sil
	@$(SH) distclean

help: ## Bu yardım
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed -E 's/:.*## /\t/' | sort
