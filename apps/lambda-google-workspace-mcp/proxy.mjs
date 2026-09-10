// MCP Protocol Compatibility Proxy
//
// AgentCore Gateway (2026-07-28) と MCP SDK 1.x (2025-03-26) の
// プロトコルバージョン差を吸収するプロキシ。
//
// 背景:
//   AgentCore Gateway は MCP 2026-07-28 のメソッド (server/discover 等) を送るが、
//   piotr-agier/google-drive-mcp が依存する @modelcontextprotocol/sdk 1.x は
//   2025-03-26 までしかサポートしていない。未知のメソッドに対して SDK は
//   "Method not found" を返し、Gateway はこれを致命的エラーとして target 作成に失敗する。
//
// 方針:
//   - server/discover: initialize + tools/list を内部で実行し、合成レスポンスを返す
//   - resources/templates/list: SDK 未登録のため空リストを返す
//   - その他: MCP サーバーにそのまま透過フォワード
//
// 構成:
//   [Lambda Web Adapter] :8080 → [proxy.mjs] :8080 → [google-drive-mcp] :8081
//
// MCP SDK が 2026-07-28 をサポートしたらこのプロキシは不要になる。

import http from "node:http";

const TARGET = { hostname: "127.0.0.1", port: 8081 };
const LISTEN_PORT = 8080;

function forwardRequest(req, res, body) {
  const proxyReq = http.request(
    { ...TARGET, path: req.url, method: req.method, headers: req.headers },
    (proxyRes) => {
      let resData = "";
      proxyRes.on("data", (chunk) => { resData += chunk; res.write(chunk); });
      proxyRes.on("end", () => {
        if (proxyRes.statusCode >= 400 || resData.includes('"error"')) {
          console.log("RESP_ERR:", proxyRes.statusCode, resData.slice(0, 1000));
        }
        res.end();
      });
      res.writeHead(proxyRes.statusCode, proxyRes.headers);
    }
  );
  proxyReq.on("error", () => {
    res.writeHead(502);
    res.end();
  });
  proxyReq.end(body);
}

// server/discover (MCP 2026-07-28):
// initialize + tools/list を実行し、結果をマージして返す
function handleDiscover(parsedBody, res) {
  const initPayload = JSON.stringify({
    jsonrpc: "2.0",
    id: "_discover_init",
    method: "initialize",
    params: {
      protocolVersion: "2025-03-26",
      capabilities: {},
      clientInfo: { name: "discover-proxy", version: "1.0.0" },
    },
  });

  const initReq = http.request(
    { ...TARGET, path: "/mcp", method: "POST", headers: { "Content-Type": "application/json", Accept: "application/json, text/event-stream" } },
    (initRes) => {
      let data = "";
      initRes.on("data", (chunk) => (data += chunk));
      initRes.on("end", () => {
        try {
          let initResult;
          if (data.includes("event: message")) {
            const match = data.match(/^data: (.+)$/m);
            initResult = match ? JSON.parse(match[1]).result : null;
          } else {
            initResult = JSON.parse(data).result;
          }
          const sessionId = initRes.headers["mcp-session-id"];

          const toolsPayload = JSON.stringify({ jsonrpc: "2.0", id: "_discover_tools", method: "tools/list", params: {} });
          const toolsHeaders = { "Content-Type": "application/json", Accept: "application/json, text/event-stream" };
          if (sessionId) toolsHeaders["mcp-session-id"] = sessionId;

          const toolsReq = http.request(
            { ...TARGET, path: "/mcp", method: "POST", headers: toolsHeaders },
            (toolsRes) => {
              let toolsData = "";
              toolsRes.on("data", (chunk) => (toolsData += chunk));
              toolsRes.on("end", () => {
                let toolsResult;
                if (toolsData.includes("event: message")) {
                  const match = toolsData.match(/^data: (.+)$/m);
                  toolsResult = match ? JSON.parse(match[1]).result : { tools: [] };
                } else {
                  toolsResult = JSON.parse(toolsData).result || { tools: [] };
                }

                if (sessionId) {
                  const delReq = http.request({ ...TARGET, path: "/mcp", method: "DELETE", headers: { "mcp-session-id": sessionId } });
                  delReq.on("error", () => {});
                  delReq.end();
                }

                const discoverResponse = {
                  jsonrpc: "2.0",
                  id: parsedBody.id,
                  result: {
                    ...initResult,
                    tools: toolsResult.tools || [],
                  },
                };
                const body = JSON.stringify(discoverResponse);
                res.writeHead(200, { "Content-Type": "application/json" });
                res.end(body);
                console.log(`server/discover responded with ${(toolsResult.tools || []).length} tools`);
              });
            }
          );
          toolsReq.on("error", () => { res.writeHead(502); res.end(); });
          toolsReq.end(toolsPayload);
        } catch (e) {
          console.error("discover proxy error:", e.message);
          res.writeHead(500);
          res.end(JSON.stringify({ jsonrpc: "2.0", id: parsedBody.id, error: { code: -32603, message: e.message } }));
        }
      });
    }
  );
  initReq.on("error", () => { res.writeHead(502); res.end(); });
  initReq.end(initPayload);
}

const server = http.createServer((req, res) => {
  let body = "";
  req.on("data", (chunk) => (body += chunk));
  req.on("end", () => {
    let parsed;
    try { parsed = JSON.parse(body); } catch { parsed = null; }

    if (parsed?.method === "server/discover") {
      console.log("Intercepting server/discover");
      handleDiscover(parsed, res);
    } else if (parsed?.method === "resources/templates/list") {
      console.log("Intercepting resources/templates/list → empty");
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ jsonrpc: "2.0", id: parsed.id, result: { resourceTemplates: [] } }));
    } else {
      if (parsed?.method) {
        console.log("FORWARD:", parsed.method, parsed.id || "(notification)");
      }
      forwardRequest(req, res, body);
    }
  });
});

server.listen(LISTEN_PORT, "0.0.0.0", () => console.log(`Proxy on :${LISTEN_PORT} -> :${TARGET.port}`));
