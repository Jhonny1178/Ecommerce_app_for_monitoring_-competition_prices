# 1. Używamy lekkiego, oficjalnego obrazu Pythona
FROM python:3.11-slim

# 2. Ustawiamy katalog roboczy wewnątrz kontenera
WORKDIR /app

# 3. Kopiujemy najpierw listę bibliotek (dla optymalizacji cache Dockera)
COPY requirements.txt .

# 4. Instalujemy biblioteki (w tym FastAPI, Uvicorn, Groq)
RUN pip install --no-cache-dir -r requirements.txt

# 5. Kopiujemy Twój kod (main.py, algorytm.py) do kontenera
COPY . .

# 6. Mówimy Dockerowi, że aplikacja będzie działać na porcie 8000
EXPOSE 8000

# 7. Odpalamy serwer
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]