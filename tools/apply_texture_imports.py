#!/usr/bin/env python3
"""Réglages d'import des textures lourdes (taille de l'APK), appliqués aux fichiers .import.

Godot 4.7 n'a pas de préréglage d'import par dossier : ce script en tient lieu. Il réécrit les
paramètres des .import existants selon les règles ci-dessous ; lance-le après avoir ajouté des
assets (l'éditeur doit d'abord avoir créé leur .import), puis réimporte :

    python tools/apply_texture_imports.py          # applique (affiche les fichiers modifiés)
    python tools/apply_texture_imports.py --check  # n'écrit rien, code 1 si un fichier est hors règle
    godot --headless --path . --import

Règles (vérifiées aussi par tests/test_texture_imports.gd) :
1. Fond pré-rendu (assets/prerender/**) : tuiles t_*, intérieurs in_*, minimap → WebP avec perte
   (compress/mode=1), qualité LOSSY_QUALITY, sans mipmaps. Les sources sont déjà des WebP avec
   perte : le stockage sans perte (mode 0) ré-encodait ~8× plus gros sans rien gagner.
   Restent sans perte : o_*.png (ids d'occultation lus au texel près par le shader
   prerender_occluder) et footprint.png (masque d'emprise).
2. Textures « VRAM » (atlas d'ennemis, atlas de biome, sols, murs) → Basis Universal (UASTC,
   compress/mode=4, niveau UASTC_LEVEL) au lieu de VRAM non compressé à l'export (mode 2 :
   ASTC 4×4 brut, 8 bits/pixel, plus un second fichier BPTC pour PC). Basis est stocké compacté
   (~4× plus petit) et transcodé au chargement en ASTC/ETC2 (mobile) ou BC7 (PC) : la mémoire
   GPU reste celle d'une texture compressée (pas de RGBA8 comme le WebP).
   Les mipmaps existantes sont gardées (props / sols dessinés réduits avec
   TEXTURE_FILTER_LINEAR_WITH_MIPMAPS) ; les atlas d'ennemis (*_atlas.png sous
   assets/sprites/enemies) n'en ont jamais (zoom quasi fixe).
"""
from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOSSY_QUALITY = "0.9"
UASTC_LEVEL = "2"
VRAM_DIRS = ("assets/sprites/", "assets/textures/")


def prerender_lossless(name: str) -> bool:
	return name.startswith("o_") or name == "footprint.png"


def wanted(rel: str, params: dict[str, str]) -> dict[str, str]:
	"""Paramètres à imposer pour la source `rel` (chemin relatif, '/'), vide si aucune règle."""
	name = rel.rsplit("/", 1)[-1]
	if rel.startswith("assets/prerender/"):
		if prerender_lossless(name):
			return {"compress/mode": "0", "mipmaps/generate": "false"}
		return {"compress/mode": "1", "compress/lossy_quality": LOSSY_QUALITY, "mipmaps/generate": "false"}
	enemy_atlas = rel.startswith("assets/sprites/enemies/") and name.endswith("_atlas.png")
	if enemy_atlas:
		return {"compress/mode": "4", "compress/uastc_level": UASTC_LEVEL,
			"compress/rdo_quality_loss": "0.0", "mipmaps/generate": "false"}
	if rel.startswith(VRAM_DIRS) and params.get("compress/mode") in ("2", "4"):
		return {"compress/mode": "4", "compress/uastc_level": UASTC_LEVEL, "compress/rdo_quality_loss": "0.0"}
	return {}


def process(path: str, check: bool) -> bool:
	"""True si le .import est (ou était) hors règle."""
	text = open(path, encoding="utf-8").read()
	if 'importer="texture"' not in text or "[params]" not in text:
		return False
	rel = os.path.relpath(path[: -len(".import")], ROOT).replace(os.sep, "/")
	head, params_txt = text.split("[params]", 1)
	params = dict(re.findall(r"^([\w/]+)=(.*)$", params_txt, re.M))
	todo = {k: v for k, v in wanted(rel, params).items() if params.get(k) != v}
	if not todo:
		return False
	print(("hors règle : " if check else "réglé : ") + rel + "  " + ", ".join(f"{k}={v}" for k, v in todo.items()))
	if check:
		return True
	for k, v in todo.items():
		if k in params:
			params_txt = re.sub(r"^" + re.escape(k) + r"=.*$", f"{k}={v}", params_txt, count=1, flags=re.M)
		else:
			params_txt = params_txt.rstrip("\n") + f"\n{k}={v}\n"
	with open(path, "w", encoding="utf-8", newline="\n") as f:
		f.write(head + "[params]" + params_txt)
	return True


def main() -> int:
	check = "--check" in sys.argv
	n = 0
	for base in ("assets/prerender", "assets/sprites", "assets/textures"):
		for dp, _dn, fn in os.walk(os.path.join(ROOT, base)):
			for f in sorted(fn):
				if f.endswith(".import") and process(os.path.join(dp, f), check):
					n += 1
	print(f"{n} fichier(s) {'hors règle' if check else 'modifié(s)'}.")
	return 1 if check and n else 0


if __name__ == "__main__":
	sys.exit(main())
