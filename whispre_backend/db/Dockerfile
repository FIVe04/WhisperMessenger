FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app

WORKDIR /app

COPY db/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY packages/whispre_common/whispre_common ./whispre_common
COPY alembic.ini .
COPY db/alembic ./db/alembic
COPY db/migrate.py ./db/migrate.py

CMD ["python", "db/migrate.py"]
