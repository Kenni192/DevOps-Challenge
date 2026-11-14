# ---- base: dependencies only ----
FROM python:3.12-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app

# ---- test: used by CI (`docker build --target test`) ----
FROM base AS test
COPY requirements-dev.txt requirements.txt ./
RUN pip install --no-cache-dir -r requirements-dev.txt
COPY . .
RUN pytest -q

# ---- runtime: small, non-root image ----
FROM base AS runtime
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} PORT=8080
RUN useradd --system --uid 10001 appuser
USER 10001
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD python -c "import urllib.request as u; u.urlopen('http://127.0.0.1:8080/health', timeout=2)" || exit 1
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--access-logfile", "-", "main:app"]
