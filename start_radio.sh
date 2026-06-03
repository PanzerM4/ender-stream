#!/bin/bash
set -euo pipefail

CD_DIR="/radio"
cd "$CD_DIR"

# Проверка ключа YouTube
if [ -z "${YT_KEY:-}" ]; then
  echo "❌ Переменная окружения YT_KEY не задана!"
  exit 1
fi

# Остановка старых процессов ffmpeg
pkill -9 -f "ffmpeg" || true

# --- НАЧАЛО: Запуск минимального HTTP-сервера для пинга ---
PORT=${PORT:-10000}

# Проверяем, занят ли порт (опционально, но полезно)
if lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
  echo "⚠️ Порт $PORT занят. Пытаемся остановить связанные процессы..."
  lsof -ti:$PORT | xargs kill -9 2>/dev/null || true
  sleep 2
fi

# Создаем простой скрипт для HTTP-сервера
cat << 'EOF' > /tmp/simple_ping_server.py
import http.server
import socketserver
import os
from http import HTTPStatus

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(HTTPStatus.OK)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        self.wfile.write(b'OK\n')

    # Обработка других методов (POST, HEAD и т.д.) также возвращает 200 OK
    def do_HEAD(self):
        self.send_response(HTTPStatus.OK)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()

    def do_POST(self):
        self.do_GET() # Для пинга POST можно обрабатывать как GET

    def log_message(self, format, *args):
        # Отключаем логирование запросов для чистоты stdout
        pass

if __name__ == "__main__":
    port = int(os.environ.get('PORT', 10000))
    with socketserver.TCPServer(("", port), Handler) as httpd:
        print(f"Ping server running on port {port}")
        httpd.serve_forever()
EOF

# Функция для завершения процессов
cleanup() {
    echo "🧹 Завершение процессов..."
    # Убиваем HTTP-сервер по PID
    if [[ -n "${HTTP_PID:-}" ]]; then
        kill $HTTP_PID 2>/dev/null || true
        # Дополнительная проверка и убийство по имени (на всякий случай)
        pkill -9 -f "simple_ping_server.py" 2>/dev/null || true
    else
        # Если PID неизвестен, пробуем убить по имени
        pkill -9 -f "simple_ping_server.py" 2>/dev/null || true
    fi
    # Убиваем фидер
    if [[ -n "${FEEDER_PID:-}" ]]; then
        kill $FEEDER_PID 2>/dev/null || true
    fi
    # Удаляем файлы
    rm -f audio.fifo current_title.txt /tmp/simple_ping_server.py
}
# Устанавливаем trap для разных сигналов завершения
trap cleanup EXIT INT TERM

# Проверка mp3
if ! ls *.mp3 >/dev/null 2>&1; then
  echo "Нет mp3-файлов в /radio"
  exit 1
fi

# Запускаем сервер в фоне
python3 /tmp/simple_ping_server.py &
HTTP_PID=$!
echo "mPid HTTP-сервера (для пинга): $HTTP_PID"

# FIFO и файл текста
rm -f audio.fifo
mkfifo audio.fifo
echo "" > current_title.txt

echo "=== Запуск НЕПРЕРЫВНОГО радио ==="

# Запуск фидера
./playlist_feeder.sh > audio.fifo 2>"/tmp/feeder_$$.log" &
FEEDER_PID=$!

sleep 2
if ! kill -0 $FEEDER_PID 2>/dev/null; then
  echo "❌ Фидер не запустился, смотрите /tmp/feeder_$$.log"
  exit 1
fi

# FFmpeg: Максимизация качества с минимальным запасом по трафику
# Обратите внимание на правильное экранирование строк и разбиение на несколько строк
ffmpeg -v warning -nostdin -y \
  -re -f image2 -loop 1 -framerate 1 -i bg.jpg \
  -f s16le -ar 44100 -ac 2 -i audio.fifo \
  -filter_complex \
    "[0:v]scale=1280:720,
     drawtext=textfile=current_title.txt:reload=1:expansion=none:
             x=30:y=h-80:fontsize=32:fontcolor=white:
             box=1:boxcolor=black@0.5:boxborderw=10:font='DejaVu Sans',
     format=yuv420p[video_out]" \
  -map "[video_out]" -map 1:a \
  -c:v libx264 -preset ultrafast -tune stillimage -b:v 300k -maxrate 330k -bufsize 660k \
  -pix_fmt yuv420p -g 2 \
  -c:a aac -b:a 64k -ar 44100 \
  -f flv "rtmp://a.rtmp.youtube.com/live2/${YT_KEY}" 2>"/tmp/ffmpeg_main_$$.log"

echo "❌ FFmpeg остановлен (код $?), логи в /tmp/ffmpeg_main_$$.log" >&2
# kill $FEEDER_PID 2>/dev/null || true # Уже делается в trap cleanup
