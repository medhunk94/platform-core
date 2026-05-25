FROM python:3.12-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY main.py .

# Add non-root user
RUN groupadd -g 1001 appuser && \
    useradd -r -u 1001 -g appuser appuser && \
    chown -R appuser:appuser /app

USER 1001

CMD ["python", "main.py"]
