#!/bin/bash
set -e

# Переходим в папку с радио
CD_DIR="/radio"
cd "$CD_DIR"

# 1. Запуск обязательной заглушки для Render (в фоне)
pkill -f "http.server" || true
python3 -m http.server 10000 &

# 2. ГЕНЕРАЦИЯ ПЛЕЙЛИСТА (Прямо перед запуском стрима)
# Создаем чистый список песен в формате, который понимает ffmpeg concat
echo "Генерируем плейлист..."
find . -maxdepth 1 -name "*.mp3" | shuf | sed "s|^\./|file '/radio/|; s|$|'|" > playlist.txt

# 3. ЕДИНЫЙ, ИЗОЛИРОВАННЫЙ ПРОЦЕСС FFMPEG
# Ключ -stream_loop -1 зациклит этот плейлист по кругу автоматически.
# Флаги </dev/null и -nostdin намертво заблокируют ошибку 'Parse error'.
# Разрешение 480p и 10 FPS поднимут скорость кодирования до нормы (>1.0x).

ffmpeg -v error -nostdin \
  -loop 1 -r 10 -i bg.jpg \
  -f concat -safe 0 -stream_loop -1 -i playlist.txt \
  -vf "scale=854:480,drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf:text='В эфире радио (LIVE)':x=(w-tw)/2:y=h-50:fontsize=24:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=10" \
  -c:v libx264 -preset ultrafast -tune stillimage -crf 32 -b:v 400k -maxrate 400k -bufsize 800k \
  -pix_fmt yuv420p -g 30 -c:a aac -b:a 128k -ar 44100 \
  -f flv "rtmp://youtube.com/live2/4ux7-0ay8-816w-cxrb-1j24" </dev/null
