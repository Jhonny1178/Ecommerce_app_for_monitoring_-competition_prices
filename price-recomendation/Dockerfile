# 1. Używamy lekkiego, oficjalnego obrazu Pythona
FROM python:3.11-slim

# 2. Ustawiamy katalog roboczy wewnątrz kontenera
WORKDIR /app

# 3. Kopiujemy plik z wymaganiami i instalujemy je
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 4. Kopiujemy resztę Twojego kodu (main.py, algorytm.py)
COPY . .

# 5. Uruchamiamy serwer FastAPI na porcie 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]