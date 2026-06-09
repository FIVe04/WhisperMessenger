import logging
import time
import uuid

from fastapi import FastAPI, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest

from .logging import clear_request_context, configure_logging, log_event, set_request_context

HTTP_REQUESTS = Counter(
    'whispre_http_requests_total',
    'Total number of HTTP requests.',
    ('service', 'method', 'route', 'status'),
)
HTTP_REQUEST_DURATION = Histogram(
    'whispre_http_request_duration_seconds',
    'HTTP request duration in seconds.',
    ('service', 'method', 'route'),
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10),
)
HTTP_REQUESTS_IN_PROGRESS = Gauge(
    'whispre_http_requests_in_progress',
    'Number of HTTP requests currently being processed.',
    ('service',),
)
SERVICE_INFO = Gauge(
    'whispre_service_info',
    'Static information about a running Whispre service.',
    ('service',),
)
KAFKA_EVENTS = Counter(
    'whispre_kafka_events_total',
    'Kafka events processed by Whispre services.',
    ('service', 'direction', 'event', 'result'),
)
WEBSOCKET_CONNECTIONS = Gauge(
    'whispre_websocket_connections',
    'Current number of active WebSocket connections.',
    ('service',),
)


def record_kafka_event(service: str, direction: str, event: str, result: str) -> None:
    KAFKA_EVENTS.labels(service=service, direction=direction, event=event, result=result).inc()


def websocket_connected(service: str) -> None:
    WEBSOCKET_CONNECTIONS.labels(service=service).inc()


def websocket_disconnected(service: str) -> None:
    WEBSOCKET_CONNECTIONS.labels(service=service).dec()


def instrument_app(app: FastAPI, service_name: str) -> None:
    configure_logging(service_name)
    logger = logging.getLogger(f'{service_name}.http')
    SERVICE_INFO.labels(service=service_name).set(1)
    HTTP_REQUESTS_IN_PROGRESS.labels(service=service_name).set(0)
    log_event(logger, logging.INFO, 'service_initialized', service=service_name)

    @app.middleware('http')
    async def prometheus_middleware(request: Request, call_next):
        if request.url.path == '/metrics':
            return await call_next(request)

        request_id = request.headers.get('x-request-id', '').strip()
        if not request_id or len(request_id) > 128:
            request_id = str(uuid.uuid4())
            request.scope['headers'].append((b'x-request-id', request_id.encode('ascii')))

        set_request_context(request_id)
        method = request.method
        started_at = time.perf_counter()
        status_code = 500
        response: Response | None = None
        HTTP_REQUESTS_IN_PROGRESS.labels(service=service_name).inc()
        try:
            response = await call_next(request)
            status_code = response.status_code
            return response
        except Exception:
            duration = time.perf_counter() - started_at
            log_event(
                logger,
                logging.ERROR,
                'http_request_failed',
                method=method,
                path=request.url.path,
                status=500,
                duration_ms=round(duration * 1000, 2),
                exc_info=True,
            )
            raise
        finally:
            route = request.scope.get('route')
            route_path = getattr(route, 'path', 'unmatched')
            duration = time.perf_counter() - started_at
            HTTP_REQUESTS.labels(
                service=service_name,
                method=method,
                route=route_path,
                status=str(status_code),
            ).inc()
            HTTP_REQUEST_DURATION.labels(
                service=service_name,
                method=method,
                route=route_path,
            ).observe(duration)
            HTTP_REQUESTS_IN_PROGRESS.labels(service=service_name).dec()
            if response is not None:
                response.headers['X-Request-ID'] = request_id
                level = logging.ERROR if status_code >= 500 else logging.WARNING if status_code >= 400 else logging.INFO
                if request.url.path == '/health':
                    level = logging.DEBUG
                log_event(
                    logger,
                    level,
                    'http_request_completed',
                    method=method,
                    route=route_path,
                    path=request.url.path,
                    status=status_code,
                    duration_ms=round(duration * 1000, 2),
                )
            clear_request_context()

    @app.get('/metrics', include_in_schema=False)
    def metrics() -> Response:
        return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)
