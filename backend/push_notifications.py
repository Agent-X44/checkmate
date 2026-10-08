"""Firebase Cloud Messaging delivery for persisted CheckMate notifications."""

import json
import logging

logger = logging.getLogger("CheckMateBackend")


class PushConfigurationError(RuntimeError):
    pass


def _firebase_messaging(service_account_json: str):
    try:
        from firebase_admin import credentials, get_app, initialize_app, messaging
    except ImportError as error:
        raise PushConfigurationError(
            "Firebase Admin SDK is not installed."
        ) from error

    try:
        app = get_app()
    except ValueError:
        try:
            service_account = json.loads(service_account_json)
            app = initialize_app(credentials.Certificate(service_account))
        except (ValueError, TypeError, KeyError) as error:
            raise PushConfigurationError(
                "Firebase service-account configuration is invalid."
            ) from error
    return app, messaging


def dispatch_notification(db, service_account_json: str, record: dict) -> dict:
    rows = (
        db.table("user_notification_tokens")
        .select("token")
        .eq("user_id", record["recipient_id"])
        .execute()
        .data
        or []
    )
    tokens = [row["token"] for row in rows if row.get("token")]
    if not tokens:
        return {"sent": 0, "failed": 0}

    app, messaging = _firebase_messaging(service_account_json)
    data = {
        key: str(record[key])
        for key in ("id", "kind", "class_id", "exam_id", "related_student_id")
        if record.get(key) is not None
    }
    sent = 0
    failed = 0
    invalid_tokens = []
    for start in range(0, len(tokens), 500):
        batch = tokens[start : start + 500]
        message = messaging.MulticastMessage(
            tokens=batch,
            notification=messaging.Notification(
                title=record["title"],
                body=record["body"],
            ),
            data=data,
            android=messaging.AndroidConfig(
                notification=messaging.AndroidNotification(tag=record["id"])
            ),
        )
        response = messaging.send_each_for_multicast(message, app=app)
        sent += response.success_count
        failed += response.failure_count
        invalid_tokens.extend(
            token
            for token, result in zip(batch, response.responses)
            if not result.success
            and getattr(result.exception, "code", None)
            in {
                "registration-token-not-registered",
                "invalid-registration-token",
                "NOT_FOUND",
            }
        )
    if invalid_tokens:
        db.table("user_notification_tokens").delete().in_(
            "token", invalid_tokens
        ).execute()
        logger.info(
            "Removed %d invalid notification device tokens.", len(invalid_tokens)
        )

    return {"sent": sent, "failed": failed}
