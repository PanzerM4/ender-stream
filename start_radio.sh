#!/bin/bash
set -e

export FFMPEG_FORCE_TEXT_STATUS=1
CD_DIR="/radio"
cd "$CD_DIR"

# Очистка старых процессов и файлов
pkill -9 -f "ffmpeg" || true
pkill -9 -f "ffprobe" || true
pkill -9 -f "http.server" || true
rm -f audio_pipe metadata.txt
mkfifo audio_pipe
touch metadata.txt

# Запуск фонового веб-сервера для Render
python3 -m http.server 10000 >/dev/null 2>&1 &

# ФОНОВЫЙ ПРОЦЕСС: Непрерывное декодирование аудио с нормализацией формата
(
  while true; do
    find . -maxdepth 1 -name "*.mp3" | shuf > shuffle_list.txt
    while IFS= read -r track_path; do
      # Извлекаем метаданные трека
      artist=$(ffprobe -v error -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$track_path" 2>/dev/null </dev/null || echo "")
      title=$(ffprobe -v error -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$track_path" 2>/dev/null </dev/null || echo "")
      
      if [ -n "$artist" ] && [ -n "$title" ]; then
          display_name="$artist — $title"
      else
          display_name=$(basename "$track_path" .mp3 | sed 's/_/ /g')
      fi
      
      # Записываем название трека в файл
      echo "$display_name" > metadata.txt
      echo "В эфире: $display_name"
      
      # Принудительно конвертируем любой MP3 в стандартный поток 44100Hz Стерео на лету
      ffmpeg -v error -nostdin -i "$track_path" -af "aresample=async=1" -f wav -ar 44100 -ac 2 -y audio_pipe </dev/null || true
    done < shuffle_list.txt
  done
) &

# ГЛАВНЫЙ ПРОЦЕСС: Постоянный стриминг на YouTube
while true; do
  echo "Запуск трансляции на YouTube..."
  
  # Читаем аудио из пайпа, а текст динамически обновляем из файла metadata.txt
  ffmpeg -v error -nostdin -y \
    -loop 1 -r 2 -i bg.jpg \
    -f wav -i audio_pipe \
    -vf "scale=640:360,drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf:textfile=metadata.txt:reload=1:x=(w-tw)/2:y=h-40:fontsize=18:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=8" \
    -c:v libx264 -preset ultrafast -tune stillimage -crf 35 -b:v 150k -maxrate 150k -bufsize 3000k \
    -pix_fmt yuv420p -g 4 -c:a aac -b:a 128k -ar 44100 \
    -f flv "rtmp://://youtube.com${YOUTUBE_KEY:-4ux7-0ay8-816w-cxrb-1j24}" < /dev/null

  echo "Стрим упал. Перезапуск через 3 секунды..."
  sleep 3
done
