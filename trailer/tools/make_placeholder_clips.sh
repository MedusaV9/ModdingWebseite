#!/usr/bin/env bash
# Erzeugt 11 Platzhalter-Clips (1920x1080 @ 60 fps, 20 s, H.264) nach public/clips/.
# Jeder Clip zeigt Szenen-Label + laufenden QUELL-Framezaehler (%{n}) + eine
# wandernde Box -> damit lassen sich trimBefore/playbackRate im Render ablesen.
# Echte Captures ueberschreiben diese Dateien einfach (gleiche Dateinamen).
set -euo pipefail

OUT="$(cd "$(dirname "$0")/.." && pwd)/public/clips"
FONT=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf
[ -f "$FONT" ] || FONT=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf
DUR=${DUR:-20}
mkdir -p "$OUT"

# name:label:c0:c1:accent
SPECS=(
  "v01_eclipse_island:V01 ECLIPSE ISLAND:0x140b2e:0x05030a:0x8B5CF6"
  "v02_ghost_ship:V02 GHOST SHIP:0x0a1626:0x03060d:0x22F5EE"
  "v03_sky_rift:V03 SKY RIFT:0x2a0b3a:0x0a0311:0xA78BFA"
  "v04_altar_deposit:V04 ALTAR DEPOSIT:0x3a2a08:0x120c02:0xE8B44A"
  "v05_wand_fight:V05 WAND FIGHT:0x3a1204:0x120501:0xFF7A33"
  "v06_herald_arrival:V06 HERALD ARRIVAL:0x1e0b3a:0x080312:0x8B5CF6"
  "v07_village_storm:V07 VILLAGE STORM:0x101a24:0x04070a:0x6FA8DC"
  "v08_gravity_orbitals:V08 GRAVITY ORBITALS:0x081f1c:0x030a09:0x22F5EE"
  "v09_ferryman_boss:V09 FERRYMAN BOSS:0x24062a:0x0b020d:0xC4B5FD"
  "v10_end_helix:V10 END HELIX:0x2e1040:0x0d0516:0xA78BFA"
  "v11_blackhole:V11 BLACKHOLE:0x0b0614:0x000000:0xFFD98A"
)

for spec in "${SPECS[@]}"; do
  IFS=':' read -r name label c0 c1 accent <<<"$spec"
  echo "[clip] $name"
  ffmpeg -y -v error -stats \
    -f lavfi -i "gradients=s=1920x1080:c0=${c0}:c1=${c1}:x0=0:y0=0:x1=1920:y1=1080:d=${DUR}:r=60,format=yuv420p" \
    -t "$DUR" \
    -vf "drawbox=x='mod(t*260\\,2040)-120':y='540+320*sin(t*1.7)':w=140:h=140:color=${accent}@0.85:t=fill,\
drawbox=x='1800-mod(t*180\\,1920)':y='300+180*sin(t*2.6+1)':w=70:h=70:color=${accent}@0.5:t=fill,\
drawtext=fontfile=${FONT}:text='${label}':fontcolor=0xEDE4FF:fontsize=96:x=(w-tw)/2:y=(h-th)/2-60:box=1:boxcolor=0x000000@0.35:boxborderw=24,\
drawtext=fontfile=${FONT}:text='PLACEHOLDER':fontcolor=${accent}:fontsize=54:x=(w-tw)/2:y=(h-th)/2+70,\
drawtext=fontfile=${FONT}:text='SRC f\\=%{n}':fontcolor=0xFFFFFF:fontsize=64:x=(w-tw)/2:y=(h-th)/2+210:box=1:boxcolor=0x000000@0.55:boxborderw=18" \
    -c:v libx264 -preset veryfast -crf 24 -maxrate 8M -bufsize 16M \
    -pix_fmt yuv420p -r 60 -an -movflags +faststart \
    "$OUT/${name}.mp4"
done

echo "--- fertig ---"
ls -la "$OUT"
