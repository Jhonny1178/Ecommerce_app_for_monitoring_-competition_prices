import os
import sys
import psycopg2
import psycopg2.extras
from airflow import DAG
from airflow.operators.empty import EmptyOperator
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator
from datetime import datetime,timedelta
from processors.files_connector import MultiTenantReportGenerator
from processors.data_ingestor import DataExtractor, DataLoader
DB_CONFIG = {
    "host":     os.environ.get("APP_DB_HOST"),
    "user":     os.environ.get("APP_DB_USER"),
    "password": os.environ.get("APP_DB_PASSWORD"),
    "database": os.environ.get("APP_DB_NAME"),
}
default_args = {
    'owner': 'Jhonny',
    'depends_on_past': False,
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
}
def get_active_clients():
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        cur  = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cur.execute("SELECT * FROM clients WHERE is_active = TRUE")
        clients = [dict(r) for r in cur.fetchall()]
        cur.close()
        conn.close()
        return clients
    except Exception as e:
        print(f"Błąd łączenia z bazą podczas budowania DAGa: {e}")
        return []

def ingest_client_data(client: dict):
    """Uruchamia DataIngestor dla jednego klienta."""
    import sys
    sys.path.insert(0, "/opt/airflow/dags")

    from processors.data_ingestor import DataExtractor, DataLoader

    client_table = f"{client['slug']}_products"
    print(f"[INGEST] Start dla klienta: {client['name']} → tabela: {client_table}")

    config = {
        "store_name":    client["slug"],
        "source_type":   client["source_type"],
        "source_path":   client["source_path"],
        "file_format":   client["file_format"],
        "field_mapping": client["field_mapping"],  # już JSONB = dict
    }

    extractor = DataExtractor(config=config)
    loader    = DataLoader(table_name=client_table)
    loader.load(extractor.extract())
    print(f"[INGEST] Zakończono dla: {client['name']}")


def run_matching_for_client(client: dict):
    sys.path.insert(0, "/opt/airflow/dags")
    prefix = client.get("store_prefix") or client["slug"]
    config = {
        "client_table":      f"{client['slug']}_products",
        "competitor_table":  f"{prefix}_competitors",
        "target_table":      f"{prefix}_report",
        "competitor_stores": list(client["spiders_to_run"]),
    }

    print(f"[MATCH] Start matchingu dla: {client['name']}")
    generator = MultiTenantReportGenerator(config=config)
    generator.generate_report(
        name_threshold  = client["match_name_threshold"],
        color_threshold = client["match_color_threshold"],
        maker_threshold = client["match_maker_threshold"],
    )
    print(f"[MATCH] Zakończono dla: {client['name']}")

def update_run_status(client_id: int, status: str, error: str = None):
    """Aktualizuje status uruchomienia w tabeli pipeline_runs."""
    conn = psycopg2.connect(**DB_CONFIG)
    cur  = conn.cursor()
    cur.execute("""
        INSERT INTO pipeline_runs (client_id, status, finished_at, error_msg)
        VALUES (%s, %s, NOW(), %s)
    """, (client_id, status, error))
    conn.commit()
    cur.close()
    conn.close()

def build_client_tasks(dag, client: dict):
    slug = client["slug"]
    prefix = client.get("store_prefix") or slug

    # Task 1: załaduj dane klienta
    ingest_task = PythonOperator(
        task_id=f"{slug}__ingest",
        python_callable=ingest_client_data,
        op_args=[client],
        dag=dag,
    )

    # Tasks 2..N: jeden BashOperator na każdego spidera
    scrape_tasks = []
    for spider in client["spiders_to_run"]:
        task = BashOperator(
            task_id=f"{slug}__scrape_{spider}",
            bash_command=(
                "export PYTHONPATH=$PYTHONPATH:/opt/airflow/dags && "
                "cd /opt/airflow/dags/ecommerce_price_comparer && "
                f"scrapy crawl {spider} "
                f"-a target_table={prefix}_competitors "
                f"-a store_prefix={prefix}"
            ),
            dag=dag,
        )
        scrape_tasks.append(task)

    # Task N+1: matching
    match_task = PythonOperator(
        task_id=f"{slug}__matching",
        python_callable=run_matching_for_client,
        op_args=[client],
        dag=dag,
    )

    # Zależności: ingest → wszystkie scrapery równolegle → matching
    ingest_task >> scrape_tasks >> match_task

    return ingest_task, match_task  # zwracamy start i koniec grupy

with DAG(
    dag_id="multi_client_pipeline",
    start_date=datetime(2026, 5, 1),
    schedule="0 * * * *",   # co godzinę
    catchup=False,
    max_active_runs=1,
    default_args=default_args,
    tags=["production"],
) as dag:

    start = EmptyOperator(task_id="start")
    end   = EmptyOperator(task_id="end")

    clients = get_active_clients()  # wywołane przy parsowaniu DAG
    if not clients:
        # Brak aktywnych klientów — DAG nic nie robi
        start >> end
    else:
        for client in clients:
            ingest_start, match_end = build_client_tasks(dag, client)
            start >> ingest_start
            match_end >> end