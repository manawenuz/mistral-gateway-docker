FROM python:3.12-slim

WORKDIR /app

# gateway.py is stdlib-only — no pip install needed
COPY gateway.py ./gateway.py

EXPOSE 8788

CMD ["python3", "gateway.py"]
