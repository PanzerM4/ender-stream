#!/bin/bash
set -e

CD_DIR="/radio"
cd "$CD_DIR"

# Переменные окружения (задайте YOUTUBE_KEY в панели управления Render)
STREAM_KEY="${YOUTUBE_KEY:-4ux7-0ay8-816w-cxrb-1j24}" 
FONT_PATH="/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"

# 1. Безопасный запуск веб-обманки для Render
pkill -f "http.server" || true
python3 -m http.server 10000 &

# 2. Создаем именованные каналы для бесконечного потока
rm -f stream_video stream_audio metadata.txt
mkfifo stream_video stream_audio
touch metadata.txt

# 3. ФОНОВЫЙ ЦИКЛ: Генерация аудио и текста без остановки
(
  while true; do
    find . -maxdepth 1 -name "*.mp3" | shuf > shuffle_list.txt
    while IFS= read -r track_path; do
      # Получаем метаданные
      artist=$(ffprobe -v error -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$track_path" 2>/dev/null || echo "")
      title=$(ffprobe -v error -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$track_path" 2>/dev/null || echo "")
      
      if [ -n "$artist" ] && [ -n "$title" ]; then
          display_name="$artist — $title"
      else
          display_name=$(basename "$track_path" .mp3 | sed 's/_/ /g')
      fi
      
      # Записываем название в файл (ffmpeg прочитает его налету)
      echo "$display_name" > metadata.txt
      echo "В эфире: $display_name"
      
      # Декодируем аудио в пайп
      ffmpeg -v error -re -i "$track_path" -f wav -y stream_audio
    done < shuffle_list.txt
  done
) &

# 4. ГЛАВНЫЙ ПРОЦЕСС FFMPEG: Непрерывная отправка на YouTube
# textfile=metadata.txt обновляет текст на экране автоматически при смене трека
ffmpeg -v error -loop 1 -re -i bg.jpg -f wav -i stream_audio \
  -vf "drawtext=fontfile=${FONT_PATH}:textfile=metadata.txt:reload=1:x=(w-tw)/2:y=h-100:fontsize=36:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=15" \
  -c:v libx264 -preset ultrafast -tune stillimage -crf 28 -b:v 2000k -maxrate 2000k -bufsize 4000k \
  -pix_fmt yuv420p -g 60 -c:a aac -b:a 192k -ar 44100 \
  -f flv "rtmp://://youtube.com"
