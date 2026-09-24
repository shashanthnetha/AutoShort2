# Multi-stage build for smaller final image
FROM python:3.11-slim AS builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy and install Python dependencies
COPY requirements.txt requirements-billing.txt ./
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --upgrade pip
RUN pip install --no-cache-dir -r requirements.txt

# Cloud (paid mode) deps: installed always so one image serves both modes
RUN pip install --no-cache-dir -r requirements-billing.txt

# GPU build (--build-arg GPU=1): user-space CUDA libs only
ARG GPU=0
RUN if [ "$GPU" = "1" ]; then \
      pip install --no-cache-dir \
        "nvidia-cublas-cu12<13" "nvidia-cudnn-cu12>=9,<10" \
        onnx-asr onnxruntime-gpu; \
    fi

# Final stage
FROM python:3.11-slim

WORKDIR /app

# Install FFmpeg, OpenCV deps, Node.js + npm + git
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    curl \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    nodejs \
    npm \
    git \
    fontconfig \
    fonts-liberation \
    fonts-noto-color-emoji \
    && rm -rf /var/lib/apt/lists/*

# Deno JS runtime
COPY --from=denoland/deno:bin /deno /usr/local/bin/deno

# Helper token provider
RUN git clone --depth 1 https://github.com/Brainicism/bgutil-ytdlp-pot-provider /opt/bgutil-provider \
    && cd /opt/bgutil-provider/server \
    && npm install --no-audit --no-fund \
    && npx tsc \
    && npm cache clean --force

ENV BGUTIL_SCRIPT_PATH=/opt/bgutil-provider/server/build/generate_once.js

# Copy virtual env from builder
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
ENV PYTHONUNBUFFERED=1

# GPU runtime wiring
ENV LD_LIBRARY_PATH=/opt/venv/lib/python3.11/site-packages/nvidia/cublas/lib:/opt/venv/lib/python3.11/site-packages/nvidia/cudnn/lib:/opt/venv/lib/python3.11/site-packages/nvidia/cuda_runtime/lib:/opt/venv/lib/python3.11/site-packages/nvidia/cu13/lib
ENV NVIDIA_DRIVER_CAPABILITIES=compute,video,utility

# Latest yt-dlp plus helper plugin
RUN pip install --upgrade --pre --no-cache-dir "yt-dlp[default]" bgutil-ytdlp-pot-provider

# Copy application code
COPY . .

# Register bundled fonts
RUN mkdir -p /usr/local/share/fonts/openshorts \
    && cp fonts/*.ttf /usr/local/share/fonts/openshorts/ \
    && cp fonts/openshorts-fontmap.conf /etc/fonts/conf.d/60-openshorts.conf \
    && fc-cache -f

# Create non-root user
RUN groupadd -r appuser && useradd -r -g appuser -d /app -s /sbin/nologin appuser

# Create application/cache directories
RUN mkdir -p /app/uploads \
    /app/output \
    /app/.cache/huggingface \
    /tmp/Ultralytics

# Fix permissions for application/cache directories
RUN chown -R appuser:appuser /app /tmp/Ultralytics

# Create YOLO model directory while still running as root
RUN mkdir -p /opt/models \
    && chown -R appuser:appuser /opt/models

# Switch to non-root user
USER appuser

# Pre-download YOLO model outside /app
# This prevents the docker-compose bind mount from hiding the model.
RUN python -c "from ultralytics import YOLO; YOLO('/opt/models/yolov8n.pt')"

# Expose FastAPI port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=5s --timeout=3s --start-period=30s --retries=2 \
  CMD curl -sf http://127.0.0.1:8000/health/ready > /dev/null || exit 1

# Run FastAPI
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips", "*", "--timeout-graceful-shutdown", "15"]
