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

# Запуск фоновой веб-заглушки для Render
python3 -m http.server 10000 >/dev/null 2>&1 &

# ФОНОВЫЙ ПРОЦЕСС: Чтение треков и жесткое вытаскивание названий
(
  while true; do
    find . -maxdepth 1 -name "*.mp3" | shuf > shuffle_list.txt
    while IFS= read -r track_path; do
      
      # 1. Пытаемся прочитать теги через ffprobe
      artist=$(ffprobe -v error -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$track_path" 2>/dev/null </dev/null || echo "")
      title=$(ffprobe -v error -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$track_path" 2>/dev/null </dev/null || echo "")
      
      # Очищаем переменные от скрытых символов возврата каретки (\r)
      artist=$(echo "$artist" | tr -d '\r\n')
      title=$(echo "$title" | tr -d '\r\n')

      # 2. ЖЕЛЕЗНАЯ ПРОВЕРКА: если теги есть — пишем их, если нет — берем имя файла
      if [ -n "$artist" ] && [ -n "$title" ]; then
          display_name="$artist — $title"
      else
          # Вырезаем путь и .mp3, заменяя минусы и подчеркивания на пробелы
          raw_name=$(basename "$track_path" .mp3)
          display_name=$(echo "$raw_name" | sed 's/[_-]/ /g')
      fi
      
      # Записываем в файл и дублируем в консоль Render для проверки
      echo "NOW_PLAYING: $display_name"
      echo "$display_name" > metadata.txt
      
      # Перекодируем трек в пайп
      ffmpeg -v error -nostdin -i "$track_path" -af "aresample=async=1" -f wav -ar 44100 -ac 2 -y audio_pipe </dev/null || true
    done < shuffle_list.txt
  done
) &

# ГЛАВНЫЙ ПРОЦЕСС: Стрим на YouTube
while true; do
  echo "Запуск трансляции на YouTube..."
  
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

