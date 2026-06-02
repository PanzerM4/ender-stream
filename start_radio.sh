#!/bin/bash
set -e

# Полное отключение интерактивного ввода на уровне самого ffmpeg
export FFMPEG_FORCE_TEXT_STATUS=1

CD_DIR="/radio"
cd "$CD_DIR"

# Корректная поочередная очистка старых процессов
pkill -9 -f ffmpeg || true
pkill -9 -f ffprobe || true
pkill -9 -f http.server || true

# Сброс старых файлов и пайпов
rm -f audio_pipe metadata.txt
mkfifo audio_pipe
touch metadata.txt

# Фоновая заглушка для Render
python3 -m http.server 10000 >/dev/null 2>&1 &

# ФОНОВЫЙ ПРОЦЕСС: Выдача звука в реальном времени (без обрывов на середине)
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
      
      ffmpeg -v error -nostdin -re -i "$track_path" -f lavfi -i anullsrc=r=44100:cl=stereo -filter_complex "[0:a][1:a]amix=inputs=2:duration=first,aresample=async=1[aout]" -map "[aout]" -f wav -ar 44100 -ac 2 -y audio_pipe </dev/null || true
    done < shuffle_list.txt
  done
) &

# ГЛАВНЫЙ ПРОЦЕСС: Стрим HD 720p со скоростью строго 1.0x (Вся команда в одну строку)
while true; do
  echo "Запуск стабильной HD-трансляции в реальном времени..."
  
  ffmpeg -v error -nostdin -y -re -loop 1 -r 1 -i bg.jpg -re -f wav -i audio_pipe -vf "scale=1280:720,drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf:textfile=metadata.txt:reload=1:x=(w-tw)/2:y=h-80:fontsize=28:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=12" -c:v libx264 -preset ultrafast -tune stillimage -crf 26 -b:v 1200k -maxrate 1200k -bufsize 2400k -pix_fmt yuv420p -g 2 -c:a aac -b:a 128k -ar 44100 -f flv "rtmp://://youtube.com${YOUTUBE_KEY:-4ux7-0ay8-816w-cxrb-1j24}" < /dev/null

  echo "Временная потеря сети. Переподключение через 3 секунды..."
  sleep 3
done


