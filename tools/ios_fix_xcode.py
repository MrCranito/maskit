#!/usr/bin/env python3
"""Corrige un projet Xcode exporté par Godot 4.4.1 pour qu'il compile aussi sur le simulateur iOS.

Problème : Godot lie MetalFX.framework pour toutes les cibles, mais le SDK du simulateur
ne le fournit pas (erreur « Framework 'MetalFX' not found »). La bibliothèque Godot du
simulateur n'utilise pas MetalFX ; seule celle de l'iPhone en a besoin.

Correctif : retire MetalFX de la phase « Link Binary With Libraries » et le lie uniquement
pour les vrais appareils via OTHER_LDFLAGS[sdk=iphoneos*] (en lien faible).
Usage : python3 tools/ios_fix_metalfx.py build/ios/Maskit.xcodeproj
"""
import re
import sys
from pathlib import Path

proj = Path(sys.argv[1]) / "project.pbxproj"
text = proj.read_text(encoding="utf-8")

# 1. Retirer l'entrée PBXBuildFile et sa référence dans la phase Frameworks
m = re.search(r"^\s*([0-9A-F]{24}) /\* MetalFX\.framework in Frameworks \*/ = \{isa = PBXBuildFile;.*\n", text, re.M)
if m:
    build_id = m.group(1)
    text = text.replace(m.group(0), "")
    text = re.sub(r"^\s*" + build_id + r" /\* MetalFX\.framework in Frameworks \*/,\n", "", text, flags=re.M)

# 1 bis. Retirer la référence de fichier (sinon Xcode l'affiche en rouge sur le simulateur)
m = re.search(r"^\s*([0-9A-F]{24}) /\* MetalFX\.framework \*/ = \{isa = PBXFileReference;.*\n", text, re.M)
if m:
    ref_id = m.group(1)
    text = text.replace(m.group(0), "")
    text = re.sub(r"^\s*" + ref_id + r" /\* MetalFX\.framework \*/,\n", "", text, flags=re.M)

# 2. Lier MetalFX seulement pour l'iPhone
flag = '\t\t\t\t"OTHER_LDFLAGS[sdk=iphoneos*]" = "$(LD_CLASSIC_$(XCODE_VERSION_ACTUAL)) -weak_framework MetalFX";\n'
if "OTHER_LDFLAGS[sdk=iphoneos*]" not in text:
    text = re.sub(r"(^\s*OTHER_LDFLAGS = .*;\n)", lambda mm: mm.group(1) + flag, text, flags=re.M)

# 3. Simulateur : la bibliothèque Godot 4.4.1 du simulateur ne contient que du x86_64
#    (malgré son Info.plist). Sur Mac Apple Silicon, on exclut arm64 pour le simulateur :
#    l'app tourne alors dans un simulateur « Rosetta » (sinon : « Undefined symbol: _main »).
excl = '\t\t\t\t"EXCLUDED_ARCHS[sdk=iphonesimulator*]" = arm64;\n'
if "EXCLUDED_ARCHS[sdk=iphonesimulator*]" not in text:
    text = re.sub(r"(^\s*OTHER_LDFLAGS = .*;\n)", lambda mm: mm.group(1) + excl, text, flags=re.M)

proj.write_text(text, encoding="utf-8")

# 4. L'Info.plist du xcframework annonce arm64 pour le simulateur alors qu'il n'y en a pas :
#    on le corrige pour que Xcode ne tente pas un lien arm64.
plist = Path(sys.argv[1]).parent / (Path(sys.argv[1]).stem + ".xcframework") / "Info.plist"
if plist.exists():
    pl = plist.read_text(encoding="utf-8")
    pl = pl.replace("<string>ios-arm64_x86_64-simulator</string>\n\t\t\t<key>LibraryPath</key>\n\t\t\t<string>libgodot.a</string>\n\t\t\t<key>SupportedArchitectures</key>\n\t\t\t<array>\n\t\t\t\t<string>arm64</string>\n\t\t\t\t<string>x86_64</string>",
                    "<string>ios-arm64_x86_64-simulator</string>\n\t\t\t<key>LibraryPath</key>\n\t\t\t<string>libgodot.a</string>\n\t\t\t<key>SupportedArchitectures</key>\n\t\t\t<array>\n\t\t\t\t<string>x86_64</string>")
    plist.write_text(pl, encoding="utf-8")
print("Projet corrigé : MetalFX lié seulement sur iPhone, simulateur en x86_64 (Rosetta).")
