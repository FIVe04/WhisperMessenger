from fastapi import FastAPI
from whispre_common.observability import instrument_app

from .config import settings
from .router import router

app = FastAPI(title=f'Whispre {settings.service_name}')
app.include_router(router)
instrument_app(app, settings.service_name)


@app.get('/health')
def health() -> dict[str, str]:
    return {'status': 'ok', 'service': settings.service_name}
