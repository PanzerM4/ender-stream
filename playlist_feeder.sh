#!/bin/bash
# playlist_feeder.sh – непрерывный звук с логированием и обработкой ошибок
set -euo pipefail

CD_DIR="/radio"
cd "$CD_DIR"

TITLE_FILE="current_title.txt"
DURATION_TARGET=$((4 * 3600))

get_title() {
  local file="$1"
  artist=$(ffprobe -v error -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || true)
  title=$(ffprobe -v error -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || true)
  if [ -n "$artist" ] && [ -n "$title" ]; then
    echo "${artist} - ${title}"
  elif [ -n "$title" ]; then
    echo "$title"
  elif [ -n "$artist" ]; then
    echo "$artist"
  else
    basename "$file" .mp3 | tr '_' ' '
  fi | sed "s/'//g"
}

# Сбор mp3
declare -A DURATIONS
FILES=()
while IFS= read -r -d '' f; do
  dur=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null || echo 0)
  if (( $(echo "$dur <= 0" | bc -l) )); then
    echo "⚠️ Пропущен $f (длительность $dur)" >&2
    continue
  fi
  DURATIONS["$f"]=$dur
  FILES+=("$f")
done < <(find . -maxdepth 1 -name "*.mp3" -print0)

if [ ${#FILES[@]} -eq 0 ]; then
  echo "❌ Нет валидных mp3-файлов" >&2
  exit 1
fi

echo "🎵 Загружено ${#FILES[@]} треков" >&2

while true; do
  # Генерация блока
  mapfile -t SHUFFLED < <(printf '%s\n' "${FILES[@]}" | shuf)

  total=0
  block_files=()
  block_titles=()
  block_starts=()
  block_ends=()

  for f in "${SHUFFLED[@]}"; do
    dur="${DURATIONS[$f]}"
    total_after=$(echo "$total + $dur" | bc -l)
    block_files+=("$f")
    block_titles+=("$(get_title "$f")")
    block_starts+=("$total")
    block_ends+=("$total_after")
    total=$total_after
    if (( $(echo "$total >= $DURATION_TARGET" | bc -l) )); then
      break
    fi
  done

  n=${#block_files[@]}
  echo "📦 Новый блок: $n треков, ~$(printf "%.0f" "$total") сек" >&2

  BLOCK_START=$(date +%s.%N)

  # Фоновый планировщик текста (с проверкой ошибок)
  (
    set -euo pipefail
    for ((i=0; i<n; i++)); do
      title="${block_titles[$i]}"
      start="${block_starts[$i]}"
      end="${block_ends[$i]}"

      show_time=$(echo "$BLOCK_START + $start + 5" | bc -l)
      hide_time=$(echo "$BLOCK_START + $end - 5" | bc -l)

      now=$(date +%s.%N)
      wait_show=$(echo "$show_time - $now" | bc -l)
      if (( $(echo "$wait_show > 0" | bc -l) )); then
        sleep "$wait_show"
      fi
      echo "$title" > "$TITLE_FILE" || echo "⚠️ Ошибка записи в $TITLE_FILE" >&2

      now=$(date +%s.%N)
      wait_hide=$(echo "$hide_time - $now" | bc -l)
      if (( $(echo "$wait_hide > 0" | bc -l) )); then
        sleep "$wait_hide"
      fi
      echo "" > "$TITLE_FILE" || true
    done
  ) &
  TEXT_PID=$!

  # Проигрываем треки с проверкой ошибок
  for f in "${block_files[@]}"; do
    title=$(get_title "$f")
    echo "▶️ Сейчас играет: $title" >&2

    # Декодируем mp3, ловим ошибки
    if ! ffmpeg -v error -i "$f" -f s16le -acodec pcm_s16le -ar 44100 -ac 2 - 2>"/tmp/ffmpeg_feeder_$$.log"; then
      echo "❌ Ошибка декодирования $f" >&2
      cat "/tmp/ffmpeg_feeder_$$.log" >&2
      # Продолжаем следующий трек, не падаем
    fi
    rm -f "/tmp/ffmpeg_feeder_$$.log"
  done

  kill $TEXT_PID 2>/dev/null || true
  wait $TEXT_PID 2>/dev/null || true
done
