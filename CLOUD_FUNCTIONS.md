Cloud Functions spec for ICQS

Purpose
- Enforce server-side validation, rate-limiting, priority handling, and automatic no-show processing.

Endpoints / Callable functions

1) bookToken (httpsCallable or HTTP)
- Input: { queueId, priority?, email?, uid? }
- Behavior:
  - Verify caller auth and email domain
  - Reject if user is blocked (check `blockedUsers` collection)
  - Enforce per-user-per-queue rate limits (e.g., 1 booking per 2s; also limit number of active bookings per user)
  - Create a token document under `queues/{queueId}/tokens` with fields: { uid, email, priority, createdAt: millis, status: 'waiting' }
  - Return token id and position

2) callNext (httpsCallable or HTTP)
- Input: { queueId }
- Behavior:
  - Verify caller is cashier for the queue (match email in queue doc)
  - Pop next token based on priority and createdAt; set `queues/{queueId}/current/token` to that token
  - Mark calledAt timestamp and return token info

3) markNoShow (httpsCallable or HTTP)
- Input: { queueId, tokenId, requestedBy }
- Behavior:
  - Verify caller is authorized (cashier/admin)
  - Mark token as no-show (status: 'no-show') and either swap with next token or trigger `callNext` behavior
  - Record audit entry in `queues/{queueId}/audit` for visibility

4) processNoShows (httpsCallable or HTTP)
- Input: { queueId }
- Behavior:
  - Iterate current token and tokens at front that exceed `noShowTimeoutSeconds` and mark them as no-show and callNext to bring next eligible token
  - Use transactions to avoid race conditions

Security & Rules
- All callable endpoints must validate Firebase auth token
- Blocked users must be enforced on server
- Rate limits should be enforced both in DB (counter + timestamps) and code-level checks
- Use Firestore transactions where reordering/consuming tokens occurs to prevent races

Notes
- Client already supplies `priority` and `email` to `bookToken`; server MUST trust only verified auth token and recompute checks from token claims where needed.
- Implement detailed logging and return helpful error messages for the client (e.g., remaining cooldown seconds, blocked reason).

Example responses
- { success: true, tokenId: 'abc', position: 5 }
- { success: false, error: 'Rate limit exceeded. Wait 2s.' }

Recommended runner: NodeJS firebase-functions with Firestore transactions
