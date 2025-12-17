# capstone/airflow/dags/currency_dbt_dag.py
from datetime import datetime, timedelta
import os

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.models import Variable

# CONFIGURATION
DBT_PROJECT_DIR = Variable.get("DBT_PROJECT_DIR", "/opt/airflow/capstone_currency_etl")
DBT_VENV_ACTIVATE = Variable.get("DBT_VENV_ACTIVATE", "")  # optional, usually empty in our docker setup
DBT_TARGET = Variable.get("DBT_TARGET", "dev")
SUMMARY_WINDOW_DAYS = Variable.get("SUMMARY_WINDOW_DAYS", "30")

# OPTIONAL: external table details for refresh
EXT_DB_NAME = Variable.get("EXT_TABLE_NAME", "CAPSTONE_CURRENCY_DB")
EXT_SCHEMA    = Variable.get("EXT_DB_NAME", "CAPSTONE_CURRENCY_SCHEMA")
EXT_TABLE_NAME     = Variable.get("EXT_SCHEMA", "CAPSTONE_CURRENCY_RAW_TABLE")

default_args = {
    "owner": "airflow",
    "depends_on_past": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}

with DAG(
    dag_id="capstone_currency_etl",
    start_date=datetime(2025, 1, 1),
    schedule="0 2 * * *",  # daily at 02:00
    catchup=False,
    max_active_runs=1,
    default_args=default_args,
    tags=["dbt", "currency"],
) as dag:

    # optional: dbt debug
    dbt_debug = BashOperator(
        task_id="dbt_debug",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && "
            f"dbt debug --profiles-dir . --project-dir . --target {DBT_TARGET} || true"
        ),
        env=os.environ,
    )

    # install deps
    dbt_deps = BashOperator(
        task_id="dbt_deps",
        bash_command=f"cd {DBT_PROJECT_DIR} && dbt deps --profiles-dir . --project-dir .",
        env=os.environ,
    )

    # NEW TASK: refresh external table using dbt run-operation
    dbt_refresh_external_table = BashOperator(
        task_id="dbt_refresh_external_table",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && "
            f"dbt run-operation refresh_external_table "
            f"--args '{{\"database\": \"{EXT_DB_NAME}\", "
            f"\"schema\": \"{EXT_SCHEMA}\", "
            f"\"table\": \"{EXT_TABLE_NAME}\", "
            f"\"complete\": false}}' "
            f"--profiles-dir . --project-dir . --target {DBT_TARGET}"
        ),
        env=os.environ,
    )

    # staging models
    dbt_run_staging = BashOperator(
        task_id="dbt_run_staging",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && "
            f"dbt run --profiles-dir . --project-dir . --target {DBT_TARGET} --select stg_currency+ "
            f"--vars '{{summary_window_days: {SUMMARY_WINDOW_DAYS}}}'"
        ),
        env=os.environ,
    )

    # marts
    dbt_run_marts = BashOperator(
        task_id="dbt_run_marts",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && "
            f"dbt run --profiles-dir . --project-dir . --target {DBT_TARGET} "
            f"--select currency_trend currency_summary "
            f"--vars '{{summary_window_days: {SUMMARY_WINDOW_DAYS}}}'"
        ),
        env=os.environ,
    )

    # tests
    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && "
            f"dbt test --profiles-dir . --project-dir . --target {DBT_TARGET} "
            f"--select stg_currency currency_trend currency_summary"
        ),
        env=os.environ,
    )

    # docs (optional)
    dbt_docs = BashOperator(
        task_id="dbt_docs_generate",
        bash_command=f"cd {DBT_PROJECT_DIR} && dbt docs generate --profiles-dir . --project-dir .",
        env=os.environ,
    )

    # ORDER OF EXECUTION
    dbt_debug >> dbt_deps >> dbt_refresh_external_table >> dbt_run_staging >> dbt_run_marts >> dbt_test >> dbt_docs
