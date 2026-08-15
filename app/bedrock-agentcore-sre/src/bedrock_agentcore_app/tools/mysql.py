from __future__ import annotations

import json
import os

import boto3
import pymysql
import structlog
from strands import tool

logger = structlog.get_logger()

_secret_arn = os.environ.get("MYSQL_SECRET_ARN", "")
_region = os.environ.get("AWS_REGION", "ap-northeast-1")

_secret: dict[str, str] | None = None


def _get_secret() -> dict[str, str]:
    global _secret
    if _secret:
        return _secret

    client = boto3.client("secretsmanager", region_name=_region)
    resp = client.get_secret_value(SecretId=_secret_arn)
    _secret = json.loads(resp["SecretString"])
    logger.info("MySQL secret fetched from Secrets Manager")
    return _secret


def _connect() -> pymysql.Connection:
    s = _get_secret()
    return pymysql.connect(
        host=s["host"],
        port=int(s["port"]),
        user=s["username"],
        password=s["password"],
        database=s["dbname"],
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
