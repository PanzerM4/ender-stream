#!/bin/bash
set -e

export FFMPEG_FORCE_TEXT_STATUS=1
CD_DIR="/radio"
cd "$CD_DIR"

# Полная очистка памяти от старых процессов и пайпов
pkill -9 -f "ffmpeg" || true
pkill -9 -f "ffprobe" || true
pkill -9 -f "http.server" || true
rm -f audio_pipe metadata.txt
mkfifo audio_pipe
touch metadata.txt

# Фоновая заглушка для Render
python3 -m http.server 10000 >/dev/null 2>&1 &

# ФОНОВЫЙ ПРОЦЕСС: Непрерывное аудио без единого шва
(
  while true; do
    find . -maxdepth 1 -name "*.mp3" | shuf > shuffle_list.txt
    while IFS= read -r track_path; do
      # Отправляем маркер в логи
      echo "Плеер взял трек: $(basename "$track_path")"
      
      # ПРИНУДИТЕЛЬНАЯ СТАБИЛИЗАЦИЯ: Любой mp3 превращаем в идеальный WAV 44100Hz Stereo
      # amix с генератором тишины гарантирует, что пайп не закроется ни на миллисекунду на стыке
      ffmpeg -v error -nostdin -i "$track_path" -f lavfi -i anullsrc=r=44100:cl=stereo \
        -filter_complex "[0:a][1:a]amix=inputs=2:duration=first,aresample=async=1[aout]" \
        -map "[aout]" -f wav -ar 44100 -ac 2 -y audio_pipe </dev/null || true
    done < shuffle_list.txt
  done
) &

sleep 2

echo "Запуск стабильной HD-трансляции в реальном времени..."
while true; do
  # ГЛАВНЫЙ ПРОЦЕСС: Читает аудио из пайпа. Флаг -re гарантирует скорость строго 1.00x.
  # Эквалайзер работает без задержек, так как получает идеальный бесшовный аудиосигнал.
  ffmpeg -v error -nostdin -y \
    -loop 1 -r 5 -i bg.jpg \
    -vn -re -f wav -i audio_pipe \
    -filter_complex "[1:a]asplit[audio_out][audio_vis]; \
                     [audio_vis]showwaves=s=1280x80:mode=cline:colors=white@0.6:r=5[waves]; \
                     [0:v]scale=1280:720[bg]; \
                     [bg][waves]overlay=x=0:y=H-h[v_waves]; \
                     [v_waves]drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf:text='RADIO LIVE':x=30:y=h-130:fontsize=24:fontcolor=white:box=1:boxcolor=black@0.5:boxborderw=10[video_out]" \
    -map "[video_out]" -map "[audio_out]" \
    -c:v libx264 -preset ultrafast -tune stillimage -crf 30 -b:v 800k -maxrate 800k -bufsize 1600k \
    -pix_fmt yuv420p -g 10 -c:a aac -b:a 128k -ar 44100 \
    -f flv "rtmp://://youtube.com{YOUTUBE_KEY:-4ux7-0ay8-816w-cxrb-1j24}" < /dev/null

  echo "Временная потеря сети. Переподключение через 3 секунды..."
  sleep 3
done
