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
 *       checkBufferPreAllocation, Java tarafında isDisableBufferPreAllocation()
 *       metodunu GetMethodID ile arar. Bu metod eski PKCS11Implementation
 *       sınıfında YOK → jMethod==0 → assert → abort (SIGABRT).
 *
 * ÇÖZÜM:
 *   Sınıfa eksik metodu ekle. true döndürür = "buffer ön-tahsisi kapalı" →
 *   modern wrapper, eski Java sınıflarının desteklediği legacy yola düşer.
 *
 * Kullanım:  java -cp javassist.jar:. PreallocPatch <jar> <çıktı-dizini>
 *   args[0] = patchlenecek jar (içeriği okunur)
 *   args[1] = patchli .class'ın yazılacağı kök dizin (iaik/.../X.class ağacı oluşur)
 *
 * Idempotent: metod zaten varsa hiçbir şey yapmaz.
 */
public class PreallocPatch {
    static final String CLS  = "iaik.pkcs.pkcs11.wrapper.PKCS11Implementation";
    static final String METH = "isDisableBufferPreAllocation";

    public static void main(String[] args) throws Exception {
        if (args.length != 2) {
            System.err.println("kullanım: PreallocPatch <jar> <çıktı-dizini>");
            System.exit(2);
        }
        ClassPool pool = new ClassPool(true);
        pool.insertClassPath(args[0]);
        CtClass cc = pool.get(CLS);
        if (cc.isFrozen()) cc.defrost();

        for (CtMethod m : cc.getDeclaredMethods()) {
            if (m.getName().equals(METH)) {
                System.out.println("[patch] " + METH + "() zaten var — atlandı");
                return;
            }
        }
        cc.addMethod(CtNewMethod.make(
            "public boolean " + METH + "() { return true; }", cc));
        cc.writeFile(args[1]);
        System.out.println("[patch] " + METH + "() eklendi -> " + CLS);
    }
}
