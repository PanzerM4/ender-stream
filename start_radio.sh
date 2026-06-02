#!/bin/bash
set -e

export FFMPEG_FORCE_TEXT_STATUS=1
CD_DIR="/radio"
cd "$CD_DIR"

# Полная очистка старых зависших процессов
pkill -9 -f "ffmpeg" || true
pkill -9 -f "ffprobe" || true
pkill -9 -f "http.server" || true
rm -f playlist.txt metadata.txt

# Легкая веб-заглушка для Render
python3 -m http.server 10000 >/dev/null 2>&1 &

echo "Этап 1: Сбор и анализ медиатеки..."
find . -maxdepth 1 -name "*.mp3" | shuf > raw_list.txt

# Очищаем файлы списков
> playlist.txt
> metadata.txt

echo "Этап 2: Расчет таймингов и генерация скрипта..."
# Автоматически создаем бесшовную склейку аудио и текста
while IFS= read -r track_path; do
  # Читаем метаданные
  artist=$(ffprobe -v error -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$track_path" 2>/dev/null </dev/null || echo "")
  title=$(ffprobe -v error -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$track_path" 2>/dev/null </dev/null || echo "")
  artist=$(echo "$artist" | tr -d '\r\n')
  title=$(echo "$title" | tr -d '\r\n')

  if [ -n "$artist" ] && [ -n "$title" ]; then
      display_name="$artist — $title"
  else
      display_name=$(basename "$track_path" .mp3 | sed 's/[_-]/ /g')
  fi

  # Добавляем трек в плейлист для ffmpeg
  echo "file '$CD_DIR/$(basename "$track_path")'" >> playlist.txt
  echo "NOW_PLAYING: $display_name"
done < raw_list.txt

rm -f raw_list.txt

echo "Этап 3: Запуск трансляции..."
# Запускаем ОДИН ОПТИМИЗИРОВАННЫЙ процесс ffmpeg.
# stream_loop -1 зацикливает плейлист по кругу.
# text='Радио онлайн' выводит красивую стабильную плашку, которая не вешает слабый CPU.
while true; do
  ffmpeg -v error -nostdin -y \
    -loop 1 -r 2 -i bg.jpg \
    -f concat -safe 0 -stream_loop -1 -i playlist.txt \
    -vf "scale=640:360,drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf:text='RADIO LIVE':x=(w-tw)/2:y=h-40:fontsize=20:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=8" \
    -c:v libx264 -preset ultrafast -tune stillimage -crf 35 -b:v 120k -maxrate 120k -bufsize 2000k \
    -pix_fmt yuv420p -g 4 -c:a aac -b:a 128k -ar 44100 -ac 2 \
    -f flv "rtmp://://youtube.com${YOUTUBE_KEY:-4ux7-0ay8-816w-cxrb-1j24}" < /dev/null

  echo "Потеря соединения. Рестарт потока через 3 секунды..."
  sleep 3
done
