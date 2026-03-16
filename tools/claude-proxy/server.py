"""
Claude Agent SDK -> Anthropic API Proxy

Exposes a local HTTP server that mimics the Anthropic /v1/messages endpoint,
but routes requests through the Claude Agent SDK (which uses your Max subscription
via OAuth token). Claude Code does ALL the work -- tool execution, multi-turn
reasoning, etc. -- and the proxy returns the final composed answer.

The proxy connects to the Flutter app's already-running MCP server via SSE
(default: http://localhost:8765/mcp). This gives Claude Code access to all
TFC MCP tools (create_alarm, get_tag_value, search_drawings, etc.) without
spawning a subprocess.

Usage:
    1. Make sure Claude Code CLI is installed and logged in (claude auth login)
    2. Start the Flutter app (which launches the MCP server on port 8765)
    3. cd tools/claude-proxy && python3 -m venv .venv
    4. .venv/bin/pip install -r requirements.txt
    5. .venv/bin/python server.py
    6. Point your app at http://localhost:8082/v1/messages

Note: If running from inside a Claude Code session, unset CLAUDECODE:
    env CLAUDECODE="" .venv/bin/python server.py

Your tfc-hmi app can then use this as a drop-in replacement for the Anthropic API.
Claude Code handles tool use internally (Read, Write, Bash, etc.) and returns the
final text response to the Flutter app.
"""

import asyncio
import json
import logging
import os
import uuid
from typing import Any

from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware

from claude_agent_sdk import (
    query,
    ClaudeAgentOptions,
    AssistantMessage,
    ResultMessage,
    SystemMessage,
    TextBlock,
    ToolUseBlock,
)
from claude_agent_sdk.types import McpHttpServerConfig

_log_level = logging.DEBUG if os.environ.get("PROXY_DEBUG") else logging.INFO
logging.basicConfig(level=_log_level)
logger = logging.getLogger("claude-proxy")

# Maximum agentic turns (tool-use round trips) before Claude stops.
# Each turn = one tool call + response. 25 is generous for most tasks.
MAX_TURNS = int(os.environ.get("PROXY_MAX_TURNS", "25"))

# Timeout in seconds for the entire query execution. Claude Code can run
# many tool-use turns which may take minutes. Default 60s keeps the HTTP
# connection from hanging indefinitely. Set PROXY_TIMEOUT=0 to disable.
QUERY_TIMEOUT = int(os.environ.get("PROXY_TIMEOUT", "300"))

# Per-message timeout for streaming: how long to wait for the *next* message
# from the agent SDK before giving up and closing the stream. This lets
# partial results stream through while still bailing on stuck queries.
STREAM_MSG_TIMEOUT = int(os.environ.get("PROXY_STREAM_MSG_TIMEOUT", "120"))

# --------------------------------------------------------------------------
# MCP Server Configuration (SSE — connects to running Flutter app)
# --------------------------------------------------------------------------
# The Flutter app runs the TFC MCP server in-process and exposes it via SSE.
# Default URL: http://localhost:8765/mcp
#
# Override with PROXY_MCP_URL env var.
# Set PROXY_MCP_ENABLED=false to disable.

_mcp_url = os.environ.get("PROXY_MCP_URL", "http://localhost:8765/mcp")
_mcp_enabled = os.environ.get("PROXY_MCP_ENABLED", "true").lower() != "false"

MCP_SERVERS: dict[str, Any] = (
    {"tfc": McpHttpServerConfig(type="http", url=_mcp_url)}
    if _mcp_enabled
    else {}
)

app = FastAPI(title="Claude Agent SDK API Proxy")

# Allow all origins for local dev -- tfc-hmi may be on a different port
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def make_message_response(
    content_blocks: list[dict],
    model: str = "claude-sonnet-4-5-20250514",
    input_tokens: int = 0,
    output_tokens: int = 0,
    stop_reason: str = "end_turn",
) -> dict:
    """Build a response that looks like the Anthropic /v1/messages response."""
    return {
        "id": f"msg_{uuid.uuid4().hex[:24]}",
        "type": "message",
        "role": "assistant",
        "content": content_blocks,
        "model": model,
        "stop_reason": stop_reason,
        "stop_sequence": None,
        "usage": {
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
        },
    }


def make_sse_event(event_type: str, data: dict) -> str:
    """Format a Server-Sent Event."""
    return f"event: {event_type}\ndata: {json.dumps(data)}\n\n"


def extract_prompt_from_messages(messages: list[dict], system: str = "") -> str:
    """
    Convert Anthropic-style messages array into a single prompt string
    for the Agent SDK.

    The system prompt is prepended as context. Message history is formatted
    so Claude understands the conversation flow.
    """
    parts = []

    if system:
        parts.append(f"[system context]: {system}")

    for msg in messages:
        role = msg.get("role", "user")
        content = msg.get("content", "")

        if isinstance(content, str):
            parts.append(f"[{role}]: {content}")
        elif isinstance(content, list):
            # Handle content blocks (text, images, tool_use, tool_result, etc.)
            text_parts = []
            for block in content:
                if isinstance(block, dict):
                    if block.get("type") == "text":
                        text_parts.append(block["text"])
                    elif block.get("type") == "tool_result":
                        # Include tool results so Claude has context
                        result_content = block.get("content", "")
                        if isinstance(result_content, list):
                            for sub in result_content:
                                if isinstance(sub, dict) and sub.get("type") == "text":
                                    text_parts.append(f"[tool result]: {sub['text']}")
                        elif isinstance(result_content, str):
                            text_parts.append(f"[tool result]: {result_content}")
            if text_parts:
                parts.append(f"[{role}]: {' '.join(text_parts)}")

    return "\n".join(parts)


def format_tool_progress(tool: ToolUseBlock) -> str:
    """Format a ToolUseBlock into a brief, human-readable progress line.

    Uses friendly names and icons for common Claude Code built-in tools,
    and a wrench icon for MCP / custom tools.
    """
    name = tool.name
    inp = tool.input or {}

    if name == "Read":
        path = inp.get("file_path", "")
        # Show just the filename or last two path components
        short = "/".join(path.rsplit("/", 2)[-2:]) if "/" in path else path
        return f"\U0001f4d6 Reading {short}..."
    elif name == "Write":
        path = inp.get("file_path", "")
        short = "/".join(path.rsplit("/", 2)[-2:]) if "/" in path else path
        return f"\u270f\ufe0f Writing {short}..."
    elif name == "Edit":
        path = inp.get("file_path", "")
        short = "/".join(path.rsplit("/", 2)[-2:]) if "/" in path else path
        return f"\u270f\ufe0f Editing {short}..."
    elif name == "Bash":
        cmd = inp.get("command", "")
        # Show first 60 chars of the command
        short_cmd = (cmd[:60] + "...") if len(cmd) > 60 else cmd
        return f"\u26a1 Running: {short_cmd}"
    elif name == "Grep":
        pattern = inp.get("pattern", "")
        return f"\U0001f50d Searching for \"{pattern}\"..."
    elif name == "Glob":
        pattern = inp.get("pattern", "")
        return f"\U0001f50d Finding files: {pattern}..."
    elif name == "WebSearch":
        q = inp.get("query", "")
        return f"\U0001f310 Searching web: {q}..."
    elif name == "WebFetch":
        url = inp.get("url", "")
        return f"\U0001f310 Fetching {url[:60]}..."
    else:
        # MCP tools and everything else
        return f"\U0001f527 {name}..."


def format_system_progress(message: SystemMessage) -> str | None:
    """Format a SystemMessage into a progress line, or None to skip it."""
    subtype = message.subtype
    data = message.data or {}

    if subtype == "task_started":
        desc = data.get("description", "")
        return f"\U0001f680 Task started: {desc}" if desc else None
    elif subtype == "task_progress":
        desc = data.get("description", "")
        return f"\u23f3 {desc}" if desc else None
    return None


def extract_progress_from_assistant(message: AssistantMessage) -> list[str]:
    """Extract progress lines from ToolUseBlock instances in an AssistantMessage."""
    lines = []
    for block in message.content:
        if isinstance(block, ToolUseBlock):
            lines.append(format_tool_progress(block))
    return lines


def extract_text_from_assistant(message: AssistantMessage) -> str | None:
    """Extract all text content from an AssistantMessage.

    Collects text from TextBlock instances, ignoring ToolUseBlock and
    ThinkingBlock content (tool execution is handled internally by
    Claude Code; we only want the final human-readable text).
    """
    texts = []
    for block in message.content:
        if isinstance(block, TextBlock):
            texts.append(block.text)
    return "\n".join(texts) if texts else None


@app.post("/v1/messages")
async def create_message(request: Request):
    """
    Anthropic-compatible /v1/messages endpoint.

    Accepts the same JSON body as the real API and proxies through
    the Agent SDK. Claude Code handles all tool execution internally
    and returns the final composed answer.
    """
    body = await request.json()

    messages = body.get("messages", [])
    # Handle system prompt - can be a string or a list of content blocks
    # (prompt caching format: [{"type": "text", "text": "...", "cache_control": ...}])
    raw_system = body.get("system", "")
    if isinstance(raw_system, list):
        system = "\n".join(
            block["text"] for block in raw_system
            if isinstance(block, dict) and block.get("type") == "text"
        )
    else:
        system = raw_system or ""
    model = body.get("model", "claude-sonnet-4-5-20250514")
    stream = body.get("stream", False)

    # Build prompt from messages
    prompt = extract_prompt_from_messages(messages, system)

    logger.info(
        "Received %s request (model=%s, messages=%d, prompt_len=%d)",
        "streaming" if stream else "non-streaming",
        model,
        len(messages),
        len(prompt),
    )
    logger.debug("Prompt: %s", prompt[:500])

    # Configure Agent SDK options.
    #
    # Key design choices:
    #   - permission_mode="bypassPermissions": Auto-approve all tool calls.
    #     The proxy is a local dev tool; we don't want it blocking on
    #     permission prompts that nobody will answer.
    #   - max_turns=25: Let Claude execute multi-step tool chains
    #     (e.g. read file -> grep -> analyze -> respond).
    #   - No allowed_tools restriction: Claude Code uses its full toolset.
    #   - model: Pass through the requested model if supported.
    options = ClaudeAgentOptions(
        system_prompt=system if system else None,
        permission_mode="bypassPermissions",
        max_turns=MAX_TURNS,
        model=model if model else None,
        mcp_servers=MCP_SERVERS if MCP_SERVERS else {},
    )

    if stream:
        return StreamingResponse(
            stream_response(prompt, options, model),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
            },
        )
    else:
        return await non_stream_response(prompt, options, model)


async def stream_response(prompt: str, options: ClaudeAgentOptions, model: str):
    """
    Stream response as SSE events matching Anthropic's streaming format.

    Events: message_start, content_block_start, content_block_delta,
            content_block_stop, message_delta, message_stop

    Claude Code may execute multiple tool-use turns internally. Each time
    it produces an AssistantMessage with text, we stream those text chunks
    to the client. The client sees a continuous text stream.
    """
    msg_id = f"msg_{uuid.uuid4().hex[:24]}"

    # message_start
    yield make_sse_event("message_start", {
        "type": "message_start",
        "message": {
            "id": msg_id,
            "type": "message",
            "role": "assistant",
            "content": [],
            "model": model,
            "stop_reason": None,
            "stop_sequence": None,
            "usage": {"input_tokens": 0, "output_tokens": 0},
        },
    })

    # content_block_start
    yield make_sse_event("content_block_start", {
        "type": "content_block_start",
        "index": 0,
        "content_block": {"type": "text", "text": ""},
    })

    # Stream text deltas from the full multi-turn agent execution.
    # A per-message timeout ensures that if a single tool-use turn stalls,
    # we close the stream gracefully instead of hanging the HTTP connection.
    full_text = ""
    result_usage = {}
    msg_timeout = STREAM_MSG_TIMEOUT if STREAM_MSG_TIMEOUT > 0 else None
    try:
        aiter = query(prompt=prompt, options=options).__aiter__()
        while True:
            try:
                if msg_timeout:
                    message = await asyncio.wait_for(
                        aiter.__anext__(), timeout=msg_timeout
                    )
                else:
                    message = await aiter.__anext__()
            except StopAsyncIteration:
                break
            except asyncio.TimeoutError:
                logger.warning(
                    "Stream per-message timeout (%ds) — closing stream with "
                    "partial result",
                    STREAM_MSG_TIMEOUT,
                )
                timeout_text = (
                    f"\n\n[Proxy timeout: no message received for "
                    f"{STREAM_MSG_TIMEOUT}s]"
                )
                yield make_sse_event("content_block_delta", {
                    "type": "content_block_delta",
                    "index": 0,
                    "delta": {"type": "text_delta", "text": timeout_text},
                })
                break

            if isinstance(message, SystemMessage):
                progress = format_system_progress(message)
                if progress:
                    progress_line = progress + "\n"
                    full_text += progress_line
                    yield make_sse_event("content_block_delta", {
                        "type": "content_block_delta",
                        "index": 0,
                        "delta": {"type": "text_delta", "text": progress_line},
                    })
            elif isinstance(message, AssistantMessage):
                # Emit progress lines for tool calls first
                progress_lines = extract_progress_from_assistant(message)
                for line in progress_lines:
                    progress_text = line + "\n"
                    full_text += progress_text
                    yield make_sse_event("content_block_delta", {
                        "type": "content_block_delta",
                        "index": 0,
                        "delta": {"type": "text_delta", "text": progress_text},
                    })

                # Then emit the actual text content
                text = extract_text_from_assistant(message)
                if text:
                    # Separate progress from final text with a blank line
                    if full_text and progress_lines:
                        text = "\n" + text
                    elif full_text:
                        text = "\n\n" + text
                    full_text += text
                    yield make_sse_event("content_block_delta", {
                        "type": "content_block_delta",
                        "index": 0,
                        "delta": {"type": "text_delta", "text": text},
                    })
            elif isinstance(message, ResultMessage):
                # Capture usage info from the final result
                if message.usage:
                    result_usage = message.usage
                if message.is_error:
                    error_text = f"\n\n[Agent error: {message.result or 'unknown error'}]"
                    yield make_sse_event("content_block_delta", {
                        "type": "content_block_delta",
                        "index": 0,
                        "delta": {"type": "text_delta", "text": error_text},
                    })

    except Exception as e:
        logger.error("Agent SDK error: %s", e, exc_info=True)
        error_text = f"Error from Agent SDK: {str(e)}"
        yield make_sse_event("content_block_delta", {
            "type": "content_block_delta",
            "index": 0,
            "delta": {"type": "text_delta", "text": error_text},
        })

    # content_block_stop
    yield make_sse_event("content_block_stop", {
        "type": "content_block_stop",
        "index": 0,
    })

    # message_delta
    yield make_sse_event("message_delta", {
        "type": "message_delta",
        "delta": {"stop_reason": "end_turn", "stop_sequence": None},
        "usage": {
            "output_tokens": result_usage.get("output_tokens", len(full_text.split())),
        },
    })

    # message_stop
    yield make_sse_event("message_stop", {"type": "message_stop"})


async def _collect_non_stream(
    prompt: str, options: ClaudeAgentOptions
) -> tuple[list[str], list[str], dict]:
    """Inner coroutine that collects all text from the agent query.

    Separated so we can wrap it with asyncio.wait_for() for timeout support.
    Returns (texts, progress_lines, usage).
    """
    texts: list[str] = []
    progress: list[str] = []
    result_usage: dict = {}

    async for message in query(prompt=prompt, options=options):
        if isinstance(message, SystemMessage):
            line = format_system_progress(message)
            if line:
                progress.append(line)
        elif isinstance(message, AssistantMessage):
            # Collect progress from tool calls
            progress.extend(extract_progress_from_assistant(message))
            # Collect final text
            text = extract_text_from_assistant(message)
            if text:
                texts.append(text)
        elif isinstance(message, ResultMessage):
            if message.usage:
                result_usage = message.usage
            if message.is_error:
                logger.error(
                    "Agent execution error: %s (turns=%d)",
                    message.result,
                    message.num_turns,
                )

    return texts, progress, result_usage


async def non_stream_response(
    prompt: str, options: ClaudeAgentOptions, model: str
) -> JSONResponse:
    """
    Collect full response from the multi-turn agent execution and return
    as a single JSON response matching the Anthropic API format.

    Applies QUERY_TIMEOUT to prevent indefinite hangs. If the timeout fires,
    returns whatever text was collected up to that point.
    """
    texts: list[str] = []
    progress: list[str] = []
    result_usage: dict = {}
    timed_out = False

    try:
        if QUERY_TIMEOUT > 0:
            texts, progress, result_usage = await asyncio.wait_for(
                _collect_non_stream(prompt, options),
                timeout=QUERY_TIMEOUT,
            )
        else:
            texts, progress, result_usage = await _collect_non_stream(
                prompt, options
            )

    except asyncio.TimeoutError:
        timed_out = True
        logger.warning(
            "Query timed out after %ds, returning partial result (%d chunks)",
            QUERY_TIMEOUT,
            len(texts),
        )

    except Exception as e:
        logger.error("Agent SDK error: %s", e, exc_info=True)
        return JSONResponse(
            status_code=500,
            content={"error": {"type": "api_error", "message": str(e)}},
        )

    # Build full response: progress log + final text
    parts = []
    if progress:
        parts.append("\n".join(progress))
    if texts:
        parts.append("\n\n".join(texts))
    full_text = "\n\n".join(parts) if parts else "No response generated."
    if timed_out:
        full_text += f"\n\n[Proxy timeout: query exceeded {QUERY_TIMEOUT}s limit]"

    response = make_message_response(
        content_blocks=[{"type": "text", "text": full_text}],
        model=model,
        input_tokens=result_usage.get("input_tokens", 0),
        output_tokens=result_usage.get("output_tokens", len(full_text.split())),
    )

    return JSONResponse(content=response)


@app.get("/health")
async def health():
    """Health check endpoint."""
    mcp_info = {}
    if MCP_SERVERS:
        for name, cfg in MCP_SERVERS.items():
            mcp_info[name] = {"type": cfg.get("type"), "url": cfg.get("url")}
    return {
        "status": "ok",
        "backend": "claude-agent-sdk",
        "max_turns": MAX_TURNS,
        "query_timeout": QUERY_TIMEOUT,
        "stream_msg_timeout": STREAM_MSG_TIMEOUT,
        "mcp_servers": mcp_info,
    }


@app.get("/v1/models")
async def list_models():
    """Minimal models endpoint for clients that check available models."""
    return {
        "models": [
            {"id": "claude-sonnet-4-5-20250514", "name": "Claude Sonnet 4.5"},
            {"id": "claude-opus-4-6", "name": "Claude Opus 4.6"},
        ]
    }


if __name__ == "__main__":
    import uvicorn

    mcp_url = os.environ.get("PROXY_MCP_URL", "http://localhost:8765/mcp")

    print("=" * 60)
    print("Claude Agent SDK -> Anthropic API Proxy")
    print("=" * 60)
    print()
    print("Endpoints:")
    print("  POST http://localhost:8082/v1/messages  (API-compatible)")
    print("  GET  http://localhost:8082/health")
    print("  GET  http://localhost:8082/v1/models")
    print()
    print(f"Config:")
    print(f"  Max turns:          {MAX_TURNS} (PROXY_MAX_TURNS)")
    print(f"  Query timeout:      {QUERY_TIMEOUT}s (PROXY_TIMEOUT, 0=off)")
    print(f"  Stream msg timeout: {STREAM_MSG_TIMEOUT}s (PROXY_STREAM_MSG_TIMEOUT, 0=off)")
    print(f"  Debug:              {'on' if os.environ.get('PROXY_DEBUG') else 'off'} (PROXY_DEBUG=1)")
    if MCP_SERVERS:
        print(f"  MCP (SSE):          {mcp_url} (PROXY_MCP_URL)")
    else:
        print(f"  MCP:                disabled (PROXY_MCP_ENABLED=false)")
    print()
    print("Auth: Uses Claude Code's existing login (Max subscription).")
    print("      Run 'claude auth login' if not already logged in.")
    print()
    print("MCP: Connects to the Flutter app's in-process MCP server via SSE.")
    print("     Make sure the Flutter app is running before starting this proxy.")
    print()
    print("If running from inside a Claude Code session:")
    print("  env CLAUDECODE='' .venv/bin/python server.py")
    print("=" * 60)

    uvicorn.run(app, host="0.0.0.0", port=8082)
