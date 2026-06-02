#!/bin/bash
set -e

CD_DIR="/radio"
cd "$CD_DIR"

STREAM_KEY="${YOUTUBE_KEY:-4ux7-0ay8-816w-cxrb-1j24}" 
FONT_PATH="/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"

pkill -f "http.server" || true
python3 -m http.server 10000 &

rm -f stream_video stream_audio metadata.txt
mkfifo stream_audio
touch metadata.txt

# Фоновый цикл генерации аудио (добавлен -re, чтобы аудио шло с реальной скоростью)
(
  while true; do
    find . -maxdepth 1 -name "*.mp3" | shuf > shuffle_list.txt
    while IFS= read -r track_path; do
      artist=$(ffprobe -v error -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$track_path" 2>/dev/null || echo "")
      title=$(ffprobe -v error -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$track_path" 2>/dev/null || echo "")
      
      if [ -n "$artist" ] && [ -n "$title" ]; then
          display_name="$artist — $title"
      else
          display_name=$(basename "$track_path" .mp3 | sed 's/_/ /g')
      fi
      
      echo "$display_name" > metadata.txt
      echo "В эфире: $display_name"
      
      # ОТКЛЮЧАЕМ stdin И ВКЛЮЧАЕМ -re ДЛЯ ФОНОВОГО ПРОЦЕССА
      ffmpeg -v error -nostdin -re -i "$track_path" -f wav -y stream_audio
    done < shuffle_list.txt
  done
) &

# ГЛАВНЫЙ ПРОЦЕСС FFMPEG
# -nostdin убирает Parse error и предотвращает переключение песен
# -r 15 снижает нагрузку на CPU Render, чтобы скорость поднялась до 1.0x
ffmpeg -v error -nostdin -loop 1 -r 15 -i bg.jpg -f wav -i stream_audio \
  -vf "drawtext=fontfile=${FONT_PATH}:textfile=metadata.txt:reload=1:x=(w-tw)/2:y=h-100:fontsize=36:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=15" \
  -c:v libx264 -preset ultrafast -tune stillimage -crf 30 -b:v 1000k -maxrate 1000k -bufsize 2000k \
  -pix_fmt yuv420p -g 30 -c:a aac -b:a 192k -ar 44100 \
  -f flv "rtmp://://youtube.com"
