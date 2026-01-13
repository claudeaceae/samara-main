import contextlib
import importlib.util
import os
import sys
import types
import uuid


@contextlib.contextmanager
def temp_environ(env):
    original = os.environ.copy()
    try:
        if env:
            for key, value in env.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value
        yield
    finally:
        os.environ.clear()
        os.environ.update(original)


@contextlib.contextmanager
def stub_modules(stubs):
    if not stubs:
        yield
        return

    original = {}
    try:
        for name, module in stubs.items():
            original[name] = sys.modules.get(name)
            sys.modules[name] = module
        yield
    finally:
        for name, prior in original.items():
            if prior is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = prior


@contextlib.contextmanager
def load_service_module(path, env=None, stubs=None, name=None):
    module_name = name or f"service_{uuid.uuid4().hex}"
    with temp_environ(env), stub_modules(stubs):
        spec = importlib.util.spec_from_file_location(module_name, path)
        module = importlib.util.module_from_spec(spec)
        sys.modules[module_name] = module
        try:
            spec.loader.exec_module(module)
            yield module
        finally:
            sys.modules.pop(module_name, None)


def make_fastapi_stubs():
    fastapi_module = types.ModuleType("fastapi")
    responses_module = types.ModuleType("fastapi.responses")
    uvicorn_module = types.ModuleType("uvicorn")

    class HTTPException(Exception):
        def __init__(self, status_code=None, detail=None):
            super().__init__(detail)
            self.status_code = status_code
            self.detail = detail

    class Request:
        pass

    def Header(default=None):
        return default

    class JSONResponse:
        def __init__(self, content):
            self.content = content

    class FastAPI:
        def __init__(self, *args, **kwargs):
            pass

        def post(self, *args, **kwargs):
            def decorator(func):
                return func
            return decorator

        def get(self, *args, **kwargs):
            def decorator(func):
                return func
            return decorator

    def run(*args, **kwargs):
        return None

    fastapi_module.FastAPI = FastAPI
    fastapi_module.Request = Request
    fastapi_module.HTTPException = HTTPException
    fastapi_module.Header = Header
    responses_module.JSONResponse = JSONResponse
    uvicorn_module.run = run

    return {
        "fastapi": fastapi_module,
        "fastapi.responses": responses_module,
        "uvicorn": uvicorn_module,
    }


def make_mcp_stubs():
    mcp_module = types.ModuleType("mcp")
    server_module = types.ModuleType("mcp.server")
    stdio_module = types.ModuleType("mcp.server.stdio")
    sse_module = types.ModuleType("mcp.server.sse")
    types_module = types.ModuleType("mcp.types")

    class Server:
        def __init__(self, name):
            self.name = name

        def list_tools(self):
            def decorator(func):
                return func
            return decorator

        def call_tool(self):
            def decorator(func):
                return func
            return decorator

        def create_initialization_options(self):
            return {}

        async def run(self, *args, **kwargs):
            return None

    class _AsyncCM:
        async def __aenter__(self):
            return (None, None)

        async def __aexit__(self, exc_type, exc, tb):
            return False

    def stdio_server():
        return _AsyncCM()

    class _SseStreamsCM:
        async def __aenter__(self):
            return (None, None)

        async def __aexit__(self, exc_type, exc, tb):
            return False

    class SseServerTransport:
        def __init__(self, *args, **kwargs):
            pass

        def connect_sse(self, scope, receive, send):
            return _SseStreamsCM()

        async def handle_post_message(self, scope, receive, send):
            return None

    class Tool:
        def __init__(self, name, description, inputSchema):
            self.name = name
            self.description = description
            self.inputSchema = inputSchema

    class TextContent:
        def __init__(self, type, text):
            self.type = type
            self.text = text

    server_module.Server = Server
    stdio_module.stdio_server = stdio_server
    sse_module.SseServerTransport = SseServerTransport
    types_module.Tool = Tool
    types_module.TextContent = TextContent

    return {
        "mcp": mcp_module,
        "mcp.server": server_module,
        "mcp.server.stdio": stdio_module,
        "mcp.server.sse": sse_module,
        "mcp.types": types_module,
    }
