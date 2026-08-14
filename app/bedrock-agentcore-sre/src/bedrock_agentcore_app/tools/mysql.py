from __future__ import annotations

import json
import os

import boto3
import pymysql
import structlog
from strands import tool

logger = structlog.get_logger()

_mysql_host = os.environ.get("MYSQL_HOST", "")
_mysql_secret_arn = os.environ.get("MYSQL_SECRET_ARN", "")
_mysql_database = os.environ.get("MYSQL_DATABASE", "app")
_region = os.environ.get("AWS_REGION", "ap-northeast-1")

_credentials: dict[str, str] | None = None


def _get_credentials() -> dict[str, str]:
    global _credentials
    if _credentials:
        return _credentials

    client = boto3.client("secretsmanager", region_name=_region)
    resp = client.get_secret_value(SecretId=_mysql_secret_arn)
    _credentials = json.loads(resp["SecretString"])
    logger.info("MySQL credentials fetched from Secrets Manager")
    return _credentials


def _connect() -> pymysql.Connection:
    creds = _get_credentials()
    host = _mysql_host.split(":")[0]
    port = int(_mysql_host.split(":")[1]) if ":" in _mysql_host else 3306
    return pymysql.connect(
        host=host,
        port=port,
        user=creds["username"],
        password=creds["password"],
        database=_mysql_database,
        connect_timeout=10,
        read_timeout=30,
        cursorclass=pymysql.cursors.DictCursor,
    )


@tool
def mysql_execute_query(query: str) -> str:
    """Execute a read-only SQL query (SELECT / SHOW / DESCRIBE / EXPLAIN only). Returns results as JSON."""
    normalized = query.strip().upper()
    if not normalized.startswith(("SELECT", "SHOW", "DESCRIBE", "DESC", "EXPLAIN")):
        return json.dumps({"error": "Only SELECT / SHOW / DESCRIBE / EXPLAIN queries are allowed"})

    conn = _connect()
    try:
        with conn.cursor() as cursor:
            cursor.execute(query)
            rows = cursor.fetchall()
            return json.dumps(rows, default=str, ensure_ascii=False)
    finally:
        conn.close()


@tool
def mysql_show_tables() -> str:
    """List all tables in the database."""
    conn = _connect()
    try:
        with conn.cursor() as cursor:
            cursor.execute("SHOW TABLES")
            rows = cursor.fetchall()
            tables = [list(r.values())[0] for r in rows]
            return json.dumps(tables, ensure_ascii=False)
    finally:
        conn.close()


@tool
def mysql_describe_table(table_name: str) -> str:
    """Show column definitions for a table."""
    conn = _connect()
    try:
        with conn.cursor() as cursor:
            cursor.execute("DESCRIBE %s" % pymysql.converters.escape_string(table_name))
            rows = cursor.fetchall()
            return json.dumps(rows, default=str, ensure_ascii=False)
    finally:
        conn.close()


mysql_tools = [
    mysql_execute_query,
    mysql_show_tables,
    mysql_describe_table,
]
g