FROM python:3.11-slim

RUN pip install --break-system-packages prometheus_client

COPY app.py /app.py

CMD ["python3", "/app.py"]
