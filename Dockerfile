# ==================================================
# RAG Q&A System - Production Dockerfile (Fast uv + Render Ready)
# ==================================================

# Build stage
FROM python:3.12-slim AS builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# [CHANGE 1] Copy ultra-fast uv package installer
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Copy requirements first for better caching
COPY requirements.txt .

# [CHANGE 1] Create virtual environment and install dependencies with uv
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN uv venv $VIRTUAL_ENV && \
    uv pip install --no-cache -r requirements.txt


# Production stage
FROM python:3.12-slim AS production

WORKDIR /app

# Install git (required by RAGAS/datasets library)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN groupadd -r appgroup && useradd -r -g appgroup appuser

# Copy virtual environment from builder
COPY --from=builder /opt/venv /opt/venv
ENV VIRTUAL_ENV=/opt/venv \
    PATH="/opt/venv/bin:$PATH"

# Copy application code and static assets
COPY app/ ./app/
# [CHANGE 2] Include static folder in case FastAPI mounts it
COPY static/ ./static/

# Set ownership to non-root user
RUN chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH=/app

# Expose port
EXPOSE 8000

# Health check (uses PORT if set, otherwise 8000)
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD python -c "import os, httpx; httpx.get(f'http://localhost:{os.getenv(\"PORT\", 8000)}/health').raise_for_status()" || exit 1

# [CHANGE 3] Run application on Render's $PORT or default 8000 locally
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]