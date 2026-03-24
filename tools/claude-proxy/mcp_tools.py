"""
MCP Tool Schema Fetcher

Connects to the Flutter app's MCP server (Streamable HTTP transport) and
fetches available tool schemas. Converts them from MCP format to the
Anthropic API tool format so the proxy can pass them to Claude.

MCP Protocol (Streamable HTTP / JSON-RPC 2.0):
  1. POST /mcp with "initialize" -> get session ID from Mcp-Session-Id header
  2. POST /mcp with "notifications/initialized" (using session ID)
  3. POST /mcp with "tools/list" (using session ID) -> tool definitions

Anthropic API tool format:
  {
    "name": "tool_name",
    "description": "tool description",
    "input_schema": { ... JSON Schema ... }
  }

Usage:
    from mcp_tools import McpToolFetcher

    fetcher = McpToolFetcher("http://localhost:8765/mcp")
    tools = await fetcher.fetch_tools()
    # Returns list of dicts in Anthropic API tool format

Standalone test:
    python mcp_tools.py [http://localhost:8765/mcp]
"""

import asyncio
import json
import logging
import time
from typing import Any

import httpx

logger = logging.getLogger("claude-proxy.mcp-tools")


# ---------------------------------------------------------------------------
# JSON-RPC 2.0 helpers
# ---------------------------------------------------------------------------
_request_id_counter = 0


def _next_id() -> int:
    """Generate a monotonically increasing JSON-RPC request ID."""
    global _request_id_counter
    _request_id_counter += 1
    return _request_id_counter


def _jsonrpc_request(method: str, params: dict | None = None) -> dict:
    """Build a JSON-RPC 2.0 request message."""
    msg: dict[str, Any] = {
        "jsonrpc": "2.0",
        "id": _next_id(),
        "method": method,
    }
    if params is not None:
        msg["params"] = params
    return msg


def _jsonrpc_notification(method: str, params: dict | None = None) -> dict:
    """Build a JSON-RPC 2.0 notification message (no id = no response expected)."""
    msg: dict[str, Any] = {
        "jsonrpc": "2.0",
        "method": method,
    }
    if params is not None:
        msg["params"] = params
    return msg


# ---------------------------------------------------------------------------
# Response parsing
# ---------------------------------------------------------------------------

def parse_mcp_response(response: httpx.Response) -> dict | None:
    """Parse an MCP HTTP response, handling both JSON-RPC and SSE formats.

    The MCP Streamable HTTP transport can return:
    - Direct JSON-RPC response (Content-Type: application/json)
    - SSE stream with JSON-RPC events (Content-Type: text/event-stream)

    For SSE, we extract the first complete JSON-RPC message from the
    data fields. Multi-line SSE data payloads are concatenated.
    """
    content_type = response.headers.get("content-type", "")

    if "text/event-stream" in content_type:
        return _parse_sse_response(response.text)
    elif "application/json" in content_type:
        try:
            return response.json()
        except json.JSONDecodeError:
            return None
    else:
        # Unknown content type -- try JSON first, then SSE
        try:
            return response.json()
        except (json.JSONDecodeError, ValueError):
            pass
        return _parse_sse_response(response.text)


def _parse_sse_response(text: str) -> dict | None:
    """Extract the first JSON-RPC message from SSE text.

    Handles multi-line data fields per the SSE spec: consecutive
    lines starting with "data:" are concatenated with newlines.
    """
    data_parts: list[str] = []

    for line in text.split("\n"):
        stripped = line.strip()

        if stripped.startswith("data:"):
            data_str = stripped[5:].strip()
            if data_str:
                data_parts.append(data_str)
        elif stripped == "" and data_parts:
            # Empty line = end of event, try to parse accumulated data
            combined = "\n".join(data_parts)
            try:
                return json.loads(combined)
            except json.JSONDecodeError:
                data_parts = []
                continue

    # Handle case where there's no trailing empty line
    if data_parts:
        combined = "\n".join(data_parts)
        try:
            return json.loads(combined)
        except json.JSONDecodeError:
            pass

    return None


# ---------------------------------------------------------------------------
# MCP -> Anthropic schema conversion
# ---------------------------------------------------------------------------

def mcp_tool_to_anthropic(tool: dict) -> dict:
    """Convert a single MCP tool definition to Anthropic API tool format.

    MCP format:
      {
        "name": "tool_name",
        "description": "...",
        "inputSchema": { "type": "object", "properties": {...}, ... }
      }

    Anthropic format:
      {
        "name": "tool_name",
        "description": "...",
        "input_schema": { "type": "object", "properties": {...}, ... }
      }

    Key differences handled:
    - inputSchema -> input_schema (camelCase to snake_case)
    - Ensures "type": "object" and "properties" exist (Anthropic requires them)
    - Strips MCP-specific fields not used by Anthropic
    """
    result: dict[str, Any] = {
        "name": tool["name"],
    }

    # Description is optional but recommended
    desc = tool.get("description")
    if desc:
        result["description"] = desc

    # Convert inputSchema to input_schema
    input_schema = dict(tool.get("inputSchema", {}))

    # Anthropic requires "type": "object" at the top level
    if "type" not in input_schema:
        input_schema["type"] = "object"

    # Anthropic requires "properties" for object schemas
    if input_schema.get("type") == "object" and "properties" not in input_schema:
        input_schema["properties"] = {}

    result["input_schema"] = input_schema

    return result


# ---------------------------------------------------------------------------
# McpToolFetcher class
# ---------------------------------------------------------------------------

class McpToolFetcher:
    """Fetches and caches MCP tool schemas from a Streamable HTTP MCP server.

    Performs the full MCP session handshake (initialize -> initialized
    notification -> tools/list) and converts tool schemas to Anthropic
    API format.

    Thread-safe via asyncio.Lock for cache access. Supports both managed
    (internal) and external httpx clients.

    Args:
        mcp_url: URL of the MCP server endpoint (e.g., http://localhost:8765/mcp).
        cache_ttl: Cache TTL in seconds. Set to 0 to disable caching.
        timeout: HTTP request timeout in seconds.
        client: Optional external httpx.AsyncClient. If not provided, a new
                client is created per fetch operation.
    """

    def __init__(
        self,
        mcp_url: str = "http://localhost:8765/mcp",
        cache_ttl: float = 60.0,
        timeout: float = 10.0,
        client: httpx.AsyncClient | None = None,
    ):
        self._mcp_url = mcp_url
        self._cache_ttl = cache_ttl
        self._timeout = timeout
        self._external_client = client

        # Cache state
        self._cached_tools: list[dict] | None = None
        self._cache_time: float = 0.0
        self._cache_lock = asyncio.Lock()

    @property
    def mcp_url(self) -> str:
        return self._mcp_url

    @property
    def cached_tool_count(self) -> int:
        """Number of tools in cache (0 if cache is empty)."""
        return len(self._cached_tools) if self._cached_tools else 0

    @property
    def cache_age(self) -> float:
        """Age of cache in seconds (0 if cache is empty)."""
        if self._cache_time == 0:
            return 0
        return time.monotonic() - self._cache_time

    async def invalidate_cache(self) -> None:
        """Force-invalidate the tool cache."""
        async with self._cache_lock:
            self._cached_tools = None
            self._cache_time = 0.0
        logger.info("MCP tool cache invalidated")

    async def fetch_tools(self, *, force_refresh: bool = False) -> list[dict]:
        """Fetch MCP tool schemas and return in Anthropic API tool format.

        Returns cached results if available and not expired, unless
        force_refresh is True.

        Returns an empty list if the MCP server is unreachable. Falls
        back to stale cache on transient errors.
        """
        # Check cache (under lock for thread safety)
        if not force_refresh:
            async with self._cache_lock:
                if (
                    self._cached_tools is not None
                    and self._cache_ttl > 0
                    and (time.monotonic() - self._cache_time) < self._cache_ttl
                ):
                    logger.debug(
                        "Returning %d cached MCP tools (age=%.1fs)",
                        len(self._cached_tools),
                        time.monotonic() - self._cache_time,
                    )
                    return self._cached_tools

        # Fetch fresh tools
        try:
            tools = await self._do_fetch()
            async with self._cache_lock:
                self._cached_tools = tools
                self._cache_time = time.monotonic()
            return tools

        except httpx.ConnectError:
            logger.warning(
                "MCP server not reachable at %s", self._mcp_url
            )
            return self._stale_cache_or_empty()

        except httpx.TimeoutException:
            logger.warning(
                "MCP server timeout at %s", self._mcp_url
            )
            return self._stale_cache_or_empty()

        except Exception as e:
            logger.error(
                "Failed to fetch MCP tools from %s: %s",
                self._mcp_url, e, exc_info=True,
            )
            return self._stale_cache_or_empty()

    def _stale_cache_or_empty(self) -> list[dict]:
        """Return stale cache if available, otherwise empty list."""
        if self._cached_tools is not None:
            logger.info(
                "Returning stale cache (%d tools, age=%.0fs)",
                len(self._cached_tools),
                time.monotonic() - self._cache_time,
            )
            return self._cached_tools
        return []

    async def _do_fetch(self) -> list[dict]:
        """Perform the full MCP handshake and return tools in Anthropic format.

        Steps:
          1. Send "initialize" request -> get session ID from headers
          2. Send "notifications/initialized" notification
          3. Send "tools/list" request -> get tool definitions
          4. Convert each tool to Anthropic API format
        """
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
        }

        if self._external_client:
            return await self._fetch_with_client(self._external_client, headers)
        else:
            async with httpx.AsyncClient(
                timeout=httpx.Timeout(self._timeout, connect=5.0)
            ) as client:
                return await self._fetch_with_client(client, headers)

    async def _fetch_with_client(
        self, client: httpx.AsyncClient, base_headers: dict
    ) -> list[dict]:
        """Execute MCP handshake using the given client."""

        # ── Step 1: Initialize ─────────────────────────────────────────
        init_request = _jsonrpc_request("initialize", {
            "protocolVersion": "2025-03-26",
            "capabilities": {},
            "clientInfo": {
                "name": "claude-proxy",
                "version": "1.0.0",
            },
        })

        logger.debug("Sending initialize to %s", self._mcp_url)
        init_response = await client.post(
            self._mcp_url, json=init_request, headers=base_headers
        )
        init_response.raise_for_status()

        # Session ID comes from the Mcp-Session-Id header (case-insensitive)
        session_id = (
            init_response.headers.get("Mcp-Session-Id")
            or init_response.headers.get("mcp-session-id")
        )

        # Validate initialize response
        init_result = parse_mcp_response(init_response)
        if init_result and "error" in init_result:
            raise RuntimeError(
                f"MCP initialize failed: {init_result['error']}"
            )

        logger.debug(
            "MCP session initialized (session=%s)", session_id or "none"
        )

        # Build session headers for subsequent requests
        session_headers = {**base_headers}
        if session_id:
            session_headers["Mcp-Session-Id"] = session_id

        # ── Step 2: Send initialized notification ──────────────────────
        init_notification = _jsonrpc_notification("notifications/initialized")

        logger.debug("Sending notifications/initialized")
        notify_response = await client.post(
            self._mcp_url, json=init_notification, headers=session_headers
        )
        # Notifications may return 200, 202 Accepted, or 204 No Content
        if notify_response.status_code not in (200, 202, 204):
            logger.warning(
                "notifications/initialized returned %d",
                notify_response.status_code,
            )

        # ── Step 3: List tools ─────────────────────────────────────────
        list_request = _jsonrpc_request("tools/list")

        logger.debug("Sending tools/list")
        list_response = await client.post(
            self._mcp_url, json=list_request, headers=session_headers
        )
        list_response.raise_for_status()

        list_result = parse_mcp_response(list_response)
        if list_result is None:
            logger.warning("Empty response from tools/list")
            return []

        if "error" in list_result:
            raise RuntimeError(
                f"MCP tools/list failed: {list_result['error']}"
            )

        # Extract tool definitions from the result
        tools_data = list_result.get("result", {}).get("tools", [])

        logger.info(
            "Fetched %d MCP tools from %s", len(tools_data), self._mcp_url
        )

        # ── Step 4: Convert to Anthropic format ────────────────────────
        anthropic_tools: list[dict] = []
        for tool in tools_data:
            try:
                anthropic_tools.append(mcp_tool_to_anthropic(tool))
            except (KeyError, TypeError) as e:
                logger.warning(
                    "Skipping malformed tool %s: %s",
                    tool.get("name", "?"), e,
                )

        logger.info(
            "Converted %d tools to Anthropic format: %s",
            len(anthropic_tools),
            [t["name"] for t in anthropic_tools],
        )

        return anthropic_tools


# ---------------------------------------------------------------------------
# Module-level convenience functions (backward compatible)
# ---------------------------------------------------------------------------

# Default fetcher instance, lazily created
_default_fetcher: McpToolFetcher | None = None


def _get_default_fetcher(
    mcp_url: str = "http://localhost:8765/mcp",
    cache_ttl: float = 60.0,
) -> McpToolFetcher:
    """Get or create the default fetcher instance."""
    global _default_fetcher
    if _default_fetcher is None or _default_fetcher.mcp_url != mcp_url:
        _default_fetcher = McpToolFetcher(mcp_url=mcp_url, cache_ttl=cache_ttl)
    return _default_fetcher


async def fetch_mcp_tools(
    mcp_url: str = "http://localhost:8765/mcp",
    *,
    force_refresh: bool = False,
    cache_ttl: float = 60.0,
) -> list[dict]:
    """Convenience function: fetch MCP tools using a default fetcher.

    For more control (custom client, timeout), use McpToolFetcher directly.
    """
    fetcher = _get_default_fetcher(mcp_url, cache_ttl)
    return await fetcher.fetch_tools(force_refresh=force_refresh)


async def invalidate_cache() -> None:
    """Invalidate the default fetcher's cache."""
    if _default_fetcher is not None:
        await _default_fetcher.invalidate_cache()


# ---------------------------------------------------------------------------
# CLI: run directly to test
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import sys

    logging.basicConfig(
        level=logging.DEBUG,
        format="%(asctime)s %(name)s %(levelname)s %(message)s",
    )

    url = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8765/mcp"

    async def main() -> None:
        fetcher = McpToolFetcher(mcp_url=url)
        tools = await fetcher.fetch_tools()

        if not tools:
            print(f"\nNo tools fetched from {url}")
            print("Is the Flutter app running with the MCP server on port 8765?")
            sys.exit(1)

        print(f"\nFetched {len(tools)} tools from {url}:\n")
        for tool in tools:
            name = tool["name"]
            desc = tool.get("description", "")[:80]
            schema = tool.get("input_schema", {})
            props = schema.get("properties", {})
            required = schema.get("required", [])

            print(f"  {name}")
            print(f"    {desc}")
            if props:
                for pname, pschema in props.items():
                    req_tag = " (required)" if pname in required else ""
                    ptype = pschema.get("type", "?")
                    pdesc = pschema.get("description", "")[:60]
                    print(f"      {pname}: {ptype}{req_tag} - {pdesc}")
            print()

        # Print raw JSON for inspection
        print("\n--- Raw Anthropic tool format ---")
        print(json.dumps(tools, indent=2))

        # Test cache
        print("\n--- Testing cache ---")
        tools2 = await fetcher.fetch_tools()
        print(f"Second call returned {len(tools2)} tools (should be cached)")
        print(f"Cache age: {fetcher.cache_age:.1f}s")

    asyncio.run(main())
