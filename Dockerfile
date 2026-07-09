# syntax=docker/dockerfile:1

# ---- Build stage: resolve deps into an isolated venv -----------------------
FROM python:3.12-slim AS builder

WORKDIR /app

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

# ---- Runtime stage: minimal image, no build tooling -------------------------
FROM python:3.12-slim AS runtime

# Keep Python from writing .pyc files / buffering stdout, tiny perf/log wins.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

# Non-root user - never run the app as root inside the container.
RUN groupadd --gid 1000 app && useradd --uid 1000 --gid app --shell /bin/false app

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY app.py .

USER app

# Container-only port. Not bound to any host port - Kubernetes Service/Ingress
# handles all routing (see requirement: no static host port).
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/').status==200 else 1)"

# Gunicorn (production WSGI server) instead of the Flask dev server.
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--threads", "4", \
     "--timeout", "30", "--access-logfile", "-", "app:app"]
