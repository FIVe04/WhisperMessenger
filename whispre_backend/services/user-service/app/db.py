from whispre_common.database import create_session_context

from .config import settings

get_db = create_session_context(settings.postgres_dsn, commit_on_success=False)
