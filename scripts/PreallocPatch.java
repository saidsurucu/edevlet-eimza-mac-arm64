import javassist.*;

/**
 * PreallocPatch — elektronik-imza.jar içindeki IAIK wrapper sürüm tutarsızlığını giderir.
 *
 * SORUN (Apple Silicon'da connect çökmesi):
 *   Jar, macOS için İKİ farklı çağdan IAIK native wrapper taşır:
 *     libs/macos/intel/   → ppc64/ppc7400/i386/x86_64  (ANTİK IAIK, eski Java sınıflarıyla uyumlu)
 *     libs/macos/aarch64/ → x86_64/arm64               (MODERN IAIK)
 *   IAIK wrapper native lib'i os.arch'a göre seçer:
 *     - Intel/Rosetta (x86_64) → antik intel wrapper → çalışır.
 *     - Apple Silicon (aarch64) → modern wrapper → connect sırasında
 *       checkBufferPreAllocation şunu yapar (arm64 slice disassembly ile doğrulandı):
 *         FindClass(env, "iaik/pkcs/pkcs11/wrapper/PKCS11")              // <-- ARAYÜZ
 *         GetMethodID(env, <o sınıf>, "isDisableBufferPreAllocation", "()Z")
 *         assert(jMethod != 0)                                          // pkcs11wrapper.h:490
 *       Metod eski PKCS11 ARAYÜZÜNDE yok → jMethod==0 → assert → abort (SIGABRT).
 *
 * ÇÖZÜM:
 *   Metodu PKCS11 ARAYÜZÜNE **default** olarak ekle (GetMethodID arayüzde bulur;
 *   CallBooleanMethod impl örneğine dispatch eder). Dispatch'i kesinleştirmek için
 *   PKCS11Implementation'a da ekle. true döndürür = "ön-tahsis kapalı" → legacy yol.
 *
 *   NOT: Metod IMPL sınıfına eklemek TEK BAŞINA YETMEZ; wrapper GetMethodID'yi
 *   FindClass("...PKCS11") (arayüz) üzerinde yapar. Asıl hedef arayüzdür.
 *
 * Kullanım:  java -cp javassist.jar:. PreallocPatch <jar> <çıktı-dizini>
 *   args[0] = patchlenecek jar (içeriği okunur)
 *   args[1] = patchli .class'ların yazılacağı kök dizin (iaik/.../X.class ağacı oluşur)
 *
 * Idempotent: metod zaten varsa o sınıf atlanır.
 */
public class PreallocPatch {
    // Sıra önemli: arayüz asıl hedef (GetMethodID burada), impl dispatch için.
    static final String[] CLASSES = {
        "iaik.pkcs.pkcs11.wrapper.PKCS11",                // arayüz — GetMethodID hedefi
        "iaik.pkcs.pkcs11.wrapper.PKCS11Implementation"   // impl   — sanal dispatch
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
            // Gövdeli + non-abstract metod: arayüzde otomatik 'default' olur.
            cc.addMethod(CtNewMethod.make(
                "public boolean " + METH + "() { return true; }", cc));
            cc.writeFile(args[1]);
            System.out.println("[patch] " + cn + ": " + METH + "() eklendi"
                + (cc.isInterface() ? " (default)" : ""));
        }
    }
}
