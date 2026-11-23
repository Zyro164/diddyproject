#!/bin/bash
WID="$1"
exec mpv --wid="$WID" --loop-file=inf --no-audio --no-osc --no-osd-bar --panscan=1.0 /config/Videos/castle-dimitrescu.mp4
