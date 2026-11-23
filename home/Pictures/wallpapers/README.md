# VM desktop themes

Everything lives in `/config/Pictures/wallpapers/`. The current theme is **Anime · Dusk**.

## Wallpapers

| File | Look | Source |
|---|---|---|
| `takamura-katana.png` | **Active** — Takamura (*Sakamoto Days*) behind his katana, near-black B&W; icon gutter is pure black | Pinterest pin `1116329826378168364` (art: CrainArt) |
| `yuji-sukuna-red.png` | Yuji/Sukuna hooded figure, red duotone manga art, 1920x1080 | Pinterest pin `1141169993115751924` |
| `akira-red.png` | Akira-style red/black poster art, 1920x1080; icon gutter stays dark | Pinterest pin `1150317929848837959` (MinzuVisuals) |
| `anime-dusk-girl.png` | girl with balloons under a shooting star, deep blue dusk sky | wallhaven `jerwwy` (anime) |
| `anime-seaside-girl.png` | anime girl on a seawall at sunset, bright blue sky | wallhaven `k8rx7q` (anime) |
| `anime-night-office.png` | anime girl coding late, neon night-city window | wallhaven `6l7d6q` (anime) |
| `midnight-aurora.png` | procedural aurora/starfield made locally (`midnight-aurora.py`) | generated |
| `wallpaper-before.txt` | the stock Xubuntu wallpaper path (rollback) | — |

## Switch theme

Wallpaper:

```bash
export DISPLAY=:1.0
xfconf-query -c xfce4-desktop \
  -p /backdrop/screen0/monitorscreen/workspace0/last-image \
  -s /config/Pictures/wallpapers/anime-seaside-girl.png
```

Icon layout (2-column grid, top-left). Edit
`/config/.config/xfce4/desktop/icons.screen0.yaml` while `xfdesktop` is stopped:

```bash
export DISPLAY=:1.0
pkill -x xfdesktop; sleep 1
# ...edit icons.screen0.yaml...
setsid xfdesktop >/tmp/xfdesktop.log 2>&1 < /dev/null &
```

Original layout is backed up at `icons.screen0.yaml.bak` (single left column,
plus a stale `DeepAI CODE.desktop` entry that is now removed).

## Rollback

Previous wallpaper (before `takamura-katana.png`): `/config/Pictures/wallpapers/yuji-sukuna-red.png`.
Before that: `/config/Pictures/wallpapers/akira-red.png`, then `/config/Pictures/Wallpapers/uploaded.png`.

```bash
export DISPLAY=:1.0
xfconf-query -c xfce4-desktop \
  -p /backdrop/screen0/monitorscreen/workspace0/last-image \
  -s "$(cat /config/Pictures/wallpapers/wallpaper-before.txt)"
cp /config/Pictures/wallpapers/icons.screen0.yaml.bak \
   /config/.config/xfce4/desktop/icons.screen0.yaml
pkill -x xfdesktop; sleep 1
setsid xfdesktop >/tmp/xfdesktop.log 2>&1 < /dev/null &
```
