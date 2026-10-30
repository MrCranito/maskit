# Environnement du pipeline de pré-rendu sur macOS. À sourcer avant un *_pipeline.sh :
#   source tools/prerender/mac_env.sh && tools/prerender/hc_pipeline.sh 2025 /tmp/hc2025
# Prérequis : Blender 5.2 (/Applications), `brew install flock coreutils`, Pillow pour le Python de
# Blender : <python3.13 de Blender> -m pip install --target ~/.cache/maskit/pylib Pillow
_here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export MASKIT_PYLIB="${MASKIT_PYLIB:-$HOME/.cache/maskit/pylib}"
export PATH="$_here/mac:/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"
mkdir -p "$HOME/.cache/maskit"
export GODOT_LOCK="${GODOT_LOCK:-$HOME/.cache/maskit/godot.lock}"
export BLENDER_LOCK="${BLENDER_LOCK:-$HOME/.cache/maskit/blender_render.lock}"
# Rendu Cycles sur le GPU Apple (lu par les *_scene.py ; CPU par défaut ailleurs)
export CYCLES_DEVICE="${CYCLES_DEVICE:-METAL}"
unset _here
