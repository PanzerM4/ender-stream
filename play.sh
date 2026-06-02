#!/bin/bash
cd /radio

# Запускаем обязательную веб-обманку для Render
python3 -m http.server 10000 &

while true; do
  echo "Перемешиваем список треков..."
  find . -maxdepth 1 -name "*.mp3" | shuf > shuffle_list.txt

  while IFS= read -r track_path; do
    artist=$(ffprobe -v error -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$track_path" 2>/dev/null)
    title=$(ffprobe -v error -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$track_path" 2>/dev/null)

    if [ -n "$artist" ] && [ -n "$title" ]; then
        display_name="$artist — $title"
    else
        display_name=$(basename "$track_path" .mp3 | sed 's/_/ /g')
    fi

    # Узнаем длительность трека для плавного затухания
    duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$track_path")
    duration_sec=${duration%.*}
    fade_out_start=$((duration_sec - 3))

    echo "В эфире: $display_name (Длительность: ${duration_sec} сек.)"

    # Используем прямой IP-адрес вместо домена — это полностью исключает ошибку Invalid argument
    ffmpeg -re -loop 1 -i bg.jpg -i "$track_path" \
      -filter_complex "[1:a]afade=t=in:ss=0:d=3,afade=t=out:st=$fade_out_start:d=3,asplit[a_out][a_eq]; \
                       [a_eq]showwaves=s=1280x200:colors=white@0.4:mode=line[v_eq]; \
                       [0:v][v_eq]overlay=x=(W-w)/2:y=(H-h)/2:shortest=1, \
                       drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf:text='$display_name':x=w-mod(t*100\,w+tw):y=h-60:fontsize=32:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=10[v_out]" \
      -map "[v_out]" -map "[a_out]" \
      -c:v libx264 -preset veryfast -b:v 2500k -maxrate 2500k -bufsize 5000k \
      -pix_fmt yuv420p -g 50 -c:a aac -b:a 128k -ar 44100 \
      -f flv "rtmp://207.244.75.12/live2/$STREAM_KEY" || true

    sleep 1
  done < shuffle_list.txt
done

