#!/usr/bin/env bash
# AI video upscaler: 1080p -> 4K (3840x2160) using Real-ESRGAN + ffmpeg.
# Works in short segments so disk usage stays bounded, and is resumable:
# re-run the same command after an interruption and finished segments are skipped.
#
# Usage: ./upscale.sh input.mp4 [output.mp4] [options]
#   -m MODEL   real   = realesrgan-x4plus     (default; live action, best quality, slow)
#              anime  = realesr-animevideov3  (animation/cartoons, ~10x faster)
#   -q CRF     x265 quality, lower = better/bigger (default 16)
#   -s SECS    segment length in seconds (default 4)
#   -t TILE    GPU tile size, lower if you run out of memory (default 0 = auto)
#   -k         keep the work directory afterwards
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ESRGAN="$HERE/bin/realesrgan-ncnn-vulkan"

IN="${1:?usage: upscale.sh input.mp4 [output.mp4] [-m real|anime] [-q crf] [-s secs] [-t tile] [-k]}"; shift
OUT="${IN%.*}_4k.mp4"
if [[ $# -gt 0 && "$1" != -* ]]; then OUT="$1"; shift; fi

MODEL=real CRF=16 SEG=4 TILE=0 KEEP=0
while getopts "m:q:s:t:k" o; do
  case $o in
    m) MODEL=$OPTARG ;; q) CRF=$OPTARG ;; s) SEG=$OPTARG ;; t) TILE=$OPTARG ;; k) KEEP=1 ;;
    *) exit 1 ;;
  esac
done

case $MODEL in
  real)  NET=realesrgan-x4plus;    SCALE=4; FMT=jpg ;;  # 4x then downscale; jpg keeps 8K temp frames small
  anime) NET=realesr-animevideov3; SCALE=2; FMT=png ;;
  *) echo "unknown model: $MODEL" >&2; exit 1 ;;
esac

[[ -x "$ESRGAN" ]] || { echo "missing $ESRGAN" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg not found (brew install ffmpeg)" >&2; exit 1; }

FPS=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "$IN")
WORK="${OUT%.*}.work"
mkdir -p "$WORK/segs" "$WORK/done"
WORK="$(cd "$WORK" && pwd)"

# 1. Split losslessly at keyframes (stream copy, no quality loss)
if [[ ! -f "$WORK/.split" ]]; then
  echo ">> splitting into ~${SEG}s segments"
  ffmpeg -v error -i "$IN" -map 0:v:0 -c copy -f segment -segment_time "$SEG" \
    -reset_timestamps 1 "$WORK/segs/%05d.mkv"
  touch "$WORK/.split"
fi

SEGS=("$WORK"/segs/*.mkv)
N=${#SEGS[@]}
START=$(date +%s)

# 2. Upscale each segment: decode -> Real-ESRGAN -> encode, then delete the frames
for i in "${!SEGS[@]}"; do
  s="${SEGS[$i]}"; name=$(basename "$s" .mkv); done_f="$WORK/done/$name.mkv"
  [[ -f "$done_f" ]] && continue
  printf ">> segment %d/%d" $((i + 1)) "$N"

  rm -rf "$WORK/in" "$WORK/up"; mkdir -p "$WORK/in" "$WORK/up"
  ffmpeg -v error -i "$s" -fps_mode passthrough "$WORK/in/%06d.png"
  "$ESRGAN" -i "$WORK/in" -o "$WORK/up" -n "$NET" -s "$SCALE" -t "$TILE" -f "$FMT" >/dev/null 2>&1
  ffmpeg -v error -framerate "$FPS" -i "$WORK/up/%06d.$FMT" \
    -vf "scale=3840:2160:flags=lanczos:force_original_aspect_ratio=decrease,pad=3840:2160:(ow-iw)/2:(oh-ih)/2" \
    -c:v libx265 -preset medium -crf "$CRF" -pix_fmt yuv420p10le -x265-params log-level=error \
    "$done_f.tmp.mkv"
  mv "$done_f.tmp.mkv" "$done_f"

  el=$(( $(date +%s) - START )); left=$(( N - i - 1 ))
  printf "  (elapsed %dm, ~%dm left)\n" $((el / 60)) $((el * left / (i + 1) / 60))
done
rm -rf "$WORK/in" "$WORK/up"

# 3. Join segments and copy the original audio/subtitles back in
echo ">> joining"
: > "$WORK/list.txt"
for f in "$WORK"/done/*.mkv; do echo "file '$f'" >> "$WORK/list.txt"; done
ffmpeg -v error -y -f concat -safe 0 -i "$WORK/list.txt" -i "$IN" \
  -map 0:v -map 1:a? -c:v copy -c:a copy -tag:v hvc1 -movflags +faststart "$OUT"

[[ $KEEP == 1 ]] || rm -rf "$WORK"
echo ">> done: $OUT"
