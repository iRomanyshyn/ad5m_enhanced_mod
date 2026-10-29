#!/usr/bin/env python3
"""Exercise first-claim branches in the pinned Moonraker authorization code.

This is deliberately a component-contract test, not a Moonraker service test.
It imports the pinned authorization.py supplied by MOONRAKER_SOURCE_DIR and
replaces only its database, event-loop, crypto and HTTP boundary dependencies.
No listener, WebSocket, browser, target Python package, network request, or
printer is started.  The test therefore proves the source component's branch
behaviour and persistent user/API-key state, but not HTTP/Tornado integration
or production cryptography.
"""

from __future__ import annotations

import asyncio
import dataclasses
from enum import IntFlag, auto
import hashlib
import hmac
import importlib.util
import json
import os
from pathlib import Path
import sys
from types import ModuleType
from typing import Any


sys.dont_write_bytecode = True


class HarnessError(RuntimeError):
    """A source-lock or authorization contract invariant failed."""


class FakeHTTPError(Exception):
    """Small substitute for Tornado's HTTPError used by the target module."""

    def __init__(self, status_code: int = 500, log_message: str = "") -> None:
        super().__init__(log_message)
        self.status_code = status_code


class FakeMoonrakerError(Exception):
    """Callable exception class matching the server.error interface."""

    def __init__(self, message: str, status_code: int = 500) -> None:
        super().__init__(message)
        self.status_code = status_code


class FakeSigner:
    """Deterministic test-only signing boundary; this is not Ed25519."""

    def __init__(self, seed: bytes | None = None) -> None:
        self.seed = seed if seed is not None else b"m" * 32
        if len(self.seed) != 32:
            raise ValueError("fake signer seed must be 32 bytes")

    @property
    def vk(self) -> bytes:
        return self.seed

    def hex_seed(self) -> bytes:
        return self.seed.hex().encode()

    def signature(self, message: bytes) -> bytes:
        return hmac.new(self.seed, message, hashlib.sha256).digest()


class FakeVerifier:
    """Counterpart to FakeSigner for exercising target JWT control flow."""

    def __init__(self, key_hex: bytes) -> None:
        self.key = bytes.fromhex(key_hex.decode())

    def verify(self, signed_message: bytes) -> None:
        signature, message = signed_message[:32], signed_message[32:]
        expected = hmac.new(self.key, message, hashlib.sha256).digest()
        if not hmac.compare_digest(signature, expected):
            raise ValueError("invalid fake signature")


class RequestType(IntFlag):
    GET = auto()
    POST = auto()
    DELETE = auto()

    @classmethod
    def all(cls) -> "RequestType":
        return cls.GET | cls.POST | cls.DELETE


class TransportType(IntFlag):
    HTTP = auto()
    WEBSOCKET = auto()


class SqlTableDefinition:
    """Minimal base so authorization.py can declare UserSqlDefinition."""


@dataclasses.dataclass
class UserInfo:
    username: str
    password: str
    created_on: float = 0.0
    salt: str = ""
    source: str = "moonraker"
    jwt_secret: str | None = None
    jwk_id: str | None = None
    groups: list[str] = dataclasses.field(default_factory=lambda: ["admin"])

    def as_tuple(self) -> tuple[Any, ...]:
        return dataclasses.astuple(self)


class FakeTimer:
    def start(self, delay: float) -> None:
        self.delay = delay


class FakeEventLoop:
    def register_timer(self, callback: object) -> FakeTimer:
        self.timer_callback = callback
        return FakeTimer()

    def delay_callback(self, delay: float, callback: object, *args: object) -> None:
        self.delayed = (delay, callback, args)


class FakeWebsockets:
    def register_notification(self, *args: object, **kwargs: object) -> None:
        self.notifications = getattr(self, "notifications", []) + [(args, kwargs)]


class FakeRow(dict[str, Any]):
    """Mapping/sequence hybrid matching the database rows Moonraker reads."""

    def __getitem__(self, key: str | int) -> Any:
        if isinstance(key, int):
            return tuple(self.values())[key]
        return super().__getitem__(key)


class FakeCursor:
    def __init__(self, rows: list[FakeRow]) -> None:
        self.rows = rows

    async def fetchall(self) -> list[FakeRow]:
        return self.rows


class FakeUserTable:
    fields = (
        "username", "password", "created_on", "salt", "source", "jwt_secret",
        "jwk_id", "groups",
    )

    def __init__(self) -> None:
        self.rows: dict[str, FakeRow] = {}

    async def __aenter__(self) -> "FakeUserTable":
        return self

    async def __aexit__(self, exc_type: object, exc: object, tb: object) -> None:
        return None

    async def execute(self, statement: str, values: tuple[Any, ...] | None = None) -> FakeCursor | None:
        if statement.startswith("SELECT"):
            return FakeCursor(list(self.rows.values()))
        if statement.startswith("DELETE FROM authorized_users") and "WHERE" not in statement:
            self.rows.clear()
        elif statement.startswith("DELETE FROM authorized_users") and values is not None:
            self.rows.pop(str(values[0]), None)
        elif statement.startswith("REPLACE INTO authorized_users") and values is not None:
            self.rows[str(values[0])] = FakeRow(zip(self.fields, values, strict=True))
        return None

    async def executemany(self, statement: str, values: list[tuple[Any, ...]]) -> None:
        if not statement.startswith("INSERT INTO authorized_users"):
            raise HarnessError(f"unexpected SQL batch statement: {statement}")
        for row in values:
            self.rows[str(row[0])] = FakeRow(zip(self.fields, row, strict=True))


class FakeDatabase:
    def __init__(self) -> None:
        self.table = FakeUserTable()

    def register_table(self, definition: object) -> FakeUserTable:
        self.definition = definition
        return self.table


class FakeServer:
    error = FakeMoonrakerError

    def __init__(self, database: FakeDatabase) -> None:
        self.database = database
        self.event_loop = FakeEventLoop()
        self.websockets = FakeWebsockets()

    def add_warning(self, message: str) -> None:
        self.warnings = getattr(self, "warnings", []) + [message]

    def lookup_component(self, name: str) -> object:
        if name == "database":
            return self.database
        if name == "websockets":
            return self.websockets
        raise HarnessError(f"unexpected component lookup: {name}")

    def get_host_info(self) -> dict[str, object]:
        return {"hostname": "ad5m-test", "port": 7125}

    def get_event_loop(self) -> FakeEventLoop:
        return self.event_loop

    def register_endpoint(self, *args: object, **kwargs: object) -> None:
        self.endpoints = getattr(self, "endpoints", []) + [(args, kwargs)]

    def send_event(self, *args: object) -> None:
        self.events = getattr(self, "events", []) + [args]


class FakeConfig:
    def __init__(self, server: FakeServer) -> None:
        self.server = server

    def get_server(self) -> FakeServer:
        return self.server

    @staticmethod
    def getint(name: str, default: int | None = None, **kwargs: object) -> int | None:
        return default

    @staticmethod
    def getboolean(name: str, default: bool = False) -> bool:
        return {"force_logins": True, "enable_api_key": True}.get(name, default)

    @staticmethod
    def get(name: str, default: str = "") -> str:
        return default

    @staticmethod
    def has_section(name: str) -> bool:
        return False

    @staticmethod
    def getlist(name: str, default: list[str] | None = None) -> list[str]:
        return {"trusted_clients": ["0.0.0.0/0"], "cors_domains": ["*"]}.get(
            name, default or []
        )


class FakeRequest:
    def __init__(self, remote_ip: str, headers: dict[str, str] | None = None) -> None:
        self.method = "GET"
        self.remote_ip = remote_ip
        self.headers = headers or {}
        self.arguments: dict[str, list[bytes]] = {}
        self.query_arguments: dict[str, list[bytes]] = {}


class FakeWebRequest:
    def __init__(self, request_type: RequestType, values: dict[str, str]) -> None:
        self.request_type = request_type
        self.values = values

    def get_request_type(self) -> RequestType:
        return self.request_type

    def get_str(self, name: str, default: str | None = None) -> str:
        value = self.values.get(name, default)
        if value is None:
            raise HarnessError(f"missing request value: {name}")
        return value

    @staticmethod
    def get_client_connection() -> None:
        return None


def fail(message: str) -> None:
    raise HarnessError(message)


def load_fixture(repo_root: Path) -> dict[str, str]:
    fixture_path = repo_root / "tests/fixtures/moonraker-authorization/first-claim.json"
    try:
        data = json.loads(fixture_path.read_text(encoding="utf-8"))
        source = data["moonraker"]
    except (OSError, KeyError, TypeError, json.JSONDecodeError) as error:
        fail(f"cannot read Moonraker authorization fixture: {error}")
    if not isinstance(source, dict) or not all(
        isinstance(source.get(field), str) for field in ("commit", "authorization_sha256")
    ):
        fail("Moonraker authorization fixture has invalid source identity")
    return {"commit": source["commit"], "authorization_sha256": source["authorization_sha256"]}


def verify_source(repo_root: Path, source: Path, lock: dict[str, str]) -> Path:
    module_path = source / "moonraker/components/authorization.py"
    if not module_path.is_file():
        fail(f"missing Moonraker authorization module: {module_path}")
    actual_hash = hashlib.sha256(module_path.read_bytes()).hexdigest()
    if actual_hash != lock["authorization_sha256"]:
        fail(
            "Moonraker authorization.py checksum mismatch: "
            f"expected {lock['authorization_sha256']}, found {actual_hash}"
        )
    package_file = repo_root / "build_scripts/buildroot/package/moonraker/moonraker.mk"
    if not package_file.is_file():
        fail(f"missing Moonraker package definition: {package_file}")
    version_line = f"MOONRAKER_VERSION = {lock['commit']}"
    if version_line not in package_file.read_text(encoding="utf-8").splitlines():
        fail(f"package definition does not pin fixture commit {lock['commit']}")
    return module_path


def install_boundary_fakes() -> None:
    tornado = ModuleType("tornado")
    tornado_web = ModuleType("tornado.web")
    tornado_web.HTTPError = FakeHTTPError
    tornado.web = tornado_web  # type: ignore[attr-defined]
    libnacl = ModuleType("libnacl")
    libnacl_sign = ModuleType("libnacl.sign")
    libnacl_sign.Signer = FakeSigner
    libnacl_sign.Verifier = FakeVerifier
    libnacl.sign = libnacl_sign  # type: ignore[attr-defined]
    moonraker = ModuleType("moonraker")
    components = ModuleType("moonraker.components")
    utils = ModuleType("moonraker.utils")
    json_wrapper = ModuleType("moonraker.utils.json_wrapper")
    json_wrapper.dumps = lambda value: json.dumps(value, separators=(",", ":")).encode()
    json_wrapper.loads = lambda value: json.loads(value)
    utils.json_wrapper = json_wrapper  # type: ignore[attr-defined]
    common = ModuleType("moonraker.common")
    common.RequestType = RequestType
    common.TransportType = TransportType
    common.SqlTableDefinition = SqlTableDefinition
    common.UserInfo = UserInfo
    sys.modules.update(
        {
            "tornado": tornado,
            "tornado.web": tornado_web,
            "libnacl": libnacl,
            "libnacl.sign": libnacl_sign,
            "moonraker": moonraker,
            "moonraker.components": components,
            "moonraker.utils": utils,
            "moonraker.utils.json_wrapper": json_wrapper,
            "moonraker.common": common,
        }
    )


def load_authorization_module(module_path: Path) -> ModuleType:
    install_boundary_fakes()
    module_name = "moonraker.components.authorization"
    spec = importlib.util.spec_from_file_location(module_name, module_path)
    if spec is None or spec.loader is None:
        fail(f"cannot load Moonraker authorization module: {module_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


async def build_authorization(module: ModuleType, database: FakeDatabase) -> object:
    authorization = module.Authorization(FakeConfig(FakeServer(database)))
    await authorization.component_init()
    return authorization


async def expect_http_401(awaitable: object, label: str) -> None:
    try:
        await awaitable  # type: ignore[misc]
    except FakeHTTPError as error:
        if error.status_code != 401:
            fail(f"{label} returned HTTP {error.status_code}, expected 401")
    else:
        fail(f"{label} unexpectedly succeeded")


async def exercise_contract(module: ModuleType) -> None:
    database = FakeDatabase()
    authorization = await build_authorization(module, database)

    # Before a normal user exists, a request from a configured trusted range
    # is the accepted first-claim setup state.
    fresh_user = await authorization.authenticate_request(FakeRequest("192.0.2.44"))
    if fresh_user.username != module.TRUSTED_USER:
        fail("fresh profile did not allow its documented trusted first-claim client")

    create_request = FakeWebRequest(
        RequestType.POST, {"username": "owner", "password": "test-only-password"}
    )
    login = await authorization._handle_user_request(create_request)
    if login["action"] != "user_created" or "token" not in login:
        fail("first normal user creation did not yield the expected source result")
    api_key = authorization.api_key
    if set(database.table.rows) != {module.API_USER, "owner"}:
        fail("normal user and API key user were not persisted through the source table path")

    # A forwarding header cannot recover trusted-client access after the owner
    # exists.  The target code must reject the actual request identity even if
    # an attacker supplies a different claimed forwarding address.
    spoofed = FakeRequest("192.0.2.44", {"X-Forwarded-For": "127.0.0.1"})
    await expect_http_401(
        authorization.authenticate_request(spoofed),
        "post-claim unauthenticated request with forwarding header",
    )

    api_user = await authorization.authenticate_request(
        FakeRequest("192.0.2.44", {"X-Api-Key": api_key})
    )
    if api_user.username != module.API_USER:
        fail("correct API key did not authenticate as Moonraker's API user")

    jwt_user = await authorization.authenticate_request(
        FakeRequest("192.0.2.44", {"Authorization": f"Bearer {login['token']}"})
    )
    if jwt_user.username != "owner":
        fail("JWT control flow did not authenticate the created normal user")

    # Recreate the component over the same persistent table to model an image
    # replacement that preserves Moonraker's database.
    replacement = await build_authorization(module, database)
    if replacement.api_key != api_key:
        fail("API key changed after rebuilding authorization from persistent state")
    await expect_http_401(
        replacement.authenticate_request(FakeRequest("192.0.2.44")),
        "post-update unauthenticated request",
    )
    persisted_api_user = await replacement.authenticate_request(
        FakeRequest("192.0.2.44", {"X-Api-Key": api_key})
    )
    if persisted_api_user.username != module.API_USER:
        fail("persisted API key did not survive component reconstruction")


def main() -> int:
    if len(sys.argv) != 2:
        fail(f"usage: {sys.argv[0]} <ad5m_enhanced_mod-root>")
    repo_root = Path(sys.argv[1]).resolve()
    if "build_output" in repo_root.parts:
        fail(f"refusing a build-output path as repository root: {repo_root}")
    source_text = os.environ.get("MOONRAKER_SOURCE_DIR", "")
    if not source_text:
        fail("MOONRAKER_SOURCE_DIR is required; provide the pinned Moonraker source tree")
    lock = load_fixture(repo_root)
    module_path = verify_source(repo_root, Path(source_text).resolve(), lock)
    module = load_authorization_module(module_path)
    asyncio.run(exercise_contract(module))
    print(f"ok: pinned Moonraker authorization.py matches {lock['commit']}")
    print("ok: fresh trusted first claim becomes credential-only after user creation")
    print("ok: API-key and JWT branch control flow succeeds after first claim")
    print("ok: user/API-key state survives a component reconstruction")
    print("Moonraker authorization component-contract validation passed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except HarnessError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
