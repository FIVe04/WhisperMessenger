from fastapi import APIRouter, Depends, Path, Query, status

from .dependencies import require_auth
from .producer import envelope_event_producer
from .schemas import AckEnvelopeRequest, EnvelopeResponse, SendBatchResponse, SendEnvelopesBatchRequest
from .service import (
    acknowledge_envelope,
    get_conversation_envelopes,
    get_pending_for_device,
    persist_envelope_batch,
)

router = APIRouter(prefix='/v1/messages')


@router.post('/envelopes:batch', response_model=SendBatchResponse, status_code=status.HTTP_202_ACCEPTED)
async def send_envelopes_batch(
    payload: SendEnvelopesBatchRequest,
    current_user_id: str = Depends(require_auth),
) -> SendBatchResponse:
    response, events = persist_envelope_batch(payload, current_user_id)
    await envelope_event_producer.publish(events)
    return response


@router.get('/envelopes/pending', response_model=list[EnvelopeResponse])
def get_pending_envelopes(
    device_id: str = Query(...),
    limit: int = Query(default=100, ge=1, le=1000),
    current_user_id: str = Depends(require_auth),
) -> list[EnvelopeResponse]:
    return get_pending_for_device(current_user_id, device_id, limit)


@router.post('/envelopes/{envelope_id}/ack')
def ack_envelope(
    payload: AckEnvelopeRequest,
    envelope_id: str = Path(...),
    current_user_id: str = Depends(require_auth),
) -> dict[str, str]:
    acknowledge_envelope(current_user_id, payload.device_id, envelope_id)
    return {'status': 'ok'}


@router.get('/conversations/{conversation_id}', response_model=list[EnvelopeResponse])
def get_conversation_history(
    conversation_id: str = Path(...),
    cursor: str | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=500),
    current_user_id: str = Depends(require_auth),
) -> list[EnvelopeResponse]:
    return get_conversation_envelopes(current_user_id, conversation_id, cursor, limit)
