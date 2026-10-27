#!/usr/bin/env bash
# One-time setup for macOS: checks for Homebrew, ffmpeg and Real-ESRGAN, installing whatever is missing.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HERE/bin"
ESRGAN_URL="https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-macos.zip"

ok()   { printf "  \033[32m✓\033[0m %s\n" "$1"; }
step() { printf "  \033[33m→\033[0m %s\n" "$1"; }

[[ "$(uname)" == "Darwin" ]] || { echo "This setup script currently supports macOS only." >&2; exit 1; }
echo "Checking dependencies..."

# Homebrew
if ! command -v brew >/dev/null; then
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [[ -x $b ]] && eval "$($b shellenv)"; done
fi
if command -v brew >/dev/null; then
  ok "Homebrew"
else
  step "installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [[ -x $b ]] && eval "$($b shellenv)"; done
fi

# ffmpeg (with libx265)
if command -v ffmpeg >/dev/null && ffmpeg -hide_banner -encoders 2>/dev/null | grep -q libx265; then
  ok "ffmpeg ($(ffmpeg -version | head -1 | cut -d' ' -f3))"
else
  step "installing ffmpeg"
  brew install ffmpeg
fi

# Real-ESRGAN
if [[ -x "$BIN/realesrgan-ncnn-vulkan" && -f "$BIN/models/realesrgan-x4plus.bin" ]]; then
  ok "Real-ESRGAN"
else
  step "downloading Real-ESRGAN"
  mkdir -p "$BIN"
  tmp="$(mktemp -d)"
  curl -fL --progress-bar -o "$tmp/r.zip" "$ESRGAN_URL"
  unzip -oq "$tmp/r.zip" -d "$tmp/x"
  cp "$tmp/x/realesrgan-ncnn-vulkan" "$BIN/"
  cp -R "$tmp/x/models" "$BIN/"
  rm -rf "$tmp"
  chmod +x "$BIN/realesrgan-ncnn-vulkan"
  xattr -dr com.apple.quarantine "$BIN" 2>/dev/null || true
fi

# Make sure the binary actually starts on this Mac
if "$BIN/realesrgan-ncnn-vulkan" -h 2>&1 | grep -qiE "bad cpu type|cannot execute|killed"; then
  echo "  ! Real-ESRGAN failed to start. On Apple Silicon try: softwareupdate --install-rosetta --agree-to-license" >&2
  exit 1
fi
ok "Real-ESRGAN runs on this Mac"

chmod +x "$HERE/upscale.sh"
echo "All set. Try: ./upscale.sh your_video.mp4"
