FROM ubuntu:22.04
RUN apt-get update && apt-get install -y ffmpeg findutils fonts-liberation python3 git
WORKDIR /radio
# Сервер сам скачивает вашу музыку и файлы настроек из репозитория
RUN git clone https://github.com .
RUN chmod +x play.sh
EXPOSE 7860
CMD ["./play.sh"]
