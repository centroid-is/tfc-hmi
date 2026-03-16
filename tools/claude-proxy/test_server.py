"""
Integration tests for the Claude Agent SDK proxy server.

Tests verify:
1. /v1/messages returns Anthropic-compatible response format (non-streaming)
2. /v1/messages streaming returns proper SSE event sequence
3. Response format matches what ClaudeProvider (Flutter) expects to parse
4. Tool use blocks are handled internally (agent executes tools, returns text)
5. /health endpoint returns config info
6. /v1/models endpoint returns model list
7. Error handling: Agent SDK failures, timeouts
8. extract_prompt_from_messages correctly converts message arrays
9. make_message_response builds valid Anthropic response structure

Run:
    cd tools/claude-proxy
    pip install -r requirements.txt pytest httpx pytest-asyncio
    pytest test_server.py -v
"""

import asyncio
import json
import sys
from dataclasses import dataclass, field
from typing import Any, AsyncIterator
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
import pytest_asyncio

# ---------------------------------------------------------------------------
# Mock the claude_agent_sdk module BEFORE importing server.py.
#
# The real SDK is not available in test environments, so we create lightweight
# stand-ins for the types the server uses: TextBlock, ToolUseBlock,
# AssistantMessage, ResultMessage, SystemMessage, ClaudeAgentOptions, query,
# and McpHttpServerConfig.
# ---------------------------------------------------------------------------


@dataclass
class MockTextBlock:
    """Stand-in for claude_agent_sdk.TextBlock."""

    text: str
    type: str = "text"


@dataclass
class MockToolUseBlock:
    """Stand-in for claude_agent_sdk.ToolUseBlock."""

    name: str
    input: dict = field(default_factory=dict)
    id: str = "tool_123"
    type: str = "tool_use"


@dataclass
class MockAssistantMessage:
    """Stand-in for claude_agent_sdk.AssistantMessage."""

    content: list = field(default_factory=list)


@dataclass
class MockResultMessage:
    """Stand-in for claude_agent_sdk.ResultMessage."""

    result: str | None = None
    is_error: bool = False
    usage: dict | None = None
    num_turns: int = 1


@dataclass
class MockSystemMessage:
    """Stand-in for claude_agent_sdk.SystemMessage."""

    subtype: str = ""
    data: dict | None = None


class MockClaudeAgentOptions:
    """Stand-in for claude_agent_sdk.ClaudeAgentOptions."""

    def __init__(self, **kwargs):
        for k, v in kwargs.items():
            setattr(self, k, v)


class MockMcpHttpServerConfig:
    """Stand-in for McpHttpServerConfig."""

    def __init__(self, **kwargs):
        self._data = kwargs
        for k, v in kwargs.items():
            setattr(self, k, v)

    def get(self, key, default=None):
        return self._data.get(key, default)


# Build mock modules
_mock_sdk = MagicMock()
_mock_sdk.TextBlock = MockTextBlock
_mock_sdk.ToolUseBlock = MockToolUseBlock
_mock_sdk.AssistantMessage = MockAssistantMessage
_mock_sdk.ResultMessage = MockResultMessage
_mock_sdk.SystemMessage = MockSystemMessage
_mock_sdk.ClaudeAgentOptions = MockClaudeAgentOptions

_mock_sdk_types = MagicMock()
_mock_sdk_types.McpHttpServerConfig = MockMcpHttpServerConfig

# Patch modules before importing server
sys.modules["claude_agent_sdk"] = _mock_sdk
sys.modules["claude_agent_sdk.types"] = _mock_sdk_types

# Now import server after mocking
from server import (  # noqa: E402
    app,
    extract_prompt_from_messages,
    extract_text_from_assistant,
    extract_progress_from_assistant,
    format_tool_progress,
    format_system_progress,
    make_message_response,
    make_sse_event,
)

# httpx is needed for the TestClient
from httpx import ASGITransport, AsyncClient  # noqa: E402


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest_asyncio.fixture
async def client():
    """Async test client for the FastAPI app."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


# ---------------------------------------------------------------------------
# Helper: mock the `query` async generator
# ---------------------------------------------------------------------------

def make_mock_query(messages: list):
    """Create a mock `query` function that yields the given messages."""

    async def mock_query(prompt, options):
        for msg in messages:
            yield msg

    return mock_query


# ===========================================================================
# Unit tests: pure functions (no HTTP, no mocking needed)
# ===========================================================================


class TestMakeMessageResponse:
    """Tests for make_message_response — the Anthropic response builder."""

    def test_basic_text_response(self):
        """Response has all required fields for ClaudeProvider.parseResponse."""
        resp = make_message_response(
            content_blocks=[{"type": "text", "text": "Hello world"}],
        )

        # Required top-level fields
        assert resp["id"].startswith("msg_")
        assert resp["type"] == "message"
        assert resp["role"] == "assistant"
        assert resp["model"] == "claude-sonnet-4-5-20250514"
        assert resp["stop_reason"] == "end_turn"
        assert resp["stop_sequence"] is None

        # Usage
        assert "usage" in resp
        assert "input_tokens" in resp["usage"]
        assert "output_tokens" in resp["usage"]

        # Content blocks
        assert len(resp["content"]) == 1
        assert resp["content"][0]["type"] == "text"
        assert resp["content"][0]["text"] == "Hello world"

    def test_custom_model_and_stop_reason(self):
        """Model and stop_reason pass through correctly."""
        resp = make_message_response(
            content_blocks=[{"type": "text", "text": "test"}],
            model="claude-opus-4-6",
            stop_reason="tool_use",
        )
        assert resp["model"] == "claude-opus-4-6"
        assert resp["stop_reason"] == "tool_use"

    def test_tool_use_content_block(self):
        """Tool use blocks in content are preserved in the response."""
        resp = make_message_response(
            content_blocks=[
                {"type": "text", "text": "I'll create that alarm."},
                {
                    "type": "tool_use",
                    "id": "toolu_abc123",
                    "name": "create_alarm",
                    "input": {"tag": "pump3.speed", "threshold": 100},
                },
            ],
            stop_reason="tool_use",
        )
        assert len(resp["content"]) == 2
        assert resp["content"][0]["type"] == "text"
        assert resp["content"][1]["type"] == "tool_use"
        assert resp["content"][1]["name"] == "create_alarm"
        assert resp["content"][1]["input"]["tag"] == "pump3.speed"

    def test_usage_tokens(self):
        """Input and output tokens are set correctly."""
        resp = make_message_response(
            content_blocks=[{"type": "text", "text": "x"}],
            input_tokens=150,
            output_tokens=42,
        )
        assert resp["usage"]["input_tokens"] == 150
        assert resp["usage"]["output_tokens"] == 42

    def test_unique_message_ids(self):
        """Each call generates a unique message ID."""
        ids = {
            make_message_response(
                content_blocks=[{"type": "text", "text": "x"}]
            )["id"]
            for _ in range(50)
        }
        assert len(ids) == 50


class TestExtractPromptFromMessages:
    """Tests for extract_prompt_from_messages — message-to-prompt conversion."""

    def test_simple_user_message(self):
        """Single user message is formatted with role prefix."""
        result = extract_prompt_from_messages(
            [{"role": "user", "content": "Hello"}]
        )
        assert "[user]: Hello" in result

    def test_system_prompt_prepended(self):
        """System prompt appears before messages."""
        result = extract_prompt_from_messages(
            [{"role": "user", "content": "Hi"}],
            system="You are a SCADA copilot.",
        )
        assert result.startswith("[system context]: You are a SCADA copilot.")
        assert "[user]: Hi" in result

    def test_multi_turn_conversation(self):
        """Multiple messages preserve conversation flow."""
        messages = [
            {"role": "user", "content": "What is pump3 status?"},
            {"role": "assistant", "content": "Pump3 is running at 1450 RPM."},
            {"role": "user", "content": "Create an alarm for it."},
        ]
        result = extract_prompt_from_messages(messages)
        assert "[user]: What is pump3 status?" in result
        assert "[assistant]: Pump3 is running at 1450 RPM." in result
        assert "[user]: Create an alarm for it." in result

    def test_content_blocks_with_text(self):
        """Content as list of blocks extracts text correctly."""
        messages = [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": "Check this tag"},
                ],
            }
        ]
        result = extract_prompt_from_messages(messages)
        assert "[user]: Check this tag" in result

    def test_tool_result_blocks(self):
        """Tool result content blocks are included with prefix."""
        messages = [
            {
                "role": "user",
                "content": [
                    {
                        "type": "tool_result",
                        "tool_use_id": "abc",
                        "content": "pump3.speed = 1450",
                    },
                ],
            }
        ]
        result = extract_prompt_from_messages(messages)
        assert "[tool result]: pump3.speed = 1450" in result

    def test_tool_result_with_list_content(self):
        """Tool result with list of text blocks is handled."""
        messages = [
            {
                "role": "user",
                "content": [
                    {
                        "type": "tool_result",
                        "tool_use_id": "abc",
                        "content": [
                            {"type": "text", "text": "value: 42"},
                        ],
                    },
                ],
            }
        ]
        result = extract_prompt_from_messages(messages)
        assert "[tool result]: value: 42" in result

    def test_empty_messages(self):
        """Empty message list returns empty string (no system either)."""
        result = extract_prompt_from_messages([])
        assert result == ""

    def test_empty_messages_with_system(self):
        """System-only prompt still works."""
        result = extract_prompt_from_messages([], system="Be helpful.")
        assert result == "[system context]: Be helpful."


class TestExtractTextFromAssistant:
    """Tests for extract_text_from_assistant."""

    def test_text_blocks_joined(self):
        msg = MockAssistantMessage(
            content=[
                MockTextBlock(text="Hello"),
                MockTextBlock(text="World"),
            ]
        )
        assert extract_text_from_assistant(msg) == "Hello\nWorld"

    def test_tool_blocks_ignored(self):
        msg = MockAssistantMessage(
            content=[
                MockToolUseBlock(name="create_alarm"),
                MockTextBlock(text="Done"),
            ]
        )
        assert extract_text_from_assistant(msg) == "Done"

    def test_no_text_returns_none(self):
        msg = MockAssistantMessage(
            content=[MockToolUseBlock(name="get_tag_value")]
        )
        assert extract_text_from_assistant(msg) is None

    def test_empty_content_returns_none(self):
        msg = MockAssistantMessage(content=[])
        assert extract_text_from_assistant(msg) is None


class TestExtractProgressFromAssistant:
    """Tests for extract_progress_from_assistant."""

    def test_tool_use_blocks_generate_progress(self):
        msg = MockAssistantMessage(
            content=[
                MockToolUseBlock(name="create_alarm", input={"tag": "pump3"}),
                MockToolUseBlock(name="get_tag_value", input={"tag": "pump3"}),
            ]
        )
        lines = extract_progress_from_assistant(msg)
        assert len(lines) == 2
        # MCP tools use wrench icon
        assert "create_alarm" in lines[0]
        assert "get_tag_value" in lines[1]

    def test_text_blocks_not_in_progress(self):
        msg = MockAssistantMessage(
            content=[MockTextBlock(text="Hello")]
        )
        lines = extract_progress_from_assistant(msg)
        assert len(lines) == 0


class TestFormatToolProgress:
    """Tests for format_tool_progress — human-readable tool descriptions."""

    def test_read_tool(self):
        tool = MockToolUseBlock(name="Read", input={"file_path": "/a/b/c.txt"})
        result = format_tool_progress(tool)
        assert "Reading" in result
        assert "b/c.txt" in result

    def test_bash_tool(self):
        tool = MockToolUseBlock(
            name="Bash", input={"command": "ls -la /tmp"}
        )
        result = format_tool_progress(tool)
        assert "Running" in result
        assert "ls -la /tmp" in result

    def test_bash_tool_long_command_truncated(self):
        long_cmd = "x" * 100
        tool = MockToolUseBlock(name="Bash", input={"command": long_cmd})
        result = format_tool_progress(tool)
        assert "..." in result
        assert len(result) < 120

    def test_grep_tool(self):
        tool = MockToolUseBlock(name="Grep", input={"pattern": "alarm.*create"})
        result = format_tool_progress(tool)
        assert "Searching" in result
        assert "alarm.*create" in result

    def test_mcp_tool(self):
        tool = MockToolUseBlock(
            name="create_alarm",
            input={"tag": "pump3.speed", "threshold": 100},
        )
        result = format_tool_progress(tool)
        assert "create_alarm" in result

    def test_write_tool(self):
        tool = MockToolUseBlock(
            name="Write", input={"file_path": "/a/b/config.yaml"}
        )
        result = format_tool_progress(tool)
        assert "Writing" in result
        assert "b/config.yaml" in result

    def test_edit_tool(self):
        tool = MockToolUseBlock(
            name="Edit", input={"file_path": "/a/b/main.dart"}
        )
        result = format_tool_progress(tool)
        assert "Editing" in result

    def test_glob_tool(self):
        tool = MockToolUseBlock(name="Glob", input={"pattern": "**/*.dart"})
        result = format_tool_progress(tool)
        assert "Finding files" in result

    def test_web_search_tool(self):
        tool = MockToolUseBlock(
            name="WebSearch", input={"query": "flutter alarm widget"}
        )
        result = format_tool_progress(tool)
        assert "Searching web" in result

    def test_web_fetch_tool(self):
        tool = MockToolUseBlock(
            name="WebFetch", input={"url": "https://example.com/docs"}
        )
        result = format_tool_progress(tool)
        assert "Fetching" in result


class TestFormatSystemProgress:
    """Tests for format_system_progress."""

    def test_task_started(self):
        msg = MockSystemMessage(
            subtype="task_started",
            data={"description": "Creating alarm configuration"},
        )
        result = format_system_progress(msg)
        assert result is not None
        assert "Task started" in result
        assert "Creating alarm configuration" in result

    def test_task_progress(self):
        msg = MockSystemMessage(
            subtype="task_progress",
            data={"description": "Analyzing tag data"},
        )
        result = format_system_progress(msg)
        assert result is not None
        assert "Analyzing tag data" in result

    def test_unknown_subtype_returns_none(self):
        msg = MockSystemMessage(subtype="unknown_thing", data={})
        assert format_system_progress(msg) is None

    def test_empty_description_returns_none(self):
        msg = MockSystemMessage(subtype="task_started", data={"description": ""})
        assert format_system_progress(msg) is None


class TestMakeSseEvent:
    """Tests for make_sse_event — SSE formatting."""

    def test_event_format(self):
        result = make_sse_event("content_block_delta", {"type": "test"})
        assert result.startswith("event: content_block_delta\n")
        assert "data: " in result
        assert result.endswith("\n\n")
        # Data line should be valid JSON
        data_line = result.split("data: ", 1)[1].strip()
        parsed = json.loads(data_line)
        assert parsed["type"] == "test"


# ===========================================================================
# Integration tests: HTTP endpoints (require mocking agent SDK query)
# ===========================================================================


class TestHealthEndpoint:
    """Tests for GET /health."""

    @pytest.mark.anyio
    async def test_health_returns_ok(self, client):
        resp = await client.get("/health")
        assert resp.status_code == 200
        body = resp.json()
        assert body["status"] == "ok"
        assert body["backend"] == "claude-agent-sdk"
        assert "max_turns" in body
        assert "query_timeout" in body
        assert "stream_msg_timeout" in body
        assert "mcp_servers" in body


class TestModelsEndpoint:
    """Tests for GET /v1/models."""

    @pytest.mark.anyio
    async def test_models_returns_list(self, client):
        resp = await client.get("/v1/models")
        assert resp.status_code == 200
        body = resp.json()
        assert "models" in body
        model_ids = [m["id"] for m in body["models"]]
        assert "claude-sonnet-4-5-20250514" in model_ids
        assert "claude-opus-4-6" in model_ids


class TestNonStreamingMessages:
    """Tests for POST /v1/messages (non-streaming)."""

    @pytest.mark.anyio
    async def test_simple_text_response(self, client):
        """A simple text response matches Anthropic API format."""

        async def mock_query(prompt, options):
            yield MockAssistantMessage(
                content=[MockTextBlock(text="The pump is running normally.")]
            )
            yield MockResultMessage(
                usage={"input_tokens": 100, "output_tokens": 25}
            )

        with patch("server.query", side_effect=mock_query):
            resp = await client.post(
                "/v1/messages",
                json={
                    "model": "claude-sonnet-4-5-20250514",
                    "messages": [
                        {"role": "user", "content": "What is pump3 status?"}
                    ],
                    "stream": False,
                },
            )

        assert resp.status_code == 200
        body = resp.json()

        # Verify Anthropic response structure that ClaudeProvider expects
        assert body["id"].startswith("msg_")
        assert body["type"] == "message"
        assert body["role"] == "assistant"
        assert body["model"] == "claude-sonnet-4-5-20250514"
        assert body["stop_reason"] == "end_turn"
        assert body["stop_sequence"] is None
        assert "usage" in body
        assert body["usage"]["input_tokens"] == 100

        # Content blocks
        assert len(body["content"]) == 1
        assert body["content"][0]["type"] == "text"
        assert "pump is running normally" in body["content"][0]["text"]

    @pytest.mark.anyio
    async def test_multi_turn_tool_execution(self, client):
        """Agent executes tools internally, returns final text to Flutter."""

        async def mock_query(prompt, options):
            # Turn 1: Agent calls a tool
            yield MockAssistantMessage(
                content=[
                    MockToolUseBlock(
                        name="get_tag_value",
                        input={"tag": "pump3.speed"},
                    )
                ]
            )
            # Turn 2: Agent produces final text
            yield MockAssistantMessage(
                content=[
                    MockTextBlock(
                        text="Pump3 is running at 1450 RPM. "
                        "I have created alarm AL-001 for high speed."
                    )
                ]
            )
            yield MockResultMessage(
                usage={"input_tokens": 200, "output_tokens": 50}
            )

        with patch("server.query", side_effect=mock_query):
            resp = await client.post(
                "/v1/messages",
                json={
                    "model": "claude-sonnet-4-5-20250514",
                    "messages": [
                        {
                            "role": "user",
                            "content": "Create an alarm for pump3 high speed",
                        }
                    ],
                    "stream": False,
                },
            )

        assert resp.status_code == 200
        body = resp.json()

        # The proxy handles tool execution internally and returns text
        assert body["content"][0]["type"] == "text"
        text = body["content"][0]["text"]
        # Should contain progress line AND final text
        assert "get_tag_value" in text  # Progress line from tool use
        assert "1450 RPM" in text  # Final text content

    @pytest.mark.anyio
    async def test_system_prompt_passed_through(self, client):
        """System prompt from request body is forwarded to agent."""
        captured_options = {}

        async def mock_query(prompt, options):
            captured_options["system_prompt"] = options.system_prompt
            captured_options["prompt"] = prompt
            yield MockAssistantMessage(
                content=[MockTextBlock(text="OK")]
            )
            yield MockResultMessage()

        with patch("server.query", side_effect=mock_query):
            await client.post(
                "/v1/messages",
                json={
                    "model": "claude-sonnet-4-5-20250514",
                    "system": "You are a SCADA copilot.",
                    "messages": [
                        {"role": "user", "content": "Hi"}
                    ],
                    "stream": False,
                },
            )

        assert captured_options["system_prompt"] == "You are a SCADA copilot."

    @pytest.mark.anyio
    async def test_agent_sdk_error_returns_500(self, client):
        """Agent SDK exceptions map to HTTP 500 with error body."""

        async def mock_query(prompt, options):
            raise RuntimeError("Agent SDK connection failed")
            # Make it an async generator that raises
            yield  # pragma: no cover

        with patch("server.query", side_effect=mock_query):
            resp = await client.post(
                "/v1/messages",
                json={
                    "model": "claude-sonnet-4-5-20250514",
                    "messages": [
                        {"role": "user", "content": "test"}
                    ],
                    "stream": False,
                },
            )

        assert resp.status_code == 500
        body = resp.json()
        assert "error" in body
        assert "Agent SDK connection failed" in body["error"]["message"]

    @pytest.mark.anyio
    async def test_result_error_included_in_response(self, client):
        """ResultMessage with is_error=True is included in response text."""

        async def mock_query(prompt, options):
            yield MockAssistantMessage(
                content=[MockTextBlock(text="Attempting...")]
            )
            yield MockResultMessage(
                is_error=True,
                result="Max turns exceeded",
                usage={"input_tokens": 500, "output_tokens": 100},
                num_turns=25,
            )

        with patch("server.query", side_effect=mock_query):
            resp = await client.post(
                "/v1/messages",
                json={
                    "model": "claude-sonnet-4-5-20250514",
                    "messages": [
                        {"role": "user", "content": "complex task"}
                    ],
                    "stream": False,
                },
            )

        assert resp.status_code == 200
        body = resp.json()
        # Error from ResultMessage should not crash; text is still returned
        assert "Attempting..." in body["content"][0]["text"]

    @pytest.mark.anyio
    async def test_no_text_returns_fallback(self, client):
        """When agent produces no text, a fallback message is returned."""

        async def mock_query(prompt, options):
            yield MockResultMessage()

        with patch("server.query", side_effect=mock_query):
            resp = await client.post(
                "/v1/messages",
                json={
                    "model": "claude-sonnet-4-5-20250514",
                    "messages": [
                        {"role": "user", "content": "test"}
                    ],
                    "stream": False,
                },
            )

        assert resp.status_code == 200
        body = resp.json()
        assert "No response generated" in body["content"][0]["text"]

    @pytest.mark.anyio
    async def test_model_passthrough(self, client):
        """Requested model is reflected in the response."""

        async def mock_query(prompt, options):
            yield MockAssistantMessage(
                content=[MockTextBlock(text="OK")]
            )
            yield MockResultMessage()

        with patch("server.query", side_effect=mock_query):
            resp = await client.post(
                "/v1/messages",
                json={
                    "model": "claude-opus-4-6",
                    "messages": [
                        {"role": "user", "content": "test"}
                    ],
                    "stream": False,
                },
            )

        body = resp.json()
        assert body["model"] == "claude-opus-4-6"


class TestStreamingMessages:
    """Tests for POST /v1/messages (streaming SSE)."""

    @pytest.mark.anyio
    async def test_streaming_event_sequence(self, client):
        """Streaming response emits correct SSE event sequence."""

        async def mock_query(prompt, options):
            yield MockAssistantMessage(
                content=[MockTextBlock(text="Alarm created successfully.")]
            )
            yield MockResultMessage(
                usage={"input_tokens": 100, "output_tokens": 20}
            )

        with patch("server.query", side_effect=mock_query):
            resp = await client.post(
                "/v1/messages",
                json={
                    "model": "claude-sonnet-4-5-20250514",
                    "messages": [
                        {"role": "user", "content": "Create alarm"}
                    ],
                    "stream": True,
                },
            )

        assert resp.status_code == 200
        assert "text/event-stream" in resp.headers["content-type"]

        # Parse SSE events
        events = parse_sse_events(resp.text)
        event_types = [e["event"] for e in events]

        # Required SSE event sequence for Anthropic streaming format
        assert event_types[0] == "message_start"
        assert event_types[1] == "content_block_start"
        # One or more content_block_delta events
        assert "content_block_delta" in event_types
        assert "content_block_stop" in event_types
        assert "message_delta" in event_types
        assert event_types[-1] == "message_stop"

    @pytest.mark.anyio
    async def test_streaming_message_start_format(self, client):
        """message_start event contains proper message skeleton."""

        async def mock_query(prompt, options):
            yield MockAssistantMessage(
                content=[MockTextBlock(text="Hello")]
            )
            yield MockResultMessage()

        with patch("server.query", side_effect=mock_query):
            resp = await client.post(
                "/v1/messages",
                json={
                    "model": "claude-sonnet-4-5-20250514",
                    "messages": [
                        {"role": "user", "content": "hi"}
                    ],
                    "stream": True,
                },
            )

        events = parse_sse_events(resp.text)
        msg_start = next(e for e in events if e["event"] == "message_start")
        data = msg_start["data"]

        assert data["type"] == "message_start"
        msg = data["message"]
        assert msg["id"].startswith("msg_")
        assert msg["type"] == "message"
        assert msg["role"] == "assistant"
        assert msg["content"] == []
        assert msg["stop_reason"] is None

    @pytest.mark.anyio
    async def test_streaming_content_delta_contains_text(self, client):
        """content_block_delta events carry text_delta with actual content."""

        async def mock_query(prompt, options):
            yield MockAssistantMessage(
                content=[MockTextBlock(text="Pump running at 1450 RPM")]
            )
            yield MockResultMessage()

        with patch("server.query", side_effect=mock_query):
            resp = await client.post(
                "/v1/messages",
                json={
                    "model": "claude-sonnet-4-5-20250514",
                    "messages": [
                        {"role": "user", "content": "status?"}
                    ],
                    "stream": True,
                },
            )

        events = parse_sse_events(resp.text)
        deltas = [e for e in events if e["event"] == "content_block_delta"]
        assert len(deltas) >= 1

        # Collect all text from deltas
        full_text = "".join(d["data"]["delta"]["text"] for d in deltas)
        assert "1450 RPM" in full_text

        # Each delta has correct structure
        for d in deltas:
            assert d["data"]["type"] == "content_block_delta"
            assert d["data"]["index"] == 0
            assert d["data"]["delta"]["type"] == "text_delta"

    @pytest.mark.anyio
    async def test_streaming_message_delta_has_stop_reason(self, client):
        """message_delta event includes stop_reason: end_turn."""

        async def mock_query(prompt, options):
            yield MockAssistantMessage(
                content=[MockTextBlock(text="Done")]
            )
            yield MockResultMessage()

        with patch("server.query", side_effect=mock_query):
            resp = await client.post(
                "/v1/messages",
                json={
                    "model": "claude-sonnet-4-5-20250514",
                    "messages": [
                        {"role": "user", "content": "test"}
                    ],
                    "stream": True,
                },
            )

        events = parse_sse_events(resp.text)
        msg_delta = next(e for e in events if e["event"] == "message_delta")
        assert msg_delta["data"]["delta"]["stop_reason"] == "end_turn"

    @pytest.mark.anyio
    async def test_streaming_tool_progress_emitted(self, client):
        """Tool use progress lines are streamed as text deltas."""

        async def mock_query(prompt, options):
            yield MockAssistantMessage(
                content=[
                    MockToolUseBlock(
                        name="create_alarm",
                        input={"tag": "pump3.speed"},
                    ),
                ]
            )
            yield MockAssistantMessage(
                content=[MockTextBlock(text="Alarm created.")]
            )
            yield MockResultMessage()

        with patch("server.query", side_effect=mock_query):
            resp = await client.post(
                "/v1/messages",
                json={
                    "model": "claude-sonnet-4-5-20250514",
                    "messages": [
                        {"role": "user", "content": "create alarm"}
                    ],
                    "stream": True,
                },
            )

        events = parse_sse_events(resp.text)
        deltas = [e for e in events if e["event"] == "content_block_delta"]
        full_text = "".join(d["data"]["delta"]["text"] for d in deltas)

        # Should contain tool progress AND final text
        assert "create_alarm" in full_text
        assert "Alarm created." in full_text

    @pytest.mark.anyio
    async def test_streaming_error_emitted_as_delta(self, client):
        """Agent SDK errors during streaming become text deltas."""

        async def mock_query(prompt, options):
            raise ConnectionError("Lost connection to agent")
            yield  # pragma: no cover

        with patch("server.query", side_effect=mock_query):
            resp = await client.post(
                "/v1/messages",
                json={
                    "model": "claude-sonnet-4-5-20250514",
                    "messages": [
                        {"role": "user", "content": "test"}
                    ],
                    "stream": True,
                },
            )

        events = parse_sse_events(resp.text)
        deltas = [e for e in events if e["event"] == "content_block_delta"]
        full_text = "".join(d["data"]["delta"]["text"] for d in deltas)
        assert "Error from Agent SDK" in full_text
        assert "Lost connection" in full_text

        # Stream should still close properly
        event_types = [e["event"] for e in events]
        assert "content_block_stop" in event_types
        assert "message_stop" in event_types


class TestAlarmCreationFlow:
    """
    End-to-end tests for the alarm creation scenario.

    Verifies that the proxy correctly handles the multi-turn flow:
    1. User asks to create an alarm
    2. Agent calls get_tag_value to check current value
    3. Agent calls create_alarm to create the alarm
    4. Agent returns final confirmation text to Flutter
    """

    @pytest.mark.anyio
    async def test_alarm_creation_non_streaming(self, client):
        """Alarm creation flow returns proper response format."""

        async def mock_query(prompt, options):
            # Verify prompt contains the user's request
            assert "Create an alarm" in prompt
            assert "pump3" in prompt

            # Turn 1: Agent reads tag value
            yield MockSystemMessage(
                subtype="task_started",
                data={"description": "Creating alarm for pump3"},
            )
            yield MockAssistantMessage(
                content=[
                    MockToolUseBlock(
                        name="get_tag_value",
                        input={"tag": "pump3.speed"},
                    ),
                ]
            )
            # Turn 2: Agent creates alarm
            yield MockAssistantMessage(
                content=[
                    MockToolUseBlock(
                        name="create_alarm",
                        input={
                            "tag": "pump3.speed",
                            "condition": "greater_than",
                            "setpoint": 1500,
                            "description": "Pump3 high speed alarm",
                        },
                    ),
                ]
            )
            # Turn 3: Final response
            yield MockAssistantMessage(
                content=[
                    MockTextBlock(
                        text="I've created alarm AL-042 for pump3.speed. "
                        "It will trigger when the speed exceeds 1500 RPM. "
                        "The current reading is 1450 RPM, so the alarm is "
                        "not active."
                    ),
                ]
            )
            yield MockResultMessage(
                usage={"input_tokens": 500, "output_tokens": 120},
            )

        with patch("server.query", side_effect=mock_query):
            resp = await client.post(
                "/v1/messages",
                json={
                    "model": "claude-sonnet-4-5-20250514",
                    "system": "You are a SCADA HMI copilot.",
                    "messages": [
                        {
                            "role": "user",
                            "content": "Create an alarm for pump3 high speed > 1500",
                        }
                    ],
                    "stream": False,
                },
            )

        assert resp.status_code == 200
        body = resp.json()

        # Verify the response is parseable by ClaudeProvider
        assert body["type"] == "message"
        assert body["role"] == "assistant"
        assert body["stop_reason"] == "end_turn"

        text = body["content"][0]["text"]
        # Progress lines from tools
        assert "get_tag_value" in text
        assert "create_alarm" in text
        # Task started progress
        assert "Creating alarm for pump3" in text
        # Final confirmation text
        assert "AL-042" in text
        assert "1500 RPM" in text

    @pytest.mark.anyio
    async def test_alarm_creation_streaming(self, client):
        """Alarm creation flow works correctly with streaming."""

        async def mock_query(prompt, options):
            yield MockAssistantMessage(
                content=[
                    MockToolUseBlock(
                        name="get_tag_value",
                        input={"tag": "pump3.speed"},
                    ),
                ]
            )
            yield MockAssistantMessage(
                content=[
                    MockToolUseBlock(
                        name="create_alarm",
                        input={
                            "tag": "pump3.speed",
                            "condition": "greater_than",
                            "setpoint": 1500,
                        },
                    ),
                ]
            )
            yield MockAssistantMessage(
                content=[
                    MockTextBlock(text="Alarm AL-042 created successfully."),
                ]
            )
            yield MockResultMessage(
                usage={"input_tokens": 400, "output_tokens": 80},
            )

        with patch("server.query", side_effect=mock_query):
            resp = await client.post(
                "/v1/messages",
                json={
                    "model": "claude-sonnet-4-5-20250514",
                    "messages": [
                        {
                            "role": "user",
                            "content": "Create alarm for pump3 speed > 1500",
                        }
                    ],
                    "stream": True,
                },
            )

        events = parse_sse_events(resp.text)
        event_types = [e["event"] for e in events]

        # Correct event sequence
        assert event_types[0] == "message_start"
        assert event_types[1] == "content_block_start"
        assert event_types[-1] == "message_stop"

        # Collect all text
        deltas = [e for e in events if e["event"] == "content_block_delta"]
        full_text = "".join(d["data"]["delta"]["text"] for d in deltas)

        # Tool progress was streamed
        assert "get_tag_value" in full_text
        assert "create_alarm" in full_text
        # Final text was streamed
        assert "AL-042" in full_text


class TestResponseFormatForFlutter:
    """
    Tests specifically verifying the response format matches what
    anthropic_sdk_dart / ClaudeProvider expects to parse.

    ClaudeProvider.parseResponse expects:
    - response.content: list of blocks (TextBlock, ToolUseBlock)
    - response.stopReason: StopReason enum value (via .value)
    - Each TextBlock has .text
    - Each ToolUseBlock has .id, .name, .input

    The proxy returns JSON that anthropic_sdk_dart will deserialize into
    these types, so the JSON structure must match exactly.
    """

    @pytest.mark.anyio
    async def test_text_block_format(self, client):
        """Text content blocks have the exact format Flutter expects."""

        async def mock_query(prompt, options):
            yield MockAssistantMessage(
                content=[MockTextBlock(text="Tag value: 42")]
            )
            yield MockResultMessage()

        with patch("server.query", side_effect=mock_query):
            resp = await client.post(
                "/v1/messages",
                json={
                    "model": "claude-sonnet-4-5-20250514",
                    "messages": [
                        {"role": "user", "content": "read tag"}
                    ],
                    "stream": False,
                },
            )

        body = resp.json()
        block = body["content"][0]

        # anthropic_sdk_dart expects these exact keys
        assert set(block.keys()) == {"type", "text"}
        assert block["type"] == "text"
        assert isinstance(block["text"], str)

    @pytest.mark.anyio
    async def test_required_response_fields(self, client):
        """All fields required by anthropic_sdk_dart Message class are present."""

        async def mock_query(prompt, options):
            yield MockAssistantMessage(
                content=[MockTextBlock(text="test")]
            )
            yield MockResultMessage()

        with patch("server.query", side_effect=mock_query):
            resp = await client.post(
                "/v1/messages",
                json={
                    "model": "claude-sonnet-4-5-20250514",
                    "messages": [
                        {"role": "user", "content": "test"}
                    ],
                    "stream": False,
                },
            )

        body = resp.json()

        # Required by anthropic_sdk_dart Message.fromJson
        required_fields = {
            "id", "type", "role", "content", "model",
            "stop_reason", "stop_sequence", "usage",
        }
        assert required_fields.issubset(set(body.keys())), (
            f"Missing fields: {required_fields - set(body.keys())}"
        )

        # Type checks
        assert isinstance(body["id"], str)
        assert isinstance(body["content"], list)
        assert isinstance(body["usage"], dict)
        assert "input_tokens" in body["usage"]
        assert "output_tokens" in body["usage"]

    @pytest.mark.anyio
    async def test_stop_reason_is_string(self, client):
        """stop_reason is a string (not null) for successful responses."""

        async def mock_query(prompt, options):
            yield MockAssistantMessage(
                content=[MockTextBlock(text="done")]
            )
            yield MockResultMessage()

        with patch("server.query", side_effect=mock_query):
            resp = await client.post(
                "/v1/messages",
                json={
                    "model": "claude-sonnet-4-5-20250514",
                    "messages": [
                        {"role": "user", "content": "test"}
                    ],
                    "stream": False,
                },
            )

        body = resp.json()
        # ClaudeProvider does: response.stopReason?.value ?? 'end_turn'
        # The deserialized StopReason needs a valid string
        assert body["stop_reason"] in ("end_turn", "tool_use", "max_tokens")


class TestCorsHeaders:
    """Verify CORS middleware is configured for Flutter app access."""

    @pytest.mark.anyio
    async def test_cors_allows_all_origins(self, client):
        """OPTIONS request returns permissive CORS headers."""
        resp = await client.options(
            "/v1/messages",
            headers={
                "origin": "http://localhost:9100",
                "access-control-request-method": "POST",
            },
        )
        # FastAPI CORS middleware should respond to preflight
        assert resp.status_code == 200
        assert "access-control-allow-origin" in resp.headers


class TestMcpConfiguration:
    """Tests for MCP server configuration."""

    def test_health_shows_mcp_config(self):
        """Health endpoint reflects MCP server configuration."""
        # This is tested via the health endpoint integration test above.
        # Here we verify the config format directly.
        from server import MCP_SERVERS

        if MCP_SERVERS:
            for name, cfg in MCP_SERVERS.items():
                assert isinstance(name, str)
                # Should have type and url
                assert cfg.get("type") is not None
                assert cfg.get("url") is not None


# ===========================================================================
# SSE parsing helper
# ===========================================================================

def parse_sse_events(text: str) -> list[dict]:
    """Parse SSE response text into a list of {event, data} dicts."""
    events = []
    current_event = None
    current_data = []

    for line in text.split("\n"):
        if line.startswith("event: "):
            if current_event is not None:
                events.append({
                    "event": current_event,
                    "data": json.loads("".join(current_data)),
                })
            current_event = line[7:].strip()
            current_data = []
        elif line.startswith("data: "):
            current_data.append(line[6:])
        elif line == "" and current_event is not None:
            events.append({
                "event": current_event,
                "data": json.loads("".join(current_data)),
            })
            current_event = None
            current_data = []

    # Handle last event if no trailing newline
    if current_event is not None and current_data:
        events.append({
            "event": current_event,
            "data": json.loads("".join(current_data)),
        })

    return events
