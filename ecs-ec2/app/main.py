"""Tiny Flask service with structured JSON logging (ships to CloudWatch via awslogs)."""
import json
import logging
import os
import sys
import time

from flask import Flask, jsonify, request, g

APP_VERSION = os.getenv("APP_VERSION", "dev")
ENVIRONMENT = os.getenv("ENVIRONMENT", "local")


class JsonFormatter(logging.Formatter):
    def format(self, record):
        payload = {
            "ts": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "level": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
        }
        payload.update(getattr(record, "extra_fields", {}))
        return json.dumps(payload)


def create_app() -> Flask:
    app = Flask(__name__)

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    app.logger.handlers = [handler]
    app.logger.setLevel(logging.INFO)

    @app.before_request
    def _start_timer():
        g.start = time.perf_counter()

    @app.after_request
    def _log_request(resp):
        if request.path != "/health":  # keep ALB health checks out of the logs
            ms = round((time.perf_counter() - g.start) * 1000, 2)
            app.logger.info(
                "request",
                extra={"extra_fields": {"method": request.method, "path": request.path,
                                        "status": resp.status_code, "duration_ms": ms}},
            )
        return resp

    @app.get("/")
    def index():
        return jsonify(service="ecs-fargate-platform", version=APP_VERSION, environment=ENVIRONMENT)

    @app.get("/health")
    def health():
        return jsonify(status="ok"), 200

    @app.get("/error")
    def error():
        """Deliberate error to exercise the log metric filter + alarm."""
        app.logger.error("simulated failure", extra={"extra_fields": {"path": "/error"}})
        return jsonify(error="simulated"), 500

    return app


app = create_app()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")))
