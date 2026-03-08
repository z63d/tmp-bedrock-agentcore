/**
 * Tool definitions for New Relic MCP
 *
 * These are the known tools provided by New Relic's Remote MCP Server.
 * This list is used for tools/list responses when called directly.
 *
 * Note: The actual tool execution is proxied to New Relic's MCP server,
 * so tools not listed here will still work if they exist on the remote server.
 *
 * Source: https://docs.newrelic.com/docs/agentic-ai/mcp/tool-reference/
 */

import { McpToolDefinition } from "../types/index.js";

/**
 * Get the list of known New Relic MCP tools
 *
 * These definitions are based on New Relic's official MCP documentation.
 * The actual tools are executed on New Relic's remote MCP server.
 */
export function getToolDefinitions(): McpToolDefinition[] {
  return [
    // Entity and Account Management
    {
      name: "get_entity",
      description: "Fetch New Relic entities by GUID or search by name pattern",
      inputSchema: {
        type: "object",
        properties: {
          guid: {
            type: "string",
            description: "Entity GUID to fetch directly",
          },
          name: {
            type: "string",
            description: "Entity name pattern for search",
          },
          accountId: {
            type: "integer",
            description: "New Relic account ID",
          },
        },
      },
    },
    {
      name: "list_entity_types",
      description: "List the complete catalog of New Relic entity types with domain/type definitions",
      inputSchema: {
        type: "object",
        properties: {},
      },
    },
    {
      name: "list_related_entities",
      description: "List entities 1 hop away (related) from a given entity GUID",
      inputSchema: {
        type: "object",
        properties: {
          entityGuid: {
            type: "string",
            description: "The GUID of the entity to find related entities for",
          },
        },
        required: ["entityGuid"],
      },
    },
    {
      name: "search_entity_with_tag",
      description: "Search for entities using a specific tag key and value",
      inputSchema: {
        type: "object",
        properties: {
          tagKey: {
            type: "string",
            description: "The tag key to search for",
          },
          tagValue: {
            type: "string",
            description: "The tag value to match",
          },
          accountId: {
            type: "integer",
            description: "New Relic account ID",
          },
        },
        required: ["tagKey", "tagValue"],
      },
    },

    // Data Access
    {
      name: "execute_nrql_query",
      description: "Execute an NRQL query against NRDB",
      inputSchema: {
        type: "object",
        properties: {
          accountId: {
            type: "integer",
            description: "New Relic account ID",
          },
          query: {
            type: "string",
            description: "NRQL query string",
          },
        },
        required: ["accountId", "query"],
      },
    },
    {
      name: "natural_language_to_nrql_query",
      description: "Convert natural language to NRQL and execute it",
      inputSchema: {
        type: "object",
        properties: {
          accountId: {
            type: "integer",
            description: "New Relic account ID",
          },
          naturalLanguageQuery: {
            type: "string",
            description: "Natural language description of the query",
          },
        },
        required: ["accountId", "naturalLanguageQuery"],
      },
    },

    // Alerting and Monitoring
    {
      name: "list_alert_policies",
      description: "List alert policies for the specified account, optionally filtering by policy name",
      inputSchema: {
        type: "object",
        properties: {
          accountId: {
            type: "integer",
            description: "New Relic account ID",
          },
          policyName: {
            type: "string",
            description: "Optional policy name filter",
          },
        },
        required: ["accountId"],
      },
    },
    {
      name: "list_alert_conditions",
      description: "List alert condition details for a specific alert policy",
      inputSchema: {
        type: "object",
        properties: {
          accountId: {
            type: "integer",
            description: "New Relic account ID",
          },
          policyId: {
            type: "string",
            description: "The ID of the alert policy",
          },
        },
        required: ["accountId", "policyId"],
      },
    },
    {
      name: "list_recent_issues",
      description: "Lists all open issues in New Relic for the specified account",
      inputSchema: {
        type: "object",
        properties: {
          accountId: {
            type: "integer",
            description: "New Relic account ID",
          },
        },
        required: ["accountId"],
      },
    },
    {
      name: "search_incident",
      description: "List all alert events (both open and close events) with flexible filtering",
      inputSchema: {
        type: "object",
        properties: {
          accountId: {
            type: "integer",
            description: "New Relic account ID",
          },
          entityGuid: {
            type: "string",
            description: "Filter by entity GUID",
          },
          startTime: {
            type: "string",
            description: "Start time for the search range (ISO 8601)",
          },
          endTime: {
            type: "string",
            description: "End time for the search range (ISO 8601)",
          },
        },
        required: ["accountId"],
      },
    },
    {
      name: "list_synthetic_monitors",
      description: "List all synthetic monitors for the specified account",
      inputSchema: {
        type: "object",
        properties: {
          accountId: {
            type: "integer",
            description: "New Relic account ID",
          },
        },
        required: ["accountId"],
      },
    },

    // Performance Analytics
    {
      name: "analyze_golden_metrics",
      description: "Analyze golden metrics (throughput, response time, errors) for an entity",
      inputSchema: {
        type: "object",
        properties: {
          entityGuid: {
            type: "string",
            description: "Entity GUID to analyze",
          },
          timePeriod: {
            type: "string",
            description: "Time period (e.g., 'last 30 minutes')",
          },
        },
        required: ["entityGuid"],
      },
    },
    {
      name: "analyze_entity_logs",
      description: "Analyze application logs to identify error patterns, anomalous behavior, and recurring issues",
      inputSchema: {
        type: "object",
        properties: {
          entityGuid: {
            type: "string",
            description: "Entity GUID to analyze logs for",
          },
          timePeriod: {
            type: "string",
            description: "Time period (e.g., 'last 30 minutes')",
          },
        },
        required: ["entityGuid"],
      },
    },
    {
      name: "list_recent_logs",
      description: "List recent logs from New Relic for the specified account and entity GUID",
      inputSchema: {
        type: "object",
        properties: {
          accountId: {
            type: "integer",
            description: "New Relic account ID",
          },
          entityGuid: {
            type: "string",
            description: "Entity GUID to get logs for",
          },
          limit: {
            type: "integer",
            description: "Maximum number of log entries to return",
          },
        },
        required: ["accountId", "entityGuid"],
      },
    },
    {
      name: "analyze_transactions",
      description: "Analyze transaction performance for an entity",
      inputSchema: {
        type: "object",
        properties: {
          entityGuid: {
            type: "string",
            description: "Entity GUID to analyze",
          },
          timePeriod: {
            type: "string",
            description: "Time period (e.g., 'last 30 minutes')",
          },
        },
        required: ["entityGuid"],
      },
    },
    {
      name: "analyze_threads",
      description: "Analyze thread activity for an entity",
      inputSchema: {
        type: "object",
        properties: {
          entityGuid: {
            type: "string",
            description: "Entity GUID to analyze",
          },
        },
        required: ["entityGuid"],
      },
    },
    {
      name: "analyze_kafka_metrics",
      description: "Analyze Kafka metrics for an entity",
      inputSchema: {
        type: "object",
        properties: {
          entityGuid: {
            type: "string",
            description: "Kafka entity GUID to analyze",
          },
        },
        required: ["entityGuid"],
      },
    },

    // Advanced Analysis
    {
      name: "analyze_deployment_impact",
      description: "Analyze the performance impact of a deployment on a specific entity",
      inputSchema: {
        type: "object",
        properties: {
          entityGuid: {
            type: "string",
            description: "Entity GUID to analyze",
          },
          deploymentId: {
            type: "string",
            description: "Deployment ID to analyze",
          },
        },
        required: ["entityGuid"],
      },
    },
    {
      name: "generate_alert_insights_report",
      description: "Generate an alert intelligence analysis report for a specific issue",
      inputSchema: {
        type: "object",
        properties: {
          issueId: {
            type: "string",
            description: "Issue ID to generate report for",
          },
          accountId: {
            type: "integer",
            description: "New Relic account ID",
          },
        },
        required: ["issueId", "accountId"],
      },
    },
    {
      name: "generate_user_impact_report",
      description: "Generate an end-user impact analysis report for a specific issue",
      inputSchema: {
        type: "object",
        properties: {
          issueId: {
            type: "string",
            description: "Issue ID to generate report for",
          },
          accountId: {
            type: "integer",
            description: "New Relic account ID",
          },
        },
        required: ["issueId", "accountId"],
      },
    },

    // Utilities
    {
      name: "convert_time_period_to_epoch_ms",
      description: "Convert a time period (e.g., 'last 30 minutes') to epoch milliseconds",
      inputSchema: {
        type: "object",
        properties: {
          timePeriod: {
            type: "string",
            description: "Time period to convert",
          },
        },
        required: ["timePeriod"],
      },
    },
    {
      name: "get_dashboard",
      description: "Fetch details about a specific dashboard",
      inputSchema: {
        type: "object",
        properties: {
          dashboardGuid: {
            type: "string",
            description: "Dashboard GUID to fetch",
          },
        },
        required: ["dashboardGuid"],
      },
    },
  ];
}
