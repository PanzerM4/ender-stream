#!/bin/bash
# playlist_feeder.sh – непрерывный звук без разрывов и с нормализацией частоты
set -euo pipefail

CD_DIR="/radio"
cd "$CD_DIR"

TITLE_FILE="current_title.txt"
DURATION_TARGET=$((4 * 3600))

get_title() {
  local file="$1"
  # Убираем переносы строк, чтобы не ломать drawtext
  artist=$(ffprobe -v error -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null | tr -d '\n\r' || true)
  title=$(ffprobe -v error -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null | tr -d '\n\r' || true)
  
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

# Сбор mp3 и их длительности
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
  # Генерация блока (перемешиваем)
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

  # Фоновый планировщик текста
  (
    for ((i=0; i<n; i++)); do
      title="${block_titles[$i]}"
      start="${block_starts[$i]}"
      end="${block_ends[$i]}"
      dur=$(echo "$end - $start" | bc -l)

      # Если трек короче 10 сек, просто очищаем текст и идем дальше
      if (( $(echo "$dur < 10" | bc -l) )); then
        echo "" > "$TITLE_FILE" || true
        continue
      fi

      show_time=$(echo "$BLOCK_START + $start + 5" | bc -l)
      hide_time=$(echo "$BLOCK_START + $end - 5" | bc -l)

      now=$(date +%s.%N)
      wait_show=$(echo "$show_time - $now" | bc -l)
      if (( $(echo "$wait_show > 0" | bc -l) )); then sleep "$wait_show"; fi
      echo "$title" > "$TITLE_FILE" || true

      now=$(date +%s.%N)
      wait_hide=$(echo "$hide_time - $now" | bc -l)
      if (( $(echo "$wait_hide > 0" | bc -l) )); then sleep "$wait_hide"; fi
      echo "" > "$TITLE_FILE" || true
    done
  ) &
  TEXT_PID=$!

  # Собираем массив входов и строку filter_complex для concat
  inputs=()
  filter=""
  for i in "${!block_files[@]}"; do
    abs_path="$(realpath "${block_files[$i]}")"
    inputs+=("-i" "$abs_path")
    filter+="[$i:a]"
  done
  filter+="concat=n=${n}:v=0:a=1[out]"

  echo "▶️ Запуск блока из $n треков..." >&2
  
  # Проигрываем весь блок ОДНИМ процессом ffmpeg с нормализацией до 44100Hz/2ch
  if ! ffmpeg -v error "${inputs[@]}" -filter_complex "$filter" -map "[out]" -f s16le -acodec pcm_s16le -ar 44100 -ac 2 - 2>"/tmp/ffmpeg_feeder_$$.log"; then
    echo "❌ Ошибка декодирования блока" >&2
    cat "/tmp/ffmpeg_feeder_$$.log" >&2
  fi
  rm -f "/tmp/ffmpeg_feeder_$$.log"

  kill $TEXT_PID 2>/dev/null || true
  wait $TEXT_PID 2>/dev/null || true
done
