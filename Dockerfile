FROM python:3.12.1-slim-bookworm
RUN python3 -m pip install cram && \
    apt update && \
    apt install -y make && \
    apt install -y patch && \
    apt clean
