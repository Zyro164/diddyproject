#!/bin/bash
export DISPLAY=:1
export XDG_RUNTIME_DIR=/config/.XDG
exec /usr/local/bin/xwinwrap -g 1920x1080+0+0 -ni -s -st -sp -b -nf -un -fdt -- /config/.local/bin/castle-dimitrescu-run.sh WID
