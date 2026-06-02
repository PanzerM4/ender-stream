#!/bin/bash
set -e

export FFMPEG_FORCE_TEXT_STATUS=1

CD_DIR="/radio"
cd "$CD_DIR"

pkill -9 -f "ffmpeg" || true
pkill -9 -f "ffprobe" || true
pkill -9 -f "http.server" || true
rm -f audio_pipe metadata.txt
mkfifo audio_pipe
touch metadata.txt

python3 -m http.server 10000 >/dev/null 2>&1 &

# ИСПРАВЛЕНО: Весь цикл обернут в скобки и направлен в пайп целиком ) > audio_pipe &
# Это не дает пайпу закрыться между треками!
(
  while true; do
    find . -maxdepth 1 -name "*.mp3" | shuf > shuffle_list.txt
    while IFS= read -r track_path; do
      artist=$(ffprobe -v error -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$track_path" 2>/dev/null </dev/null || echo "")
      title=$(ffprobe -v error -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$track_path" 2>/dev/null </dev/null || echo "")
      
      artist=$(echo "$artist" | tr -d '\r\n')
      title=$(echo "$title" | tr -d '\r\n')

      if [ -n "$artist" ] && [ -n "$title" ]; then
          display_name="$artist — $title"
      else
          display_name=$(basename "$track_path" .mp3 | sed 's/[_-]/ /g')
      fi
      
      echo "$display_name" > metadata.txt
      echo "NOW_PLAYING: $display_name"
      
      # ИСПРАВЛЕНО: Выводим в стандартный вывод pipe:1, который перехватывается общим пайпом
      ffmpeg -v error -nostdin -i "$track_path" -f wav -ar 44100 -ac 2 -y pipe:1 </dev/null || true
    done < shuffle_list.txt
  done
) > audio_pipe &

while true; do
  echo "Запуск HD-трансляции на YouTube..."
  
  # ИСПРАВЛЕНО: Убран лишний -re, изменен -r (FPS) на 15 для стабильности YouTube,
  # изменен размер GOP (-g 30), исправлен RTMP-URL.
  ffmpeg -v error -nostdin -y \
    -loop 1 -i bg.jpg \
    -re -f wav -i audio_pipe \
    -vf "scale=1280:720,fps=15,drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf:textfile=metadata.txt:reload=1:x=(w-tw)/2:y=h-80:fontsize=28:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=12" \
    -c:v libx264 -preset ultrafast -tune stillimage -crf 26 -b:v 1200k -maxrate 1200k -bufsize 2400k \
    -pix_fmt yuv420p -g 30 -c:a aac -b:a 128k -ar 44100 \
    -f flv "rtmp://://youtube.com{YOUTUBE_KEY:-4ux7-0ay8-816w-cxrb-1j24}" < /dev/null

  echo "Переподключение потока через 3 секунды..."
  sleep 3
done



