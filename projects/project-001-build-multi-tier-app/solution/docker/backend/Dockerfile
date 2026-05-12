# syntax=docker/dockerfile:1.7

FROM python:3.11.10-slim AS runtime


RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        tini \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --system --gid 1000 app \
    && useradd  --system --uid 1000 --gid app --create-home --home-dir /home/app app

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

COPY app.py .

RUN chown -R app:app /app

USER app

ENV APP_PORT=5000
EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/api/health').read()" \
        || exit 1

ENTRYPOINT ["/usr/bin/tini", "--"]

CMD ["python", "app.py"]

