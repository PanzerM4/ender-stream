#!/bin/bash
set -e

CD_DIR="/radio"
cd "$CD_DIR"

STREAM_KEY="${YOUTUBE_KEY:-4ux7-0ay8-816w-cxrb-1j24}" 
FONT_PATH="/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"

pkill -f "http.server" || true
python3 -m http.server 10000 &

rm -f stream_audio metadata.txt
mkfifo stream_audio
touch metadata.txt

# Фоновый цикл генерации аудио (Жесткая изоляция ввода через </dev/null)
(
  while true; do
    find . -maxdepth 1 -name "*.mp3" | shuf > shuffle_list.txt
    while IFS= read -r track_path; do
      
      # Добавили </dev/null к ffprobe
      artist=$(ffprobe -v error -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$track_path" 2>/dev/null </dev/null || echo "")
      title=$(ffprobe -v error -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$track_path" 2>/dev/null </dev/null || echo "")
      
      if [ -n "$artist" ] && [ -n "$title" ]; then
          display_name="$artist — $title"
      else
          display_name=$(basename "$track_path" .mp3 | sed 's/_/ /g')
      fi
      
      echo "$display_name" > metadata.txt
      echo "В эфире: $display_name"
      
      # ИЗОЛЯЦИЯ: -nostdin И </dev/null гарантируют, что ffmpeg не тронет список песен
      ffmpeg -v error -nostdin -re -i "$track_path" -f wav -y stream_audio </dev/null
    done < shuffle_list.txt
  done
) &

# ГЛАВНЫЙ ПРОЦЕСС FFMPEG (Оптимизирован под слабый CPU Render)
# scale=854:480 переводит видео в 480p (для статичной картинки больше не нужно)
# -r 5 снижает частоту кадров до 5 в секунду. Это поднимет speed до >1.0x
ffmpeg -v error -nostdin -loop 1 -r 5 -i bg.jpg -f wav -i stream_audio \
  -vf "scale=854:480,drawtext=fontfile=${FONT_PATH}:textfile=metadata.txt:reload=1:x=(w-tw)/2:y=h-50:fontsize=24:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=10" \
  -c:v libx264 -preset ultrafast -tune stillimage -crf 32 -b:v 400k -maxrate 400k -bufsize 800k \
  -pix_fmt yuv420p -g 15 -c:a aac -b:a 128k -ar 44100 \
  -f flv "rtmp://://youtube.com" </dev/null
