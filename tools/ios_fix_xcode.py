#!/usr/bin/env python3
"""Corrige un projet Xcode exporté par Godot 4.4.1 (preset « iOS »).

Usage : python3 tools/ios_fix_xcode.py build/ios/Maskit.xcodeproj

3. « Undefined symbol: _MTLIOErrorDomain » (Godot 4.7, metal-cpp) : Metal lié explicitement et
   constantes Metal absentes de certains SDK définies en faible (simulator_stubs.mm).

Défauts corrigés :
1. « Framework 'MetalFX' not found » : MetalFX n'existe pas dans le SDK du simulateur.
   → MetalFX n'est lié (en lien faible) que pour les vrais iPhone.
2. « Undefined symbol: _main » sur simulateur avec un Mac Apple Silicon : la bibliothèque
   officielle du simulateur ne contient que du x86_64 (même en Godot 4.7.2).
   → On fabrique une bibliothèque simulateur arm64 à partir de la bibliothèque iPhone arm64,
     en changeant la plateforme déclarée dans chaque objet Mach-O (iOS → iOS Simulator).
     Technique « arm64-to-sim » : même code machine, seule l'étiquette de plateforme change.
   → Les deux classes MetalFX référencées par Godot reçoivent des remplaçants vides pour le
     simulateur (fichier simulator_stubs.mm) ; elles ne servent qu'au moteur Vulkan/Metal,
     pas au moteur GL Compatibility utilisé par le jeu.
   Le simulateur tourne alors nativement (iPhone 16, 17, 18…), sans Rosetta.
"""
import re
import shutil
import struct
import sys
from pathlib import Path

LC_BUILD_VERSION = 0x32
LC_VERSION_MIN_IPHONEOS = 0x25
PLATFORM_IOS = 2
PLATFORM_IOSSIMULATOR = 7
MH_MAGIC_64 = 0xFEEDFACF
CPU_TYPE_ARM64 = 0x0100000C

STUBS = """// Généré par tools/ios_fix_xcode.py.
// 1. Constantes Metal référencées par metal-cpp (Godot 4.7) : selon la version du SDK d'Xcode,
//    certaines n'existent pas (MTLTensorDomain : iOS 26, MTLLogStateErrorDomain : iOS 18,
//    MTLIOErrorDomain : iOS 16, et le simulateur n'en exporte qu'une partie) → « Undefined symbol ».
//    Définitions faibles : ce ne sont que des noms (domaines d'erreur, compteurs de profilage), et
//    le moteur GL Compatibility du jeu n'utilise pas le pilote Metal de Godot.
// 2. Remplaçants des classes MetalFX pour le simulateur (MetalFX absent du SDK simulateur).
#include <TargetConditionals.h>
#import <Foundation/Foundation.h>
extern "C" {
extern __attribute__((weak)) NSString *const MTLBinaryArchiveDomain = @"MTLBinaryArchiveDomain";
extern __attribute__((weak)) NSString *const MTLCommandBufferEncoderInfoErrorKey = @"MTLCommandBufferEncoderInfoErrorKey";
extern __attribute__((weak)) NSString *const MTLCommonCounterClipperInvocations = @"MTLCommonCounterClipperInvocations";
extern __attribute__((weak)) NSString *const MTLCommonCounterClipperPrimitivesOut = @"MTLCommonCounterClipperPrimitivesOut";
extern __attribute__((weak)) NSString *const MTLCommonCounterComputeKernelInvocations = @"MTLCommonCounterComputeKernelInvocations";
extern __attribute__((weak)) NSString *const MTLCommonCounterFragmentCycles = @"MTLCommonCounterFragmentCycles";
extern __attribute__((weak)) NSString *const MTLCommonCounterFragmentInvocations = @"MTLCommonCounterFragmentInvocations";
extern __attribute__((weak)) NSString *const MTLCommonCounterFragmentsPassed = @"MTLCommonCounterFragmentsPassed";
extern __attribute__((weak)) NSString *const MTLCommonCounterPostTessellationVertexCycles = @"MTLCommonCounterPostTessellationVertexCycles";
extern __attribute__((weak)) NSString *const MTLCommonCounterPostTessellationVertexInvocations = @"MTLCommonCounterPostTessellationVertexInvocations";
extern __attribute__((weak)) NSString *const MTLCommonCounterRenderTargetWriteCycles = @"MTLCommonCounterRenderTargetWriteCycles";
extern __attribute__((weak)) NSString *const MTLCommonCounterSetStageUtilization = @"MTLCommonCounterSetStageUtilization";
extern __attribute__((weak)) NSString *const MTLCommonCounterSetStatistic = @"MTLCommonCounterSetStatistic";
extern __attribute__((weak)) NSString *const MTLCommonCounterSetTimestamp = @"MTLCommonCounterSetTimestamp";
extern __attribute__((weak)) NSString *const MTLCommonCounterTessellationCycles = @"MTLCommonCounterTessellationCycles";
extern __attribute__((weak)) NSString *const MTLCommonCounterTessellationInputPatches = @"MTLCommonCounterTessellationInputPatches";
extern __attribute__((weak)) NSString *const MTLCommonCounterTimestamp = @"MTLCommonCounterTimestamp";
extern __attribute__((weak)) NSString *const MTLCommonCounterTotalCycles = @"MTLCommonCounterTotalCycles";
extern __attribute__((weak)) NSString *const MTLCommonCounterVertexCycles = @"MTLCommonCounterVertexCycles";
extern __attribute__((weak)) NSString *const MTLCommonCounterVertexInvocations = @"MTLCommonCounterVertexInvocations";
extern __attribute__((weak)) NSString *const MTLCounterErrorDomain = @"MTLCounterErrorDomain";
extern __attribute__((weak)) NSString *const MTLIOErrorDomain = @"MTLIOErrorDomain";
extern __attribute__((weak)) NSString *const MTLLogStateErrorDomain = @"MTLLogStateErrorDomain";
extern __attribute__((weak)) NSString *const MTLTensorDomain = @"MTLTensorDomain";
}
// 3. Écran 120 Hz (ProMotion) : Godot 4.7 fixe l'affichage iOS à 60 images/s
//    (GDTView.preferredFrameRate = 60). On le remplace, à l'initialisation de la vue, par la
//    fréquence maximale de l'écran ; Engine.max_fps (réglage « Images par seconde » du jeu)
//    limite ensuite à 120, 60 ou 30. Nécessite CADisableMinimumFrameDurationOnPhone (Info.plist).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
static void (*raiders_orig_common_init)(id, SEL) = NULL;
static void raiders_common_init(id self, SEL _cmd) {
	if (raiders_orig_common_init) {
		raiders_orig_common_init(self, _cmd);
	}
	NSInteger maxFps = [UIScreen mainScreen].maximumFramesPerSecond;
	if (maxFps > 60 && [self respondsToSelector:@selector(setPreferredFrameRate:)]) {
		((void (*)(id, SEL, float))objc_msgSend)(self, @selector(setPreferredFrameRate:), (float)maxFps);
	}
}
__attribute__((constructor)) static void raiders_enable_promotion(void) {
	Class cls = NSClassFromString(@"GDTView");
	if (cls == Nil) {
		return;
	}
	Method m = class_getInstanceMethod(cls, NSSelectorFromString(@"godot_commonInit"));
	if (m != NULL) {
		raiders_orig_common_init = (void (*)(id, SEL))method_setImplementation(m, (IMP)raiders_common_init);
	}
}
#if TARGET_OS_SIMULATOR
@interface MTLFXSpatialScalerDescriptor : NSObject
@end
@implementation MTLFXSpatialScalerDescriptor
@end
@interface MTLFXTemporalScalerDescriptor : NSObject
@end
@implementation MTLFXTemporalScalerDescriptor
@end
#endif
"""


def patch_macho(buf: bytearray, off: int, size: int) -> tuple[int, int]:
    """Passe un objet Mach-O arm64 en plateforme simulateur. Renvoie (patchés, non gérés)."""
    if size < 32:
        return 0, 0
    magic, cputype = struct.unpack_from("<II", buf, off)
    if magic != MH_MAGIC_64 or cputype != CPU_TYPE_ARM64:
        return 0, 0
    ncmds, = struct.unpack_from("<I", buf, off + 16)
    p = off + 32
    patched = unhandled = 0
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", buf, p)
        if cmd == LC_BUILD_VERSION:
            platform, = struct.unpack_from("<I", buf, p + 8)
            if platform == PLATFORM_IOS:
                struct.pack_into("<I", buf, p + 8, PLATFORM_IOSSIMULATOR)
                # Le simulateur arm64 n'existe qu'à partir d'iOS 14 : minos relevé si besoin
                minos, = struct.unpack_from("<I", buf, p + 12)
                if minos < 0x000E0000:
                    struct.pack_into("<I", buf, p + 12, 0x000E0000)
                patched += 1
        elif cmd == LC_VERSION_MIN_IPHONEOS:
            unhandled += 1
        p += cmdsize
    return patched, unhandled


def make_simulator_archive(device_lib: Path, out_lib: Path) -> None:
    buf = bytearray(device_lib.read_bytes())
    assert buf[:8] == b"!<arch>\n", "archive ar attendue"
    pos = 8
    patched = unhandled = members = 0
    while pos + 60 <= len(buf):
        hdr = bytes(buf[pos:pos + 60])
        name = hdr[:16].decode("ascii", "replace").strip()
        size = int(hdr[48:58].decode().strip())
        data = pos + 60
        name_len = 0
        if name.startswith("#1/"):
            name_len = int(name[3:])
        members += 1
        a, b = patch_macho(buf, data + name_len, size - name_len)
        patched += a
        unhandled += b
        pos = data + size + (size & 1)
    if unhandled:
        raise SystemExit(f"{unhandled} objets utilisent LC_VERSION_MIN_IPHONEOS : conversion impossible")
    out_lib.write_bytes(buf)
    print(f"Bibliothèque simulateur arm64 : {patched} objets convertis sur {members} membres.")


def add_stub_source(text: str, proj_dir: Path, app_dir: Path) -> str:
    (app_dir / "simulator_stubs.mm").write_text(STUBS, encoding="utf-8")
    if "simulator_stubs.mm" in text:
        return text
    build_id, ref_id = "5A1A5A1A5A1A5A1A5A1A0001", "5A1A5A1A5A1A5A1A5A1A0002"
    # PBXBuildFile
    text = text.replace(
        "/* Begin PBXBuildFile section */\n",
        "/* Begin PBXBuildFile section */\n"
        f"\t\t{build_id} /* simulator_stubs.mm in Sources */ = {{isa = PBXBuildFile; fileRef = {ref_id} /* simulator_stubs.mm */; }};\n", 1)
    # PBXFileReference : placé à côté de dummy.cpp (même groupe, même dossier)
    text = text.replace(
        "/* Begin PBXFileReference section */\n",
        "/* Begin PBXFileReference section */\n"
        f"\t\t{ref_id} /* simulator_stubs.mm */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.cpp.objcpp; path = simulator_stubs.mm; sourceTree = \"<group>\"; }};\n", 1)
    text = re.sub(r"(^\s*)([0-9A-F]{24}) /\* dummy\.cpp \*/,\n",
                  lambda m: m.group(0) + f"{m.group(1)}{ref_id} /* simulator_stubs.mm */,\n", text, count=1, flags=re.M)
    text = re.sub(r"(^\s*)([0-9A-F]{24}) /\* dummy\.cpp in Sources \*/,\n",
                  lambda m: m.group(0) + f"{m.group(1)}{build_id} /* simulator_stubs.mm in Sources */,\n", text, count=1, flags=re.M)
    return text


def main() -> None:
    proj_dir = Path(sys.argv[1])
    name = proj_dir.stem
    root = proj_dir.parent
    pbx = proj_dir / "project.pbxproj"
    text = pbx.read_text(encoding="utf-8")

    # 1. MetalFX : retiré de la phase de lien, lié seulement pour les vrais iPhone
    m = re.search(r"^\s*([0-9A-F]{24}) /\* MetalFX\.framework in Frameworks \*/ = \{isa = PBXBuildFile;.*\n", text, re.M)
    if m:
        text = text.replace(m.group(0), "")
        text = re.sub(r"^\s*" + m.group(1) + r" /\* MetalFX\.framework in Frameworks \*/,\n", "", text, flags=re.M)
    m = re.search(r"^\s*([0-9A-F]{24}) /\* MetalFX\.framework \*/ = \{isa = PBXFileReference;.*\n", text, re.M)
    if m:
        text = text.replace(m.group(0), "")
        text = re.sub(r"^\s*" + m.group(1) + r" /\* MetalFX\.framework \*/,\n", "", text, flags=re.M)
    flag = '\t\t\t\t"OTHER_LDFLAGS[sdk=iphoneos*]" = "$(LD_CLASSIC_$(XCODE_VERSION_ACTUAL)) -framework Metal -weak_framework MetalFX";\n'
    # Metal n'est référencé que par metal-cpp (C++, pas d'autolink) : lien explicite partout.
    text = re.sub(r'^(\s*OTHER_LDFLAGS = "\$\(LD_CLASSIC_\$\(XCODE_VERSION_ACTUAL\)\))(\s*)";',
                  lambda mm: mm.group(1) + ' -framework Metal";' if "-framework Metal" not in mm.group(0) else mm.group(0),
                  text, flags=re.M)
    text = text.replace('-weak_framework MetalFX";', '-framework Metal -weak_framework MetalFX";')
    text = text.replace('-framework Metal -framework Metal', '-framework Metal')
    if "OTHER_LDFLAGS[sdk=iphoneos*]" not in text:
        text = re.sub(r"(^\s*OTHER_LDFLAGS = .*;\n)", lambda mm: mm.group(1) + flag, text, flags=re.M)

    # Ancien correctif Rosetta (versions précédentes de ce script) : retiré
    text = re.sub(r'^\s*"EXCLUDED_ARCHS\[sdk=iphonesimulator\*\]" = arm64;\n', "", text, flags=re.M)

    # 2. Bibliothèque simulateur arm64 fabriquée depuis celle de l'iPhone
    xcf = root / f"{name}.xcframework"
    dev = xcf / "ios-arm64" / "libgodot.a"
    old_sim = xcf / "ios-arm64_x86_64-simulator"
    new_sim = xcf / "ios-arm64-simulator"
    if dev.exists():
        if old_sim.exists():
            shutil.rmtree(old_sim)
        new_sim.mkdir(exist_ok=True)
        make_simulator_archive(dev, new_sim / "libgodot.a")
        (xcf / "Info.plist").write_text("""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AvailableLibraries</key>
	<array>
		<dict>
			<key>LibraryIdentifier</key>
			<string>ios-arm64</string>
			<key>LibraryPath</key>
			<string>libgodot.a</string>
			<key>SupportedArchitectures</key>
			<array>
				<string>arm64</string>
			</array>
			<key>SupportedPlatform</key>
			<string>ios</string>
		</dict>
		<dict>
			<key>LibraryIdentifier</key>
			<string>ios-arm64-simulator</string>
			<key>LibraryPath</key>
			<string>libgodot.a</string>
			<key>SupportedArchitectures</key>
			<array>
				<string>arm64</string>
			</array>
			<key>SupportedPlatform</key>
			<string>ios</string>
			<key>SupportedPlatformVariant</key>
			<string>simulator</string>
		</dict>
	</array>
	<key>CFBundlePackageType</key>
	<string>XFWK</string>
	<key>XCFrameworkFormatVersion</key>
	<string>1.0</string>
</dict>
</plist>
""", encoding="utf-8")
    # Le simulateur n'a qu'une architecture : arm64 (Mac Apple Silicon)
    excl = '\t\t\t\t"EXCLUDED_ARCHS[sdk=iphonesimulator*]" = x86_64;\n'
    if "EXCLUDED_ARCHS[sdk=iphonesimulator*]" not in text:
        text = re.sub(r"(^\s*OTHER_LDFLAGS = .*;\n)", lambda mm: mm.group(1) + excl, text, flags=re.M)

    # 3. Remplaçants MetalFX pour le simulateur
    text = add_stub_source(text, proj_dir, root / name)

    # 4. Écran 120 Hz (ProMotion) autorisé sur iPhone
    plist = root / name / f"{name}-Info.plist"
    if plist.exists():
        pl = plist.read_text(encoding="utf-8")
        if "CADisableMinimumFrameDurationOnPhone" not in pl:
            i = pl.rfind("</dict>")
            pl = pl[:i] + "\t<key>CADisableMinimumFrameDurationOnPhone</key>\n\t<true/>\n" + pl[i:]
            plist.write_text(pl, encoding="utf-8")
    else:
        print("Attention : Info.plist introuvable (%s), 120 Hz non activé." % plist)

    pbx.write_text(text, encoding="utf-8")
    print("Projet corrigé : Metal lié, constantes Metal manquantes remplacées, MetalFX seulement sur iPhone, simulateur arm64 natif, écran 120 Hz (ProMotion) activé.")


if __name__ == "__main__":
    main()
