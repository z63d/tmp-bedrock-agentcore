/**
 * Responses API Module
 *
 * Exports CloudWatch client for use with Bedrock Responses API
 * and AgentCore Gateway.
 */
export {
  CloudWatchResponsesClient,
  type CloudWatchClientConfig,
  type CloudWatchResponse,
  type ToolExecutionResult,
} from "./cloudwatch-client.js";
