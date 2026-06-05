import javassist.*;
import java.io.File;
import java.net.URL;
import java.net.URLClassLoader;

/**
 * PreallocPatch — elektronik-imza.jar içindeki IAIK wrapper sürüm tutarsızlığını giderir.
 *
 * SORUN (Apple Silicon'da connect çökmesi):
 *   Jar, macOS için İKİ farklı çağdan IAIK native wrapper taşır:
 *     libs/macos/intel/   → ppc64/ppc7400/i386/x86_64  (ANTİK IAIK, eski Java sınıflarıyla uyumlu)
 *     libs/macos/aarch64/ → x86_64/arm64               (MODERN IAIK)
 *   Apple Silicon'da modern wrapper seçilir ve connect sırasında
 *   (arm64 slice disassembly ile doğrulandı):
 *       FindClass(env, "iaik/pkcs/pkcs11/wrapper/PKCS11")              // <-- ARAYÜZ (impl değil!)
 *       GetMethodID(env, <o sınıf>, "isDisableBufferPreAllocation", "()Z")
 *       assert(jMethod != 0)                                          // pkcs11wrapper.h:490
 *       CallBooleanMethod(obj, jMethod)
 *   Metod eski PKCS11 ARAYÜZÜNDE yok → jMethod==0 → assert → abort (SIGABRT).
 *
 * ÇÖZÜM:
 *   Metodu PKCS11 arayüzüne + PKCS11Implementation'a ekle.
 *   - Arayüz: ABSTRACT olmalı. jar Java 7 (major 51, Manifest Build-Jdk:1.7.0_75)
 *     derlemesidir; major<52 arayüzde 'default' (gövdeli) metod ClassFormatError verir
 *     ("illegal modifiers: 0x1"). abstract (0x401) her sürümde legaldir; GetMethodID
 *     abstract arayüz metodunu da bulur, CallBooleanMethod impl'e dispatch eder.
 *   - Impl: gövdeli, true döndürür (= ön-tahsis kapalı → legacy yol). Tek implementer
 *     PKCS11Implementation olduğu için arayüzü abstract bırakmak güvenli.
 *
 *   NOT: Metodu yalnız impl'e eklemek YETMEZ (release 3.1.2_2 hatası); GetMethodID
 *   FindClass("...PKCS11") arayüzünde yapılır. Yalnız arayüze 'default' eklemek de
 *   YETMEZ (3.1.2_3 hatası); major 51 default metodu reddeder.
 *
 * Kullanım:  java -cp javassist.jar:. PreallocPatch <jar> <çıktı-dizini>
 *   args[0] = patchlenecek jar (içeriği okunur)   args[1] = patchli .class kök dizini
 *
 * Idempotent: metod zaten varsa o sınıf atlanır. Sonda yamalı sınıfları yükleyip
 * ClassFormatError'a karşı doğrular (kart/native lib gerektirmez).
 */
public class PreallocPatch {
    static final String[] CLASSES = {
        "iaik.pkcs.pkcs11.wrapper.PKCS11",                // arayüz — GetMethodID hedefi (abstract)
        "iaik.pkcs.pkcs11.wrapper.PKCS11Implementation"   // impl   — sanal dispatch (return true)
    };
    static final String METH = "isDisableBufferPreAllocation";

    public static void main(String[] args) throws Exception {
        if (args.length != 2) {
            System.err.println("kullanım: PreallocPatch <jar> <çıktı-dizini>");
            System.exit(2);
        }
        ClassPool pool = new ClassPool(true);
        pool.insertClassPath(args[0]);
        for (String cn : CLASSES) {
            CtClass cc = pool.get(cn);
            if (cc.isFrozen()) cc.defrost();
            boolean exists = false;
            for (CtMethod m : cc.getDeclaredMethods()) {
                if (m.getName().equals(METH)) { exists = true; break; }
            }
            if (exists) {
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
            System.out.println("[patch] " + cn + ": " + METH + "() eklendi"
                + (cc.isInterface() ? " (abstract)" : " (return true)"));
        }
        // Doğrulama: yamalı sınıflar ClassFormatError'suz yüklenebiliyor mu?
        // out dizini önce (yamalı, imzasız), bağımlılıklar için orijinal jar sonra.
        URL[] urls = { new File(args[1]).toURI().toURL(), new File(args[0]).toURI().toURL() };
        try (URLClassLoader cl = new URLClassLoader(urls, PreallocPatch.class.getClassLoader())) {
            for (String cn : CLASSES) Class.forName(cn, false, cl);  // false = static-init yok
        }
        System.out.println("[patch] doğrulama OK: yamalı sınıflar yüklenebiliyor (ClassFormatError yok)");
    }
}
