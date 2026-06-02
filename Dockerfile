FROM ubuntu:22.04
RUN apt-get update && apt-get install -y ffmpeg findutils fonts-liberation python3 git
WORKDIR /radio
COPY . .
RUN chmod +x play.sh
EXPOSE 7860
CMD ["./play.sh"]
