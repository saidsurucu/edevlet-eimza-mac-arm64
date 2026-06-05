import javassist.*;
import java.io.File;
import java.net.URL;
import java.net.URLClassLoader;
import java.util.ArrayList;
import java.util.List;

/**
 * PreallocPatch — elektronik-imza.jar içindeki IAIK wrapper sürüm tutarsızlığını giderir.
 *
 * SORUN (Apple Silicon):
 *   Jar, macOS için İKİ farklı çağdan IAIK native wrapper taşır:
 *     libs/macos/intel/   → ppc64/ppc7400/i386/x86_64  (ANTİK IAIK; eski Java 7 sınıflarıyla uyumlu)
 *     libs/macos/aarch64/ → x86_64/arm64               (MODERN IAIK)
 *   Apple Silicon'da modern wrapper seçilir ama jar'daki Java sınıfları ESKİdir
 *   (Java 7 / major 51, Manifest Build-Jdk:1.7.0_75). Modern wrapper'ın beklediği
 *   bazı şeyler eski sınıflarda yoktur → iki ayrı belirti (ikisi de burada giderilir):
 *
 *   (A) connect → checkBufferPreAllocation (arm64 disassembly):
 *         FindClass("iaik/pkcs/pkcs11/wrapper/PKCS11")  // ARAYÜZ
 *         GetMethodID("isDisableBufferPreAllocation","()Z"); assert(jMethod!=0)  // SIGABRT
 *       → Metod PKCS11 arayüzünde yok. ÇÖZÜM: arayüze ABSTRACT (major<52 'default'
 *         illegal → ClassFormatError) + PKCS11Implementation'a gövdeli (return true) ekle.
 *
 *   (B) C_SignInit → jMechanismParameterToCKMechanismParameter, param tipini
 *       FindClass+IsInstanceOf ile tespit ederken modern CK_*_PARAMS sınıflarını arar;
 *       eski jar'da olmayanlar → NoClassDefFoundError. ÇÖZÜM: eksik 11 sınıfı BOŞ public
 *       stub olarak ekle. Alan erişimi (GetFieldID) yalnız tipe-özel dönüştürücülerde ve
 *       yalnız param gerçekten o tipse olur; imzalama (RSA/ECDSA) bunları kullanmaz, bu
 *       yüzden IsInstanceOf false döner ve boş stub yeterlidir.
 *
 *   NOT: 3.1.2_2 (yalnız impl) ve 3.1.2_3 (arayüze 'default') sürümleri bu yüzden
 *   yetmedi; doğru çözüm yukarıdaki (A)+(B).
 *
 * Kullanım:  java -cp javassist.jar:. PreallocPatch <jar> <çıktı-dizini>
 * Idempotent. Sonda yamalı + üretilen sınıfları yükleyip doğrular (kart/native gerekmez).
 */
public class PreallocPatch {
    static final String PKG  = "iaik.pkcs.pkcs11.wrapper.";
    static final String METH = "isDisableBufferPreAllocation";

    // (A) Metod eklenecek sınıflar: arayüz (GetMethodID hedefi) + impl (dispatch).
    static final String[] METHOD_CLASSES = { PKG + "PKCS11", PKG + "PKCS11Implementation" };

    // (B) Modern wrapper'ın aradığı, eski jar'da OLMAYAN PKCS#11 param sınıfları (boş stub).
    static final String[] MISSING_PARAM_CLASSES = {
        "CK_CCM_MESSAGE_PARAMS", "CK_CCM_PARAMS", "CK_CHACHA20_PARAMS",
        "CK_ECDH_AES_KEY_WRAP_PARAMS", "CK_ECDSA_ECIES_PARAMS", "CK_GCM_MESSAGE_PARAMS",
        "CK_GCM_PARAMS", "CK_RSA_AES_KEY_WRAP_PARAMS",
        "CK_SALSA20_CHACHA20_POLY1305_MSG_PARAMS", "CK_SALSA20_CHACHA20_POLY1305_PARAMS",
        "CK_SALSA20_PARAMS"
    };

    public static void main(String[] args) throws Exception {
        if (args.length != 2) {
            System.err.println("kullanım: PreallocPatch <jar> <çıktı-dizini>");
            System.exit(2);
        }
        ClassPool pool = new ClassPool(true);
        pool.insertClassPath(args[0]);
        List<String> touched = new ArrayList<>();

        // (A) eksik metodu ekle
        for (String cn : METHOD_CLASSES) {
            CtClass cc = pool.get(cn);
            if (cc.isFrozen()) cc.defrost();
            if (hasMethod(cc)) {
                System.out.println("[patch] " + cn + ": " + METH + "() zaten var — atlandı");
                continue;
            }
            CtMethod m;
            if (cc.isInterface()) {
                m = CtNewMethod.abstractMethod(CtClass.booleanType, METH,
                        new CtClass[0], new CtClass[0], cc);
                m.setModifiers(Modifier.PUBLIC | Modifier.ABSTRACT);
            } else {
                m = CtNewMethod.make("public boolean " + METH + "() { return true; }", cc);
            }
            cc.addMethod(m);
            cc.writeFile(args[1]);
            touched.add(cn);
            System.out.println("[patch] " + cn + ": " + METH + "() eklendi"
                + (cc.isInterface() ? " (abstract)" : " (return true)"));
        }

        // (B) eksik param sınıflarını boş stub olarak ekle
        for (String simple : MISSING_PARAM_CLASSES) {
            String fqcn = PKG + simple;
            try { pool.get(fqcn); System.out.println("[patch] " + fqcn + ": zaten var"); continue; }
            catch (NotFoundException notFound) { /* eklenecek */ }
            CtClass nc = pool.makeClass(fqcn);   // public, Object'ten türer, default ctor
            nc.writeFile(args[1]);
            touched.add(fqcn);
            System.out.println("[patch] eksik param sınıfı eklendi: " + fqcn);
        }

        // Doğrulama: dokunulan tüm sınıflar yüklenebiliyor mu? (ClassFormatError/NoClassDef yakala)
        URL[] urls = { new File(args[1]).toURI().toURL(), new File(args[0]).toURI().toURL() };
        try (URLClassLoader cl = new URLClassLoader(urls, PreallocPatch.class.getClassLoader())) {
            for (String cn : touched) Class.forName(cn, false, cl);  // false = static-init yok
        }
        System.out.println("[patch] doğrulama OK: " + touched.size()
            + " sınıf yüklenebiliyor (ClassFormatError/NoClassDef yok)");
    }

    private static boolean hasMethod(CtClass cc) {
        for (CtMethod m : cc.getDeclaredMethods())
            if (m.getName().equals(METH)) return true;
        return false;
    }
}
