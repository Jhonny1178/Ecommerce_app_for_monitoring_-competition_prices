FROM apache/airflow:2.9.2-python3.9

USER root

RUN apt-get update && apt-get install -y \
    gcc \
    python3-dev \
    && apt-get clean

USER airflow

RUN pip install --no-cache-dir \
    rapidfuzz \
    pandas \
    sqlalchemy \
    psycopg2-binary \
    openpyxl \
    requests \
    python-dotenv \
    scrapy \
    itemadapter \
    scrapy-rotating-proxies \
    scrapeops-scrapy-proxy-sdk