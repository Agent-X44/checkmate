import json
import os
import sys
from types import ModuleType, SimpleNamespace
import pytest
from httpx import ASGITransport, AsyncClient

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import main
from main import app
from push_notifications import dispatch_notification


@pytest.mark.parametrize(
    ("standard_name", "platform_name"),
    [
        ("SUPABASE_URL", "SUPABASEURL"),
        ("SUPABASE_SERVICE_ROLE_KEY", "SUPABASESERVICEROLEKEY"),
        (
            "SUPABASE_NOTIFICATION_WEBHOOK_SECRET",
            "SUPABASENOTIFICATIONWEBHOOKSECRET",
        ),
        ("FIREBASE_SERVICE_ACCOUNT_JSON", "FIREBASESERVICEACCOUNTJSON"),
    ],
)
def test_deployment_settings_accept_hugging_face_secret_names(
    monkeypatch, standard_name, platform_name
):
    monkeypatch.delenv(standard_name, raising=False)
    monkeypatch.setenv(platform_name, "configured-value")

    assert main._deployment_setting(standard_name, platform_name) == "configured-value"


def test_standard_deployment_setting_takes_precedence(monkeypatch):
    monkeypatch.setenv("SUPABASE_URL", "standard-url")
    monkeypatch.setenv("SUPABASEURL", "platform-url")

    assert main._deployment_setting("SUPABASE_URL", "SUPABASEURL") == "standard-url"


class FakeQuery:
    def __init__(self, data=None):
        self.data = data

    def select(self, *_args):
        return self

    def eq(self, *_args):
        return self

    def maybe_single(self):
        return self

    def delete(self):
        self.data = None
        return self

    def in_(self, *_args):
        return self

    def execute(self):
        return SimpleNamespace(data=self.data)


class FakeDatabase:
    def __init__(self, enrollment=True, tokens=None, enrollment_error=False):
        self.enrollment = enrollment
        self.tokens = tokens or []
        self.deleted_tokens = []
        self.enrollment_error = enrollment_error

    def table(self, name):
        if name == "enrollments":
            if self.enrollment_error:
                raise RuntimeError("enrollment database unavailable")
            return FakeQuery({"user_id": "student-1"} if self.enrollment else None)
        if name == "user_notification_tokens":
            query = FakeQuery(self.tokens)
            original_execute = query.execute

            def execute():
                if query.data is None:
                    self.deleted_tokens = ["invalid-token"]
                return original_execute()

            query.execute = execute
            return query
        raise AssertionError(f"Unexpected table: {name}")


def _webhook_payload(kind="announcement"):
    return {
        "type": "INSERT",
        "schema": "public",
        "table": "user_notifications",
        "record": {
            "id": "notice-1",
            "recipient_id": "student-1",
            "kind": kind,
            "source_id": "source-1",
            "class_id": "class-1",
            "exam_id": "exam-1" if kind == "result" else None,
            "related_student_id": "student-1" if kind == "message" else None,
            "title": "CheckMate update",
            "body": "A new update is available.",
        },
    }


def test_fcm_delivery_with_no_registered_devices_is_a_successful_noop():
    result = dispatch_notification(
        FakeDatabase(),
        "",
        {
            "id": "notice-1",
            "recipient_id": "student-1",
            "kind": "announcement",
            "title": "New announcement",
            "body": "Read the class announcement.",
        },
    )

    assert result == {"sent": 0, "failed": 0}


@pytest.mark.asyncio
async def test_notification_webhook_sends_to_student_and_supports_all_event_types(
    monkeypatch,
):
    database = FakeDatabase()
    sent = []
    monkeypatch.setattr(main, "SUPABASE_NOTIFICATION_WEBHOOK_SECRET", "secret")
    monkeypatch.setattr(main, "FIREBASE_SERVICE_ACCOUNT_JSON", '{"type":"service_account"}')
    monkeypatch.setattr(main, "supabase_admin", database)
    monkeypatch.setattr(
        main,
        "dispatch_notification",
        lambda db, credentials, record: sent.append((db, credentials, record))
        or {"sent": 1, "failed": 0},
    )

    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        for kind in ("message", "announcement", "module_upload", "result"):
            response = await client.post(
                "/webhooks/user-notifications",
                json=_webhook_payload(kind),
                headers={"X-CheckMate-Webhook-Secret": "secret"},
            )
            assert response.status_code == 200
            assert response.json() == {"sent": 1, "failed": 0}

    assert [entry[2]["kind"] for entry in sent] == [
        "message",
        "announcement",
        "module_upload",
        "result",
    ]


@pytest.mark.asyncio
async def test_notification_webhook_rejects_bad_secret_and_skips_non_students(
    monkeypatch,
):
    monkeypatch.setattr(main, "SUPABASE_NOTIFICATION_WEBHOOK_SECRET", "secret")
    monkeypatch.setattr(main, "FIREBASE_SERVICE_ACCOUNT_JSON", '{"type":"service_account"}')
    monkeypatch.setattr(main, "supabase_admin", FakeDatabase(enrollment=False))
    monkeypatch.setattr(
        main,
        "dispatch_notification",
        lambda *_args: pytest.fail("non-student notification must not be sent"),
    )

    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        bad_secret = await client.post(
            "/webhooks/user-notifications",
            json=_webhook_payload(),
            headers={"X-CheckMate-Webhook-Secret": "wrong"},
        )
        non_student = await client.post(
            "/webhooks/user-notifications",
            json=_webhook_payload(),
            headers={"X-CheckMate-Webhook-Secret": "secret"},
        )

    assert bad_secret.status_code == 401
    assert non_student.status_code == 200
    assert non_student.json()["skipped"] == "recipient is not a student"


@pytest.mark.asyncio
async def test_notification_webhook_reports_unconfigured_delivery(monkeypatch):
    monkeypatch.setattr(main, "SUPABASE_NOTIFICATION_WEBHOOK_SECRET", "")

    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        response = await client.post(
            "/webhooks/user-notifications",
            json=_webhook_payload(),
        )

    assert response.status_code == 503


@pytest.mark.asyncio
async def test_notification_webhook_surfaces_recipient_lookup_failures(monkeypatch):
    monkeypatch.setattr(main, "SUPABASE_NOTIFICATION_WEBHOOK_SECRET", "secret")
    monkeypatch.setattr(main, "FIREBASE_SERVICE_ACCOUNT_JSON", '{"type":"service_account"}')
    monkeypatch.setattr(
        main, "supabase_admin", FakeDatabase(enrollment_error=True)
    )

    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        response = await client.post(
            "/webhooks/user-notifications",
            json=_webhook_payload(),
            headers={"X-CheckMate-Webhook-Secret": "secret"},
        )

    assert response.status_code == 502


@pytest.mark.asyncio
async def test_notification_webhook_reports_partial_fcm_delivery(monkeypatch):
    monkeypatch.setattr(main, "SUPABASE_NOTIFICATION_WEBHOOK_SECRET", "secret")
    monkeypatch.setattr(
        main, "FIREBASE_SERVICE_ACCOUNT_JSON", '{"type":"service_account"}'
    )
    monkeypatch.setattr(main, "supabase_admin", FakeDatabase())
    monkeypatch.setattr(
        main,
        "dispatch_notification",
        lambda *_args: {"sent": 1, "failed": 1},
    )

    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        response = await client.post(
            "/webhooks/user-notifications",
            json=_webhook_payload(),
            headers={"X-CheckMate-Webhook-Secret": "secret"},
        )

    assert response.status_code == 502


def test_fcm_delivery_sends_notification_and_removes_invalid_device_tokens(
    monkeypatch,
):
    message_calls = []

    def factory(**kwargs):
        return SimpleNamespace(**kwargs)

    class TokenError(Exception):
        code = "NOT_FOUND"

    messaging = SimpleNamespace(
        MulticastMessage=factory,
        Notification=factory,
        AndroidConfig=factory,
        AndroidNotification=factory,
        send_each_for_multicast=lambda message, app: message_calls.append(
            (message, app)
        )
        or SimpleNamespace(
            success_count=1,
            failure_count=1,
            responses=[
                SimpleNamespace(success=True, exception=None),
                SimpleNamespace(success=False, exception=TokenError()),
            ],
        ),
    )
    firebase_admin = ModuleType("firebase_admin")
    firebase_admin.credentials = SimpleNamespace(Certificate=lambda value: value)
    firebase_admin.get_app = lambda: (_ for _ in ()).throw(ValueError("no app"))
    firebase_admin.initialize_app = lambda _credential: "firebase-app"
    firebase_admin.messaging = messaging
    monkeypatch.setitem(sys.modules, "firebase_admin", firebase_admin)
    database = FakeDatabase(tokens=[
        {"token": "valid-token"},
        {"token": "invalid-token"},
    ])

    result = dispatch_notification(
        database,
        json.dumps({"type": "service_account"}),
        {
            "id": "notice-1",
            "recipient_id": "student-1",
            "kind": "result",
            "class_id": "class-1",
            "exam_id": "exam-1",
            "title": "Results released",
            "body": "Your score is ready.",
        },
    )

    assert result == {"sent": 1, "failed": 1}
    assert message_calls[0][0].data == {
        "id": "notice-1",
        "kind": "result",
        "class_id": "class-1",
        "exam_id": "exam-1",
    }
    assert message_calls[0][1] == "firebase-app"
    assert database.deleted_tokens == ["invalid-token"]
