#!/bin/sh
# Windows 11 style taskbar search pill (rendered by xfce4-genmon-plugin)
SP='&#160;&#160;&#160;&#160;&#160;&#160;&#160;&#160;&#160;&#160;&#160;&#160;&#160;&#160;&#160;&#160;&#160;&#160;&#160;&#160;&#160;&#160;'
printf '%s' "<img>$HOME/.local/share/icons/win11-search.png</img><txt>&#160;Search$SP</txt><tool>Search apps and files</tool><click>xfce4-popup-whiskermenu</click>"
