FROM ubuntu:22.04

# Устанавливаем ffmpeg, python3, bc (для вычислений с плавающей точкой) и шрифты
RUN apt-get update && apt-get install -y \
    ffmpeg \
    python3 \
    bc \
    fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

# Создаем рабочую директорию
WORKDIR /radio

# Копируем все файлы (музыку, картинку и ОБА скрипта)
COPY . .

# Делаем исполняемыми оба скрипта
RUN chmod +x start_radio.sh playlist_feeder.sh

# Если bg.jpg нет — создаём чёрный фон 1280x720 (по желанию)
RUN if [ ! -f bg.jpg ]; then \
      ffmpeg -y -f lavfi -i color=c=black:s=1280x720:r=1 -frames:v 1 bg.jpg; \
    fi

# Открываем порт для Render (если требуется)
EXPOSE 10000

# Запускаем основное радио
CMD ["./start_radio.sh"]
