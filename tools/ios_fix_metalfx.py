#!/usr/bin/env python3
"""Corrige un projet Xcode exporté par Godot 4.4 pour qu'il compile aussi sur le simulateur iOS.

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

proj.write_text(text, encoding="utf-8")
print("MetalFX : lié uniquement pour les appareils iOS (simulateur corrigé).")
