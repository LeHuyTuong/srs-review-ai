FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt ./requirements.txt
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

COPY app ./app
# /diagram/drawio runs the vendored uc-review.mjs (Node stdlib only, Node >= 22).
COPY --from=node:22-bookworm-slim /usr/local/bin/node /usr/local/bin/node
COPY vendor ./vendor
# Migrations ship inside the image so a VPS that only `docker pull`s can run
# `alembic upgrade head` without the source tree.
COPY alembic.ini ./alembic.ini
COPY alembic ./alembic

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
