from airflow import DAG
from airflow.providers.standard.operators.empty import EmptyOperator
from airflow.operators.empty import EmptyOperator
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator
from datetime import datetime,timedelta
default_args = {
    'owner': 'Jhonny',
    'depends_on_past': False,
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
}
# wpisujemy które spidery chcemy uruchomić
spiders_to_run = ['Calavado', 'jmbdesing','pod_pierzyna']
with DAG(
    dag_id='scrapers_runner',
    start_date=datetime(2026, 5, 1),
    schedule = '0 * * * *',
    catchup = False,
    max_active_runs = 1,
    default_args = default_args,

) as dag :
    start = EmptyOperator(task_id='start')
    end = EmptyOperator(task_id='end')
    for spider_name in spiders_to_run :
        scrape_task = BashOperator(
            task_id=f'task_{spider_name}',
            bash_command=f'export PYTHONPATH=/opt/airflow/dags:/opt/airflow/dags/ecommerce_price_comparer:$PYTHONPATH && cd /opt/airflow/dags/ecommerce_price_comparer/ && scrapy crawl {spider_name}',

        )
    start >> scrape_task >> end

