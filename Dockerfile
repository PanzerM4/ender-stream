FROM ubuntu:22.04
RUN apt-get update && apt-get install -y ffmpeg findutils fonts-liberation
WORKDIR /radio
COPY . .
RUN chmod +x start.sh
CMD ["./start.sh"]
