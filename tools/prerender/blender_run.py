"""Lance une scène pré-rendue (fw_scene.py, ss_scene.py, mall_scene.py) dans Blender quand le
module « bpy » n'est pas installé dans Python :
  blender -b --factory-startup --python tools/prerender/blender_run.py -- <scene.py> <args…>
Les arguments après « -- » deviennent sys.argv de la scène. PRERENDER_PYPATH (facultatif) :
dossier site-packages à ajouter (Pillow, absent du Python de Blender ; même version de Python).
"""
import os
import runpy
import sys

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if not argv:
    raise SystemExit(__doc__)
extra = os.environ.get("PRERENDER_PYPATH", "")
if extra:
    sys.path.append(extra)
sys.path.insert(0, os.path.dirname(os.path.abspath(argv[0])))
sys.argv = argv
runpy.run_path(argv[0], run_name="__main__")
