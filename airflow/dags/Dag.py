import json
import os
import subprocess
import sys
from datetime import datetime, timedelta

import psycopg2
import psycopg2.extras
from airflow import DAG
from airflow.operators.empty import EmptyOperator
from airflow.operators.python import PythonOperator


DB_CONFIG = {
    "host": os.environ.get("APP_DB_HOST"),
    "port": os.environ.get("APP_DB_PORT", "5432"),
    "user": os.environ.get("APP_DB_USER"),
    "password": os.environ.get("APP_DB_PASSWORD"),
    "database": os.environ.get("APP_DB_NAME"),
}


default_args = {
    "owner": "Jhonny",
    "depends_on_past": False,
    "email_on_failure": False,
    "email_on_retry": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}


def normalize_spiders(spiders_to_run):
    if not spiders_to_run:
        return []

    if isinstance(spiders_to_run, list):
        return [str(spider).strip() for spider in spiders_to_run if str(spider).strip()]

    if isinstance(spiders_to_run, tuple):
        return [str(spider).strip() for spider in spiders_to_run if str(spider).strip()]

    if isinstance(spiders_to_run, str):
        value = spiders_to_run.strip()

        if value.startswith("{") and value.endswith("}"):
            value = value[1:-1]

        return [
            spider.strip().strip('"').strip("'")
            for spider in value.split(",")
            if spider.strip()
        ]

    return []


def normalize_field_mapping(field_mapping):
    if not field_mapping:
        return {}

    if isinstance(field_mapping, dict):
        return field_mapping

    if isinstance(field_mapping, str):
        try:
            return json.loads(field_mapping)
        except Exception:
            return {}

    return {}


def get_active_clients():
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

    cur.execute("""
        SELECT
            id,
            name,
            slug,
            store_prefix,
            is_active,
            source_type,
            source_path,
            source_url,
            file_format,
            field_mapping,
            spiders_to_run,
            match_name_threshold,
            match_color_threshold,
            match_maker_threshold
        FROM clients
        WHERE is_active = TRUE
        ORDER BY id
    """)

    clients = [dict(row) for row in cur.fetchall()]

    cur.close()
    conn.close()

    return clients


def ingest_client_products(client):
    sys.path.insert(0, "/opt/airflow/dags")

    from processors.data_ingestor import DataExtractor, DataLoader

    prefix = client.get("store_prefix") or client["slug"]
    products_table = f"{prefix}_products"

    source_type = client.get("source_type")
    source_path = client.get("source_path")
    source_url = client.get("source_url")
    file_format = client.get("file_format")
    field_mapping = normalize_field_mapping(client.get("field_mapping"))

    if source_type == "url" and source_url:
        source_path = source_url

    if not source_type or not source_path or not file_format:
        raise ValueError(
            f"Client {client['id']} has incomplete source config: "
            f"source_type={source_type}, source_path={source_path}, file_format={file_format}"
        )

    config = {
        "store_name": prefix,
        "source_type": source_type,
        "source_path": source_path,
        "file_format": file_format,
        "field_mapping": field_mapping,
    }

    print(f"[INGEST] Client={client['name']} prefix={prefix}")
    print(f"[INGEST] Source={source_type} path={source_path} format={file_format}")
    print(f"[INGEST] Target table={products_table}")

    extractor = DataExtractor(config=config)
    loader = DataLoader(table_name=products_table)
    loader.load(extractor.extract(), batch_size=500)

    print(f"[INGEST] Finished for client={client['name']}")


def run_spider_for_client(client, spider_name):
    prefix = client.get("store_prefix") or client["slug"]

    command = (
        "export PYTHONPATH=$PYTHONPATH:/opt/airflow/dags && "
        "cd /opt/airflow/dags/ecommerce_price_comparer && "
        f"scrapy crawl {spider_name} "
        f"-a target_table={prefix}_competitors "
        f"-a store_prefix={prefix}"
    )

    print(f"[SCRAPER] Client={client['name']} spider={spider_name}")
    print(f"[SCRAPER] Command={command}")

    result = subprocess.run(
        command,
        shell=True,
        text=True,
        capture_output=True,
    )

    print("[SCRAPER STDOUT]")
    print(result.stdout)

    print("[SCRAPER STDERR]")
    print(result.stderr)

    if result.returncode != 0:
        raise RuntimeError(
            f"Spider {spider_name} failed for client {client['name']} "
            f"with code {result.returncode}"
        )

    print(f"[SCRAPER] Finished spider={spider_name} client={client['name']}")


def run_matching_for_client(client):
    sys.path.insert(0, "/opt/airflow/dags")

    from processors.files_connector import MultiTenantReportGenerator

    prefix = client.get("store_prefix") or client["slug"]
    spiders = normalize_spiders(client.get("spiders_to_run"))

    if not spiders:
        print(f"[MATCH] Skipping client={client['name']} because spiders_to_run is empty")
        return

    config = {
        "client_table": f"{prefix}_products",
        "competitor_table": f"{prefix}_competitors",
        "target_table": f"{prefix}_matches",
        "competitor_stores": spiders,
    }

    name_threshold = client.get("match_name_threshold") or 90
    color_threshold = client.get("match_color_threshold") or 80
    maker_threshold = client.get("match_maker_threshold") or 80

    print(f"[MATCH] Client={client['name']} prefix={prefix}")
    print(f"[MATCH] Config={config}")
    print(
        f"[MATCH] Thresholds: name={name_threshold}, "
        f"color={color_threshold}, maker={maker_threshold}"
    )

    generator = MultiTenantReportGenerator(config=config)

    result = generator.generate_report(
        name_threshold=name_threshold,
        color_threshold=color_threshold,
        maker_threshold=maker_threshold,
    )

    if result is None:
        print(f"[MATCH] No report generated for client={client['name']}")
    else:
        print(f"[MATCH] Generated rows={len(result)} for client={client['name']}")


def save_pipeline_run(client_id, status, error_msg=None):
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        cur = conn.cursor()

        cur.execute("""
            INSERT INTO pipeline_runs (client_id, status, finished_at, error_msg)
            VALUES (%s, %s, NOW(), %s)
        """, (client_id, status, error_msg))

        conn.commit()
        cur.close()
        conn.close()

    except Exception as e:
        print(f"[PIPELINE_RUN_LOG] Could not save pipeline run: {e}")


def run_pipeline_for_client(client):
    client_id = client["id"]
    prefix = client.get("store_prefix") or client["slug"]
    spiders = normalize_spiders(client.get("spiders_to_run"))

    print("=" * 80)
    print(f"[CLIENT PIPELINE] START client_id={client_id} name={client['name']} prefix={prefix}")
    print(f"[CLIENT PIPELINE] spiders_to_run={spiders}")
    print("=" * 80)

    try:
        ingest_client_products(client)

        for spider_name in spiders:
            run_spider_for_client(client, spider_name)

        run_matching_for_client(client)

        save_pipeline_run(client_id, "success")

        print(f"[CLIENT PIPELINE] SUCCESS client_id={client_id}")

    except Exception as e:
        error_msg = str(e)
        save_pipeline_run(client_id, "failed", error_msg)
        print(f"[CLIENT PIPELINE] FAILED client_id={client_id}: {error_msg}")
        raise


def run_all_active_clients():
    clients = get_active_clients()

    print(f"[PIPELINE] Active clients count={len(clients)}")

    if not clients:
        print("[PIPELINE] No active clients. Nothing to do.")
        return

    for client in clients:
        run_pipeline_for_client(client)

    print("[PIPELINE] Finished all active clients.")


with DAG(
    dag_id="multi_client_pipeline",
    start_date=datetime(2026, 5, 1),
    schedule="0 * * * *",
    catchup=False,
    max_active_runs=1,
    default_args=default_args,
    tags=["production", "multi-client"],
) as dag:
    start = EmptyOperator(task_id="start")

    run_all = PythonOperator(
        task_id="run_all_active_clients",
        python_callable=run_all_active_clients,
    )

    end = EmptyOperator(task_id="end")

    start >> run_all >> end