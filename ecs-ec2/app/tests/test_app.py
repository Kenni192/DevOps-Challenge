from main import create_app


def client():
    return create_app().test_client()


def test_health():
    r = client().get("/health")
    assert r.status_code == 200
    assert r.get_json() == {"status": "ok"}


def test_index():
    r = client().get("/")
    assert r.status_code == 200
    assert r.get_json()["service"] == "ecs-fargate-platform"


def test_error_endpoint_returns_500():
    assert client().get("/error").status_code == 500
