# syntax=docker/dockerfile:1.7
FROM python:3.14-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y ca-certificates && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:0.7.22 /uv /uvx /usr/local/bin/

RUN --mount=type=secret,id=corp_ca,required=false \
    if [ -f /run/secrets/corp_ca ]; then \
        cp /run/secrets/corp_ca /usr/local/share/ca-certificates/corp-ca.crt && update-ca-certificates; \
    else \
        echo "No corporate CA secret provided"; \
    fi

COPY pyproject.toml uv.lock README.md ./
COPY src ./src

RUN UV_NATIVE_TLS=1 uv sync --frozen --no-dev

ENV PATH="/app/.venv/bin:$PATH"

EXPOSE 8000

CMD ["uvicorn", "kharon.main:app", "--host", "0.0.0.0", "--port", "8000"]
