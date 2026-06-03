#!/bin/bash
# playlist_feeder.sh – непрерывный звук + плавное обновление названий треков
# Запускать: ./playlist_feeder.sh > audio.fifo

CD_DIR="/radio"
cd "$CD_DIR"

TITLE_FILE="current_title.txt"
DURATION_TARGET=$((4 * 3600))  # 4 часа

# Функция получения названия (без изменений)
get_title() {
  local file="$1"
  artist=$(ffprobe -v error -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
  title=$(ffprobe -v error -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
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

# Собираем все mp3 с длительностями (дробными)
declare -A DURATIONS
FILES=()
while IFS= read -r -d '' f; do
  dur=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null || echo 0)
  if (( $(echo "$dur <= 0" | bc -l) )); then
    continue
  fi
  DURATIONS["$f"]=$dur
  FILES+=("$f")
done < <(find . -maxdepth 1 -name "*.mp3" -print0)

if [ ${#FILES[@]} -eq 0 ]; then
  echo "Нет mp3-файлов" >&2
  exit 1
fi

# Бесконечный цикл блоков
while true; do
  # --- Генерация блока ---
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
  echo "Новый блок: $n треков, длительность $(printf "%.0f" "$total") сек." >&2

  # Запоминаем абсолютное время старта этого блока
  BLOCK_START=$(date +%s.%N)

  # --- Запускаем фоновый планировщик обновления текста (появление через 5 сек после начала, исчезновение за 5 сек до конца) ---
  (
    for ((i=0; i<n; i++)); do
      title="${block_titles[$i]}"
      start="${block_starts[$i]}"
      end="${block_ends[$i]}"

      # Появляется через 5 секунд после начала трека
      show_time=$(echo "$BLOCK_START + $start + 5" | bc -l)
      # Исчезает за 5 секунд до конца трека
      hide_time=$(echo "$BLOCK_START + $end - 5" | bc -l)

      # Ждём до show_time (появление названия)
      now=$(date +%s.%N)
      wait_show=$(echo "$show_time - $now" | bc -l)
      if (( $(echo "$wait_show > 0" | bc -l) )); then
        sleep "$wait_show"
      fi
      echo "$title" > "$TITLE_FILE"

      # Ждём до hide_time (скрытие названия)
      now=$(date +%s.%N)
      wait_hide=$(echo "$hide_time - $now" | bc -l)
      if (( $(echo "$wait_hide > 0" | bc -l) )); then
        sleep "$wait_hide"
      fi
      echo "" > "$TITLE_FILE"
    done
  ) &
  TEXT_PID=$!

  # --- Основной поток: выдаём PCM треков с логированием в stderr ---
  for f in "${block_files[@]}"; do
    # Сообщение в логи Render
    echo "Сейчас играет: $(get_title "$f")" >&2

    # Декодируем mp3 и пишем PCM в stdout (в FIFO)
    ffmpeg -v error -i "$f" -f s16le -acodec pcm_s16le -ar 44100 -ac 2 - 2>/dev/null
  done

  # Блок закончился, убиваем фоновый планировщик (на случай, если остались несработанные события)
  kill $TEXT_PID 2>/dev/null
  wait $TEXT_PID 2>/dev/null

  # Сразу переходим к следующему блоку (без паузы)
done
