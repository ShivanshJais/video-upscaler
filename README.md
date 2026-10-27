# video-upscaler

AI upscaling from 1080p to 4K (3840×2160) on your Mac, using [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) and ffmpeg. It's free, runs locally and uses the Mac's GPU.

## Setup (macOS)

```bash
git clone https://github.com/ShivanshJais/video-upscaler.git
cd video-upscaler
./setup.sh
```

`setup.sh` checks for Homebrew, ffmpeg and Real-ESRGAN and installs any that are missing. You can run it again safely.

## Usage

```bash
./upscale.sh input.mp4                  # live action (best quality, slower)
./upscale.sh input.mp4 out.mp4 -m anime # animation/cartoons (~10x faster)
```

| Option | Default | Meaning |
|---|---|---|
| `-m real\|anime` | `real` | `real` = realesrgan-x4plus (4× then downscaled to 4K); `anime` = realesr-animevideov3 (2×) |
| `-q CRF` | `16` | x265 quality; lower = better/bigger |
| `-s SECS` | `4` | segment length processed at a time |
| `-t TILE` | `0` (auto) | GPU tile size; set e.g. `256` if you run out of memory |
| `-k` | off | keep the work directory |

Output: 4K HEVC (10-bit, `hvc1` tagged so it plays in QuickTime). The original frame rate is kept and the original audio is copied in unchanged.

## How it works

1. Splits the video losslessly at keyframes into short segments.
2. For each segment, extracts the frames, upscales them with Real-ESRGAN, encodes them to HEVC, then deletes the frames, so disk usage stays small.
3. Joins the segments and copies the original audio back in.

If it's interrupted, re-run the same command. Finished segments are skipped.

## Speed

AI upscaling is slow. On an M-series Mac the `real` model takes a few seconds per frame, so start with a short clip:

```bash
ffmpeg -i in.mp4 -t 10 -c copy test.mp4 && ./upscale.sh test.mp4
```
