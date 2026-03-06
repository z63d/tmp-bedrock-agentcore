/**
 * AWS SigV4 Signed Fetch for AgentCore Gateway MCP
 *
 * Creates a fetch function that automatically signs requests with AWS SigV4.
 * This is required for calling AgentCore Gateway endpoints.
 */

import { SignatureV4 } from "@smithy/signature-v4";
import { Sha256 } from "@aws-crypto/sha256-js";
import { fromNodeProviderChain } from "@aws-sdk/credential-providers";

export interface SigV4FetchConfig {
  region: string;
  service?: string;
}

/**
 * Create a fetch function that signs requests with AWS SigV4
 */
export function createSigV4Fetch(config: SigV4FetchConfig): typeof fetch {
  const { region, service = "bedrock-agentcore" } = config;

  return async (
    input: string | URL | Request,
    init?: RequestInit
  ): Promise<Response> => {
    const url = typeof input === "string" ? new URL(input) : input instanceof URL ? input : new URL(input.url);
    const method = init?.method ?? "GET";
    const body = init?.body?.toString() ?? "";

    // Get AWS credentials
    const credentials = await fromNodeProviderChain()();

    // Prepare headers
    const headers: Record<string, string> = {
      host: url.hostname,
    };

    // Copy headers from init
    if (init?.headers) {
      const initHeaders = new Headers(init.headers);
      initHeaders.forEach((value, key) => {
        headers[key.toLowerCase()] = value;
      });
    }

    // Create signer
    const signer = new SignatureV4({
      service,
      region,
      credentials,
      sha256: Sha256,
    });

    // Sign the request
    const signedRequest = await signer.sign({
      method,
      protocol: url.protocol,
      hostname: url.hostname,
      path: url.pathname + url.search,
      headers,
      body,
    });

    // Make the actual fetch request
    const response = await fetch(url.toString(), {
      ...init,
      method: signedRequest.method,
      headers: signedRequest.headers as HeadersInit,
      body: init?.body,
    });

    // Log non-OK responses for debugging
    if (!response.ok) {
      const responseText = await response.clone().text();
      console.error(`SigV4 fetch error: ${response.status} ${response.statusText}`);
      console.error(`Response body: ${responseText}`);
    }

    return response;
  };
}
