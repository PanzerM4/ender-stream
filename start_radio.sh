#!/bin/bash
set -e

# Полное отключение интерактивного ввода на уровне самого ffmpeg
export FFMPEG_FORCE_TEXT_STATUS=1

CD_DIR="/radio"
cd "$CD_DIR"

# Убиваем вообще все старые процессы, которые могли выжить на Render
pkill -9 -f "ffmpeg" || true
pkill -9 -f "ffprobe" || true
pkill -9 -f "http.server" || true
pkill -9 -f "bash" || true

# Запуск веб-обманки для Render в абсолютную пустоту
python3 -m http.server 10000 >/dev/null 2>&1 &

# Создаем плейлист в один проход без фоновых циклов
echo "Генерируем плейлист..."
find . -maxdepth 1 -name "*.mp3" | shuf | sed "s|^\./|file '/radio/|; s|$|'|" > playlist.txt

# Запуск стрима с полной изоляцией ввода и выводом логов в stdout
exec ffmpeg -v error -nostdin -y \
  -loop 1 -r 10 -i bg.jpg \
  -f concat -safe 0 -stream_loop -1 -i playlist.txt \
  -vf "scale=854:480,drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf:text='Radio Live':x=(w-tw)/2:y=h-50:fontsize=24:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=10" \
  -c:v libx264 -preset ultrafast -tune stillimage -crf 32 -b:v 400k -maxrate 400k -bufsize 800k \
  -pix_fmt yuv420p -g 30 -c:a aac -b:a 128k -ar 44100 \
  -f flv "rtmp://a.rtmp.youtube.com/live2/${YOUTUBE_KEY:-4ux7-0ay8-816w-cxrb-1j24}" < /dev/null
