"""
CloudWatch MCP Server Handler for AWS Lambda
Implements MCP Protocol 2025-03-26

This Lambda function provides CloudWatch observability tools via the MCP protocol,
enabling AI agents to query metrics, alarms, and logs for analysis and troubleshooting.
"""
import json
import logging
import os
from datetime import datetime, timedelta
from typing import Any

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS clients
region = os.environ.get("AWS_REGION", "ap-northeast-1")
cloudwatch = boto3.client("cloudwatch", region_name=region)
logs = boto3.client("logs", region_name=region)

# MCP Protocol version
MCP_PROTOCOL_VERSION = "2025-03-26"


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """
    CloudWatch MCP Server Lambda handler.

    Supports two invocation patterns:
    1. Gateway Target invocation (from AgentCore Gateway):
       - Event: Tool arguments directly (e.g., {"state_value": "ALARM"})
       - Context: client_context.custom contains tool metadata including bedrockAgentCoreToolName

    2. API Gateway / Direct invocation (JSON-RPC format):
       - Event: {"body": "{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",...}"}
    """
    try:
        # Log for debugging
        logger.info(f"Raw event: {json.dumps(event)[:2000]}")

        # Check if this is a Gateway Target invocation
        # Gateway Target passes tool arguments directly in event, and tool name in context
        tool_name_from_context = None
        if hasattr(context, 'client_context') and context.client_context:
            custom = getattr(context.client_context, 'custom', None)
            if custom and isinstance(custom, dict):
                full_tool_name = custom.get('bedrockAgentCoreToolName')
                if full_tool_name:
                    # Strip target name prefix: {target_name}___{tool_name}
                    delimiter = "___"
                    if delimiter in full_tool_name:
                        tool_name_from_context = full_tool_name.split(delimiter)[-1]
                    else:
                        tool_name_from_context = full_tool_name
                    logger.info(f"Gateway Target invocation: tool={tool_name_from_context}")

        # Gateway Target invocation: event contains tool arguments directly
        if tool_name_from_context:
            arguments = event  # Event IS the arguments
            logger.info(f"Executing tool '{tool_name_from_context}' with args: {json.dumps(arguments)[:500]}")
            result = execute_tool(tool_name_from_context, arguments)
            # Return result as plain JSON string (not wrapped in JSON-RPC)
            return json.dumps(result, default=str)

        # API Gateway / Direct invocation: JSON-RPC format
        body = event
        if "body" in event:
            body = event.get("body", "{}")
            if isinstance(body, str):
                body = json.loads(body)

        method = body.get("method")
        params = body.get("params", {})
        request_id = body.get("id", 1)

        logger.info(f"MCP Request: method={method}, params={json.dumps(params)[:500]}")

        if method == "initialize":
            return mcp_response(request_id, handle_initialize())

        elif method == "tools/list":
            return mcp_response(request_id, {"tools": get_tool_definitions()})

        elif method == "tools/call":
            tool_name = params.get("name")
            arguments = params.get("arguments", {})
            result = execute_tool(tool_name, arguments)
            return mcp_response(
                request_id, {"content": [{"type": "text", "text": json.dumps(result, default=str)}]}
            )

        else:
            return mcp_error(request_id, -32601, f"Method not found: {method}")

    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {e}")
        return mcp_error(1, -32700, f"Parse error: {e}")
    except Exception as e:
        logger.error(f"Unexpected error: {e}", exc_info=True)
        return mcp_error(1, -32000, str(e))


def handle_initialize() -> dict[str, Any]:
    """Handle MCP initialize request."""
    return {
        "protocolVersion": MCP_PROTOCOL_VERSION,
        "serverInfo": {"name": "cloudwatch-mcp-server", "version": "1.0.0"},
        "capabilities": {"tools": {}},
    }


def get_tool_definitions() -> list[dict[str, Any]]:
    """Return MCP tool definitions for CloudWatch operations."""
    return [
        {
            "name": "get_metric_data",
            "description": "Retrieve CloudWatch metric data for analysis. Returns time series data for specified metrics.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "namespace": {
                        "type": "string",
                        "description": "CloudWatch namespace (e.g., AWS/EC2, AWS/Lambda, AWS/RDS)",
                    },
                    "metric_name": {
                        "type": "string",
                        "description": "Name of the metric (e.g., CPUUtilization, Invocations, Duration)",
                    },
                    "dimensions": {
                        "type": "array",
                        "description": "Metric dimensions as array of {Name, Value} objects",
                        "items": {
                            "type": "object",
                            "properties": {
                                "Name": {"type": "string"},
                                "Value": {"type": "string"},
                            },
                        },
                    },
                    "start_time": {
                        "type": "string",
                        "description": "ISO8601 start time (default: 1 hour ago)",
                    },
                    "end_time": {
                        "type": "string",
                        "description": "ISO8601 end time (default: now)",
                    },
                    "period": {
                        "type": "integer",
                        "description": "Data point period in seconds (default: 300)",
                    },
                    "stat": {
                        "type": "string",
                        "description": "Statistic to retrieve: Average, Sum, Minimum, Maximum, SampleCount (default: Average)",
                    },
                },
                "required": ["namespace", "metric_name"],
            },
        },
        {
            "name": "analyze_metric",
            "description": "Analyze a CloudWatch metric for trends, anomalies, and statistics. Provides summary statistics and identifies patterns.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "namespace": {
                        "type": "string",
                        "description": "CloudWatch namespace",
                    },
                    "metric_name": {
                        "type": "string",
                        "description": "Name of the metric to analyze",
                    },
                    "dimensions": {
                        "type": "array",
                        "description": "Metric dimensions",
                        "items": {"type": "object"},
                    },
                    "hours": {
                        "type": "integer",
                        "description": "Number of hours to analyze (default: 24)",
                    },
                },
                "required": ["namespace", "metric_name"],
            },
        },
        {
            "name": "get_active_alarms",
            "description": "Get all active CloudWatch alarms in ALARM or INSUFFICIENT_DATA state. Useful for identifying current issues.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "state_value": {
                        "type": "string",
                        "enum": ["ALARM", "INSUFFICIENT_DATA", "OK"],
                        "description": "Filter by alarm state (default: ALARM)",
                    },
                    "alarm_name_prefix": {
                        "type": "string",
                        "description": "Filter alarms by name prefix",
                    },
                },
            },
        },
        {
            "name": "get_alarm_history",
            "description": "Get history of state changes for a specific alarm. Useful for understanding alarm patterns.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "alarm_name": {
                        "type": "string",
                        "description": "Name of the alarm to get history for",
                    },
                    "history_item_type": {
                        "type": "string",
                        "enum": ["ConfigurationUpdate", "StateUpdate", "Action"],
                        "description": "Type of history items to retrieve (default: StateUpdate)",
                    },
                    "max_records": {
                        "type": "integer",
                        "description": "Maximum number of history records (default: 50)",
                    },
                },
                "required": ["alarm_name"],
            },
        },
        {
            "name": "describe_log_groups",
            "description": "List CloudWatch log groups with optional filtering. Returns log group metadata.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "log_group_name_prefix": {
                        "type": "string",
                        "description": "Filter log groups by name prefix (e.g., /aws/lambda/)",
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Maximum number of log groups to return (default: 50)",
                    },
                },
            },
        },
        {
            "name": "analyze_log_group",
            "description": "Analyze a CloudWatch log group for error patterns and anomalies within a time window.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "log_group_name": {
                        "type": "string",
                        "description": "Name of the log group to analyze",
                    },
                    "hours": {
                        "type": "integer",
                        "description": "Number of hours to analyze (default: 1)",
                    },
                    "filter_pattern": {
                        "type": "string",
                        "description": "CloudWatch Logs filter pattern (e.g., ERROR, Exception)",
                    },
                },
                "required": ["log_group_name"],
            },
        },
        {
            "name": "execute_log_insights_query",
            "description": "Execute a CloudWatch Logs Insights query for advanced log analysis.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "log_group_name": {
                        "type": "string",
                        "description": "Name of the log group to query",
                    },
                    "query_string": {
                        "type": "string",
                        "description": "Logs Insights query string (e.g., 'fields @timestamp, @message | filter @message like /ERROR/')",
                    },
                    "start_time": {
                        "type": "string",
                        "description": "ISO8601 start time (default: 1 hour ago)",
                    },
                    "end_time": {
                        "type": "string",
                        "description": "ISO8601 end time (default: now)",
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Maximum number of results (default: 100)",
                    },
                },
                "required": ["log_group_name", "query_string"],
            },
        },
    ]


def execute_tool(tool_name: str, arguments: dict[str, Any]) -> Any:
    """Execute the specified tool with given arguments."""
    tools = {
        "get_metric_data": get_metric_data,
        "analyze_metric": analyze_metric,
        "get_active_alarms": get_active_alarms,
        "get_alarm_history": get_alarm_history,
        "describe_log_groups": describe_log_groups,
        "analyze_log_group": analyze_log_group,
        "execute_log_insights_query": execute_log_insights_query,
    }

    if tool_name not in tools:
        raise ValueError(f"Unknown tool: {tool_name}")

    return tools[tool_name](**arguments)


# =============================================================================
# Tool Implementations
# =============================================================================


def get_metric_data(
    namespace: str,
    metric_name: str,
    dimensions: list[dict] | None = None,
    start_time: str | None = None,
    end_time: str | None = None,
    period: int = 300,
    stat: str = "Average",
) -> dict[str, Any]:
    """Retrieve CloudWatch metric data."""
    end_dt = datetime.fromisoformat(end_time.replace("Z", "+00:00")) if end_time else datetime.utcnow()
    start_dt = (
        datetime.fromisoformat(start_time.replace("Z", "+00:00")) if start_time else end_dt - timedelta(hours=1)
    )

    metric_query = {
        "Id": "m1",
        "MetricStat": {
            "Metric": {
                "Namespace": namespace,
                "MetricName": metric_name,
                "Dimensions": [{"Name": d["Name"], "Value": d["Value"]} for d in (dimensions or [])],
            },
            "Period": period,
            "Stat": stat,
        },
    }

    response = cloudwatch.get_metric_data(
        MetricDataQueries=[metric_query],
        StartTime=start_dt,
        EndTime=end_dt,
    )

    result = response["MetricDataResults"][0]
    return {
        "namespace": namespace,
        "metric_name": metric_name,
        "stat": stat,
        "period_seconds": period,
        "data_points": len(result.get("Timestamps", [])),
        "timestamps": [t.isoformat() for t in result.get("Timestamps", [])],
        "values": result.get("Values", []),
        "unit": result.get("Label", ""),
    }


def analyze_metric(
    namespace: str,
    metric_name: str,
    dimensions: list[dict] | None = None,
    hours: int = 24,
) -> dict[str, Any]:
    """Analyze metric for trends and statistics."""
    end_dt = datetime.utcnow()
    start_dt = end_dt - timedelta(hours=hours)

    # Get data at 5-minute intervals
    period = 300
    response = cloudwatch.get_metric_data(
        MetricDataQueries=[
            {
                "Id": "m1",
                "MetricStat": {
                    "Metric": {
                        "Namespace": namespace,
                        "MetricName": metric_name,
                        "Dimensions": [{"Name": d["Name"], "Value": d["Value"]} for d in (dimensions or [])],
                    },
                    "Period": period,
                    "Stat": "Average",
                },
            }
        ],
        StartTime=start_dt,
        EndTime=end_dt,
    )

    values = response["MetricDataResults"][0].get("Values", [])

    if not values:
        return {
            "namespace": namespace,
            "metric_name": metric_name,
            "analysis_hours": hours,
            "message": "No data points found for the specified time range",
        }

    # Calculate statistics
    avg_val = sum(values) / len(values)
    min_val = min(values)
    max_val = max(values)
    variance = sum((x - avg_val) ** 2 for x in values) / len(values)
    std_dev = variance**0.5

    # Detect trend (simple linear regression)
    n = len(values)
    if n > 1:
        x_mean = (n - 1) / 2
        slope = sum((i - x_mean) * (v - avg_val) for i, v in enumerate(values)) / sum(
            (i - x_mean) ** 2 for i in range(n)
        )
        trend = "increasing" if slope > std_dev / n else "decreasing" if slope < -std_dev / n else "stable"
    else:
        trend = "insufficient_data"

    return {
        "namespace": namespace,
        "metric_name": metric_name,
        "analysis_hours": hours,
        "data_points": n,
        "statistics": {
            "average": round(avg_val, 4),
            "minimum": round(min_val, 4),
            "maximum": round(max_val, 4),
            "std_deviation": round(std_dev, 4),
        },
        "trend": trend,
        "latest_value": round(values[0], 4) if values else None,
    }


def get_active_alarms(
    state_value: str = "ALARM",
    alarm_name_prefix: str | None = None,
) -> dict[str, Any]:
    """Get active CloudWatch alarms."""
    params = {"StateValue": state_value}
    if alarm_name_prefix:
        params["AlarmNamePrefix"] = alarm_name_prefix

    logger.info(f"Calling describe_alarms with params: {params}")
    response = cloudwatch.describe_alarms(**params)
    logger.info(f"describe_alarms response: MetricAlarms count={len(response.get('MetricAlarms', []))}, CompositeAlarms count={len(response.get('CompositeAlarms', []))}")

    alarms = []
    for alarm in response.get("MetricAlarms", []):
        alarms.append(
            {
                "alarm_name": alarm["AlarmName"],
                "state": alarm["StateValue"],
                "state_reason": alarm.get("StateReason", ""),
                "state_updated": alarm.get("StateUpdatedTimestamp", "").isoformat()
                if alarm.get("StateUpdatedTimestamp")
                else None,
                "metric_name": alarm.get("MetricName", ""),
                "namespace": alarm.get("Namespace", ""),
                "threshold": alarm.get("Threshold"),
                "comparison_operator": alarm.get("ComparisonOperator", ""),
            }
        )

    return {
        "state_filter": state_value,
        "alarm_count": len(alarms),
        "alarms": alarms,
    }


def get_alarm_history(
    alarm_name: str,
    history_item_type: str = "StateUpdate",
    max_records: int = 50,
) -> dict[str, Any]:
    """Get alarm history."""
    response = cloudwatch.describe_alarm_history(
        AlarmName=alarm_name,
        HistoryItemType=history_item_type,
        MaxRecords=max_records,
    )

    history = []
    for item in response.get("AlarmHistoryItems", []):
        history.append(
            {
                "timestamp": item.get("Timestamp", "").isoformat() if item.get("Timestamp") else None,
                "type": item.get("HistoryItemType", ""),
                "summary": item.get("HistorySummary", ""),
            }
        )

    return {
        "alarm_name": alarm_name,
        "history_count": len(history),
        "history": history,
    }


def describe_log_groups(
    log_group_name_prefix: str | None = None,
    limit: int = 50,
) -> dict[str, Any]:
    """List CloudWatch log groups."""
    params = {"limit": limit}
    if log_group_name_prefix:
        params["logGroupNamePrefix"] = log_group_name_prefix

    response = logs.describe_log_groups(**params)

    groups = []
    for group in response.get("logGroups", []):
        groups.append(
            {
                "name": group["logGroupName"],
                "stored_bytes": group.get("storedBytes", 0),
                "retention_days": group.get("retentionInDays"),
                "creation_time": datetime.fromtimestamp(group.get("creationTime", 0) / 1000).isoformat()
                if group.get("creationTime")
                else None,
            }
        )

    return {
        "log_group_count": len(groups),
        "log_groups": groups,
    }


def analyze_log_group(
    log_group_name: str,
    hours: int = 1,
    filter_pattern: str | None = None,
) -> dict[str, Any]:
    """Analyze log group for patterns and errors."""
    end_time = int(datetime.utcnow().timestamp() * 1000)
    start_time = end_time - (hours * 3600 * 1000)

    # Use Logs Insights for analysis
    query = """
    fields @timestamp, @message
    | filter @message like /(?i)(error|exception|fail|timeout|crash)/
    | stats count() as error_count by bin(5m)
    | sort @timestamp desc
    | limit 100
    """

    if filter_pattern:
        query = f"""
        fields @timestamp, @message
        | filter @message like /{filter_pattern}/
        | stats count() as match_count by bin(5m)
        | sort @timestamp desc
        | limit 100
        """

    try:
        start_response = logs.start_query(
            logGroupName=log_group_name,
            startTime=start_time // 1000,
            endTime=end_time // 1000,
            queryString=query,
        )

        query_id = start_response["queryId"]

        # Wait for query to complete (with timeout)
        import time

        for _ in range(30):  # Max 30 seconds
            result_response = logs.get_query_results(queryId=query_id)
            if result_response["status"] == "Complete":
                break
            time.sleep(1)

        results = result_response.get("results", [])
        total_errors = sum(
            int(field["value"])
            for row in results
            for field in row
            if field["field"] in ("error_count", "match_count")
        )

        return {
            "log_group_name": log_group_name,
            "analysis_hours": hours,
            "filter_pattern": filter_pattern or "(error|exception|fail|timeout|crash)",
            "total_matches": total_errors,
            "time_buckets": len(results),
            "query_status": result_response["status"],
        }

    except Exception as e:
        return {
            "log_group_name": log_group_name,
            "error": str(e),
        }


def execute_log_insights_query(
    log_group_name: str,
    query_string: str,
    start_time: str | None = None,
    end_time: str | None = None,
    limit: int = 100,
) -> dict[str, Any]:
    """Execute Logs Insights query."""
    end_ts = int(
        datetime.fromisoformat(end_time.replace("Z", "+00:00")).timestamp()
        if end_time
        else datetime.utcnow().timestamp()
    )
    start_ts = int(
        datetime.fromisoformat(start_time.replace("Z", "+00:00")).timestamp()
        if start_time
        else end_ts - 3600
    )

    # Ensure query has a limit
    if "limit" not in query_string.lower():
        query_string = f"{query_string} | limit {limit}"

    start_response = logs.start_query(
        logGroupName=log_group_name,
        startTime=start_ts,
        endTime=end_ts,
        queryString=query_string,
    )

    query_id = start_response["queryId"]

    # Wait for completion
    import time

    for _ in range(30):
        result_response = logs.get_query_results(queryId=query_id)
        if result_response["status"] in ("Complete", "Failed", "Cancelled"):
            break
        time.sleep(1)

    # Format results
    formatted_results = []
    for row in result_response.get("results", []):
        formatted_row = {field["field"]: field["value"] for field in row}
        formatted_results.append(formatted_row)

    return {
        "log_group_name": log_group_name,
        "query": query_string,
        "status": result_response["status"],
        "result_count": len(formatted_results),
        "results": formatted_results[:limit],
        "statistics": result_response.get("statistics", {}),
    }


# =============================================================================
# MCP Response Helpers
# =============================================================================


def mcp_response(request_id: int, result: Any) -> dict[str, Any]:
    """Format MCP success response."""
    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(
            {
                "jsonrpc": "2.0",
                "id": request_id,
                "result": result,
            }
        ),
    }


def mcp_error(request_id: int, code: int, message: str) -> dict[str, Any]:
    """Format MCP error response."""
    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(
            {
                "jsonrpc": "2.0",
                "id": request_id,
                "error": {"code": code, "message": message},
            }
        ),
    }
