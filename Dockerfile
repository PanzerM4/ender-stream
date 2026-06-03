FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    ffmpeg \
    python3 \
    bc \
    fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /radio

COPY . .

RUN chmod +x start_radio.sh playlist_feeder.sh

RUN if [ ! -f bg.jpg ]; then \
      ffmpeg -y -f lavfi -i color=c=black:s=1280x720:r=1 -frames:v 1 bg.jpg; \
    fi

EXPOSE 10000

CMD ["./start_radio.sh"]
