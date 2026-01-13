import asyncio
import os
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

from service_test_utils import load_service_module, make_mcp_stubs


MCP_PATH = os.path.join(
    os.path.dirname(__file__),
    "..",
    "..",
    "services",
    "mcp-memory-bridge",
    "server.py",
)


class McpMemoryBridgeTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.mind_path = os.path.join(self.temp_dir.name, ".claude-mind")
        os.makedirs(self.mind_path, exist_ok=True)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_append_and_search_files(self):
        with load_service_module(MCP_PATH, env={"SAMARA_MIND_PATH": self.mind_path}, stubs=make_mcp_stubs()) as mcp:
            memory_dir = Path(self.mind_path) / "memory"
            memory_dir.mkdir(parents=True, exist_ok=True)
            target_file = memory_dir / "observations.md"
            target_file.write_text("Line one\nLine two about forests\nLine three\n")

            results = mcp.search_files(memory_dir, "forests")

        self.assertEqual(len(results), 1)
        self.assertIn("forests", results[0]["context"])
        self.assertEqual(results[0]["file"], "memory/observations.md")

    def test_call_tool_appends_episode(self):
        with load_service_module(MCP_PATH, env={"SAMARA_MIND_PATH": self.mind_path}, stubs=make_mcp_stubs()) as mcp:
            result = asyncio.run(mcp.call_tool("append_episode", {"content": "Test entry"}))
            episode_path = mcp.get_today_episode_path()

        self.assertTrue(episode_path.exists())
        content = episode_path.read_text()
        self.assertIn("Test entry", content)
        self.assertEqual(result[0].text, "Appended to today's episode")

    def test_call_tool_adds_observation(self):
        with load_service_module(MCP_PATH, env={"SAMARA_MIND_PATH": self.mind_path}, stubs=make_mcp_stubs()) as mcp:
            result = asyncio.run(mcp.call_tool("add_observation", {"content": "Noted pattern"}))
            obs_path = Path(self.mind_path) / "memory" / "observations.md"

        self.assertTrue(obs_path.exists())
        self.assertIn("Noted pattern", obs_path.read_text())
        self.assertEqual(result[0].text, "Added observation")

    def test_call_tool_log_exchange(self):
        with load_service_module(MCP_PATH, env={"SAMARA_MIND_PATH": self.mind_path}, stubs=make_mcp_stubs()) as mcp:
            result = asyncio.run(
                mcp.call_tool(
                    "log_exchange",
                    {
                        "source": "web",
                        "user_message": "Hello there",
                        "assistant_response": "Hi!",
                        "topics": ["greeting"],
                    },
                )
            )
            episode_path = mcp.get_today_episode_path()

        content = episode_path.read_text()
        self.assertIn("Exchange (web)", content)
        self.assertIn("Hello there", content)
        self.assertIn("greeting", content)
        self.assertIn("Logged exchange", result[0].text)

    def test_call_tool_add_learning_and_decision_and_question(self):
        with load_service_module(MCP_PATH, env={"SAMARA_MIND_PATH": self.mind_path}, stubs=make_mcp_stubs()) as mcp:
            learn_result = asyncio.run(
                mcp.call_tool("add_learning", {"title": "Learned", "content": "Detail", "source": "lab"})
            )
            decision_result = asyncio.run(
                mcp.call_tool(
                    "add_decision",
                    {"decision": "Adopt", "rationale": "Works", "alternatives": "Skip"},
                )
            )
            question_result = asyncio.run(
                mcp.call_tool("add_question", {"question": "Why?", "context": "Testing"})
            )

        memory_dir = Path(self.mind_path) / "memory"
        self.assertIn("Learned", (memory_dir / "learnings.md").read_text())
        self.assertIn("Adopt", (memory_dir / "decisions.md").read_text())
        self.assertIn("Why?", (memory_dir / "questions.md").read_text())
        self.assertIn("Added learning", learn_result[0].text)
        self.assertIn("Recorded decision", decision_result[0].text)
        self.assertIn("Added question", question_result[0].text)

    def test_call_tool_search_memory_no_results(self):
        with load_service_module(MCP_PATH, env={"SAMARA_MIND_PATH": self.mind_path}, stubs=make_mcp_stubs()) as mcp:
            result = asyncio.run(mcp.call_tool("search_memory", {"query": "nothing"}))

        self.assertIn("No results found", result[0].text)

    def test_call_tool_get_recent_context(self):
        with load_service_module(MCP_PATH, env={"SAMARA_MIND_PATH": self.mind_path}, stubs=make_mcp_stubs()) as mcp:
            episode_path = mcp.get_today_episode_path()
            episode_path.parent.mkdir(parents=True, exist_ok=True)
            episode_path.write_text("Line 1\nLine 2\n")
            memory_dir = Path(self.mind_path) / "memory"
            memory_dir.mkdir(parents=True, exist_ok=True)
            (memory_dir / "learnings.md").write_text("Learning 1\nLearning 2\n")
            result = asyncio.run(mcp.call_tool("get_recent_context", {"days": 1}))

        self.assertIn("Recent Episodes", result[0].text)
        self.assertIn("Recent Learnings", result[0].text)

    def test_call_tool_get_identity_and_about(self):
        mind_dir = Path(self.mind_path)
        mind_dir.mkdir(parents=True, exist_ok=True)
        (mind_dir / "identity.md").write_text("Identity text")
        (mind_dir / "goals.md").write_text("Goals text")
        memory_dir = mind_dir / "memory"
        memory_dir.mkdir(parents=True, exist_ok=True)
        (memory_dir / "about-collaborator.md").write_text("About file")

        with load_service_module(MCP_PATH, env={"SAMARA_MIND_PATH": self.mind_path}, stubs=make_mcp_stubs()) as mcp:
            identity_result = asyncio.run(mcp.call_tool("get_identity", {}))
            about_result = asyncio.run(mcp.call_tool("get_about_collaborator", {}))

        self.assertIn("Identity text", identity_result[0].text)
        self.assertIn("Goals text", identity_result[0].text)
        self.assertIn("About file", about_result[0].text)

    def test_call_tool_unknown(self):
        with load_service_module(MCP_PATH, env={"SAMARA_MIND_PATH": self.mind_path}, stubs=make_mcp_stubs()) as mcp:
            result = asyncio.run(mcp.call_tool("missing", {}))

        self.assertIn("Unknown tool", result[0].text)

    def test_resolve_mind_dir_and_file_helpers(self):
        with load_service_module(MCP_PATH, env={"SAMARA_MIND_PATH": self.mind_path}, stubs=make_mcp_stubs()) as mcp:
            with mock.patch.dict(os.environ, {"HOME": "/tmp/home"}, clear=True):
                self.assertEqual(mcp.resolve_mind_dir(), Path("/tmp/home/.claude-mind"))

            self.assertIsNone(mcp.read_file_safe(Path(self.mind_path) / "missing.md"))
            target = Path(self.mind_path) / "memory" / "notes.md"
            mcp.append_to_file(target, "Line 1\n")
            mcp.append_to_file(target, "Line 2\n")
            self.assertIn("Line 2", target.read_text())

    def test_search_memory_returns_results(self):
        with load_service_module(MCP_PATH, env={"SAMARA_MIND_PATH": self.mind_path}, stubs=make_mcp_stubs()) as mcp:
            memory_dir = Path(self.mind_path) / "memory"
            memory_dir.mkdir(parents=True, exist_ok=True)
            (memory_dir / "notes.md").write_text("alpha\nbeta\n")
            result = asyncio.run(mcp.call_tool("search_memory", {"query": "beta"}))

        self.assertIn("Found 1 matches", result[0].text)

    def test_call_tool_get_about_collaborator_missing(self):
        with load_service_module(MCP_PATH, env={"SAMARA_MIND_PATH": self.mind_path}, stubs=make_mcp_stubs()) as mcp:
            result = asyncio.run(mcp.call_tool("get_about_collaborator", {}))

        self.assertIn("No collaborator file found", result[0].text)

    def test_main_http_and_stdio_branches(self):
        stubs = make_mcp_stubs()
        uvicorn_module = types.ModuleType("uvicorn")

        class Config:
            def __init__(self, app, host=None, port=None):
                self.app = app
                self.host = host
                self.port = port

        class Server:
            def __init__(self, config):
                self.config = config

            async def serve(self):
                async def receive():
                    return {}

                async def send(message):
                    return None

                await self.config.app({"path": "/health", "method": "GET"}, receive, send)
                await self.config.app({"path": "/messages", "method": "POST"}, receive, send)
                await self.config.app({"path": "/sse", "method": "GET"}, receive, send)
                await self.config.app({"path": "/unknown", "method": "GET"}, receive, send)

        uvicorn_module.Config = Config
        uvicorn_module.Server = Server
        stubs["uvicorn"] = uvicorn_module

        with load_service_module(MCP_PATH, env={"SAMARA_MIND_PATH": self.mind_path}, stubs=stubs) as mcp:
            with mock.patch.object(sys, "argv", ["server.py", "--http", "--port", "9000"]):
                asyncio.run(mcp.main())
            with mock.patch.object(sys, "argv", ["server.py"]):
                asyncio.run(mcp.main())
