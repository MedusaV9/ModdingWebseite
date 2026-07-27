#!/usr/bin/env bash
# Builds the 30 s trailer music bed + SFX (docs/plans_v3/trailer/sound_design.md,
# storyboard variant: drop at 15.0 s / frame 900, hard stinger silence 14.85-15.0 s).
set -euo pipefail

SND=/home/ubuntu/project-eclipse/ProjectEclipse/src/main/resources/assets/eclipse/sounds
OUT="$(cd "$(dirname "$0")/.." && pwd)/public/audio"
TMP=/tmp/trailer_audio
mkdir -p "$OUT" "$TMP"

# 1) 30 s bed: day_final arc (B shifted so the drop impact lands at 15.0 s)
#    + eclipse_totality sub tail; hard mute 14.85-14.995 s for the stinger black.
ffmpeg -y -loglevel error \
  -i "$SND/music/day_final.ogg" -i "$SND/music/day_final.ogg" -i "$SND/music/eclipse_totality.ogg" \
  -filter_complex "\
[0:a]atrim=0:6.2,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.5[a];\
[1:a]atrim=20.6:45.25,asetpts=PTS-STARTPTS[b];\
[a][b]acrossfade=d=0.8:c1=tri:c2=tri[ab];\
[ab]volume=enable='between(t,14.85,14.995)':volume=0,afade=t=out:st=25.96:d=0.05[abx];\
[2:a]atrim=128.2:134.2,asetpts=PTS-STARTPTS,lowpass=f=120,volume=9dB,\
afade=t=in:st=0:d=0.08,afade=t=out:st=2.2:d=1.05,adelay=26000|26000[tail];\
[abx][tail]amix=inputs=2:duration=longest:dropout_transition=0:normalize=0[mix];\
[mix]apad=whole_dur=30,atrim=0:30,asetpts=PTS-STARTPTS[raw]" \
  -map "[raw]" -ar 48000 -ac 2 -c:a pcm_s16le "$TMP/mix_raw.wav"

# 2) loudnorm pass 1 (measure)
ffmpeg -hide_banner -nostats -i "$TMP/mix_raw.wav" \
  -af loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json -f null - 2>&1 \
  | tail -n 14 > "$TMP/loudnorm.json"
I=$(grep  -oP '"input_i"\s*:\s*"\K[-0-9.]+'      "$TMP/loudnorm.json")
TP=$(grep -oP '"input_tp"\s*:\s*"\K[-0-9.]+'     "$TMP/loudnorm.json")
LRA=$(grep -oP '"input_lra"\s*:\s*"\K[-0-9.]+'   "$TMP/loudnorm.json")
TH=$(grep -oP '"input_thresh"\s*:\s*"\K[-0-9.]+' "$TMP/loudnorm.json")
OFF=$(grep -oP '"target_offset"\s*:\s*"\K[-0-9.]+' "$TMP/loudnorm.json")

# 3) loudnorm pass 2 (linear) -> Remotion master
ffmpeg -y -loglevel error -i "$TMP/mix_raw.wav" \
  -af "loudnorm=I=-14:TP=-1.5:LRA=11:measured_I=$I:measured_TP=$TP:\
measured_LRA=$LRA:measured_thresh=$TH:offset=$OFF:linear=true" \
  -ar 48000 -ac 2 -c:a pcm_s16le "$OUT/trailer_music.wav"

# 4) SFX (48 kHz stereo WAV)
for spec in \
  "boss/ferryman_bell:sfx_bell" \
  "boss/herald_telegraph:sfx_impact" \
  "event/border_glitch:sfx_glitch" \
  "event/emerge:sfx_riser" \
  "ui/heart_shatter:sfx_shatter" \
  "ui/unlock_sting:sfx_unlock" \
  "ambient/gazer_whisper:sfx_whisper" ; do
  ffmpeg -y -loglevel error -i "$SND/${spec%%:*}.ogg" -ar 48000 -ac 2 -c:a pcm_s16le "$OUT/${spec##*:}.wav"
done

# 5) endcard sub boom
ffmpeg -y -loglevel error -i "$SND/event/submerge.ogg" \
  -af "lowpass=f=90,volume=10dB,alimiter=limit=0.84:level=false" \
  -ar 48000 -ac 2 -c:a pcm_s16le "$OUT/sfx_sub_boom.wav"

echo "--- verification ---"
ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT/trailer_music.wav"
ffmpeg -hide_banner -nostats -i "$OUT/trailer_music.wav" -af ebur128=peak=true -f null - 2>&1 | tail -6
