/* eslint-disable */

// ===============================================
// Campus Queue System – Firebase Cloud Functions
// Prototype version - accepts UID/email in data
// ===============================================

const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

const db = admin.firestore();

// Read configuration from runtime config (firebase functions:config:set app.allowed_domains="..." app.default_no_show_timeout=300)
const _cfg = (() => {
  try {
    const cfg = functions.config && functions.config().app ? functions.config().app : {};
    const domains = cfg.allowed_domains ? cfg.allowed_domains.split(',').map(s => s.trim()).filter(Boolean) : ['mite.ac.in','asterhyphen.xyz'];
    const defaultTimeout = Number(cfg.default_no_show_timeout) || 300;
    return { allowedDomains: domains, defaultNoShowTimeout: defaultTimeout };
  } catch (e) {
    return { allowedDomains: ['mite.ac.in','asterhyphen.xyz'], defaultNoShowTimeout: 300 };
  }
})();


// ---------------------------------------------------------
// 🔥 Helper: Load user role by UID
// ---------------------------------------------------------
async function getRole(uid) {
  const doc = await db.collection("users").doc(uid).get();
  if (!doc.exists) return "student"; // default
  return doc.data().role;
}

// ---------------------------------------------------------
// GET USER ROLE
// ---------------------------------------------------------
exports.getUserRole = functions.https.onCall(async (data, context) => {
  // Try context.auth first, then data.uid
  let uid = null;
  if (context.auth) {
    uid = context.auth.uid;
  } else if (data && data.uid) {
    uid = data.uid;
  }

  if (!uid) {
    throw new functions.https.HttpsError("unauthenticated", "Not logged in");
  }

  const role = await getRole(uid);
  return { role };
});

// ---------------------------------------------------------
// Helpers: Auth, blocklist, priority & internal callNext
// ---------------------------------------------------------

async function verifyAuthFromReq(req) {
  // Expects Authorization: Bearer <idToken>
  const header = req.get('Authorization') || req.get('authorization');
  if (!header || !header.startsWith('Bearer ')) return null;
  const idToken = header.split('Bearer ')[1];
  try {
    const decoded = await admin.auth().verifyIdToken(idToken);
    return decoded; // contains uid, email, email_verified
  } catch (err) {
    console.warn('Failed to verify ID token:', err);
    return null;
  }
}

async function isBlockedEmail(email) {
  if (!email) return false;
  const snap = await db.collection('blockedUsers').where('email', '==', email).limit(1).get();
  return !snap.empty;
}

function computePriorityFromEmail(email) {
  if (!email) return 2;
  const local = (email.split('@')[0] || '').toUpperCase();
  // Students with IDs starting with 4MT are lower priority (2)
  if (local.startsWith('4MT')) return 2;
  // Teachers / other staff get higher priority (1)
  return 1;
}

async function callNextInternal(queueId) {
  const queueDoc = await db.collection('queues').doc(queueId).get();
  if (!queueDoc.exists) {
    throw new Error('Queue not found');
  }

  const tokensRef = db
    .collection('queues')
    .doc(queueId)
    .collection('tokens');

  const currentRef = db
    .collection('queues')
    .doc(queueId)
    .collection('current')
    .doc('token');

  // Pick next token by priority then timestamp
  const snap = await tokensRef.orderBy('priority', 'asc').orderBy('timestamp').limit(1).get();

  if (snap.empty) {
    await currentRef.delete().catch(() => {});
    return { success: true, message: 'No tokens left' };
  }

  const next = snap.docs[0];
  const nextData = next.data();

  await next.ref.delete();
  await currentRef.set({
    uid: nextData.uid,
    email: nextData.email,
    calledAt: Date.now(),
    priority: nextData.priority || 2,
  });

  return { success: true, email: nextData.email };
}

// ---------------------------------------------------------
// ADMIN → CREATE QUEUE (HTTP function)
// ---------------------------------------------------------
exports.createQueue = functions.https.onRequest(async (req, res) => {
  // Handle CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).json({ error: { message: "Method not allowed", status: "INVALID_ARGUMENT" } });
    return;
  }

  try {
    const requestData = req.body.data || req.body;
    console.log('createQueue HTTP called - body:', JSON.stringify(req.body));
    
    const uid = requestData.uid;
    const { name, cashierEmail } = requestData;

    console.log('Extracted - uid:', uid, 'name:', name, 'cashierEmail:', cashierEmail);

    if (!uid) {
      res.status(401).json({ error: { message: "Not logged in", status: "UNAUTHENTICATED" } });
      return;
    }

    const role = await getRole(uid);
    if (role !== "admin") {
      res.status(403).json({ error: { message: "Only admin can create queues", status: "PERMISSION_DENIED" } });
      return;
    }

    if (!name || !cashierEmail) {
      res.status(400).json({ error: { message: "Missing name or cashierEmail", status: "INVALID_ARGUMENT" } });
      return;
    }

    const ref = await db.collection("queues").add({
      name,
      cashierEmail,
      createdAt: Date.now(),
      // default no-show timeout (seconds) - can be overridden by admin
      noShowTimeoutSeconds: requestData.noShowTimeoutSeconds || _cfg.defaultNoShowTimeout,
    });

    console.log('Queue created successfully:', ref.id);
    res.status(200).json({ success: true, id: ref.id });
  } catch (error) {
    console.error('createQueue error:', error);
    res.status(500).json({ error: { message: error.message, status: "INTERNAL" } });
  }
});

// ---------------------------------------------------------
// STUDENT → BOOK TOKEN (HTTP function - server-side validation/enforcement)
// ---------------------------------------------------------
exports.bookToken = functions.https.onRequest(async (req, res) => {
  // Handle CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).json({ error: { message: "Method not allowed", status: "INVALID_ARGUMENT" } });
    return;
  }

  try {
    const requestData = req.body.data || req.body;
    console.log('bookToken HTTP called - requestData:', JSON.stringify(requestData));

    // Prefer verified auth token when available
    const auth = await verifyAuthFromReq(req);
    const uid = (auth && auth.uid) || requestData.uid;
    const email = (auth && auth.email) || requestData.email || 'unknown';
    const queueId = requestData.queueId;

    if (!uid) {
      res.status(401).json({ error: { message: "Not logged in", status: "UNAUTHENTICATED" } });
      return;
    }

    if (!queueId) {
      res.status(400).json({ error: { message: "Missing queueId", status: "INVALID_ARGUMENT" } });
      return;
    }

    // Enforce verified email if present in token
    if (auth && !auth.email_verified) {
      res.status(403).json({ error: { message: "Email not verified", status: "PERMISSION_DENIED" } });
      return;
    }

    // Basic email domain restriction using runtime config
    const domainAllowed = _cfg.allowedDomains.some(d => email.endsWith('@' + d));
    if (!domainAllowed) {
      res.status(403).json({ error: { message: "Email domain not permitted", status: "PERMISSION_DENIED" } });
      return;
    }

    // Check blocklist
    if (await isBlockedEmail(email)) {
      res.status(403).json({ error: { message: "User is blocked", status: "PERMISSION_DENIED" } });
      return;
    }

    const tokensRef = db.collection('queues').doc(queueId).collection('tokens');
    const currentRef = db.collection('queues').doc(queueId).collection('current').doc('token');

    // Prevent duplicates or already being served
    const existing = await tokensRef.where('uid', '==', uid).get();
    if (!existing.empty) {
      res.status(409).json({ error: { message: "Already in queue", status: "ALREADY_EXISTS" } });
      return;
    }

    const currentSnap = await currentRef.get();
    if (currentSnap.exists && currentSnap.data().uid === uid) {
      res.status(409).json({ error: { message: "Already being served", status: "ALREADY_EXISTS" } });
      return;
    }

    // Rate limiting: per-user per-queue cooldown (2 seconds)
    const now = Date.now();
    const rateDocRef = db.collection('rateLimits').doc(uid);
    await db.runTransaction(async (t) => {
      const r = await t.get(rateDocRef);
      const field = `lastBook_${queueId}`;
      if (r.exists && r.data()[field] && (now - r.data()[field] < 2000)) {
        throw new functions.https.HttpsError('resource-exhausted', 'Please wait before booking again');
      }
      t.set(rateDocRef, { [field]: now }, { merge: true });

      // Compute priority on server (lower number => higher priority)
      const priority = computePriorityFromEmail(email);

      // Add queue token
      t.set(tokensRef.doc(), {
        uid,
        email,
        timestamp: now,
        priority,
      });
    });

    console.log('Token booked successfully for uid:', uid);
    res.status(200).json({ success: true });
  } catch (error) {
    if (error instanceof functions.https.HttpsError) {
      console.error('bookToken HttpsError:', error);
      res.status(429).json({ error: { message: error.message, status: error.code } });
      return;
    }
    console.error('bookToken error:', error);
    res.status(500).json({ error: { message: error.message, status: "INTERNAL" } });
  }
});

// ---------------------------------------------------------
// CASHIER → CALL NEXT (HTTP function)
// ---------------------------------------------------------
exports.callNext = functions.https.onRequest(async (req, res) => {
  // Handle CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).json({ error: { message: "Method not allowed", status: "INVALID_ARGUMENT" } });
    return;
  }

  try {
    const requestData = req.body.data || req.body;
    console.log('callNext HTTP called - requestData:', JSON.stringify(requestData));

    const auth = await verifyAuthFromReq(req);
    const uid = (auth && auth.uid) || requestData.uid;
    const email = (auth && auth.email) || requestData.email;
    const queueId = requestData.queueId;

    if (!uid || !email) {
      res.status(401).json({ error: { message: "Not logged in", status: "UNAUTHENTICATED" } });
      return;
    }

    if (!queueId) {
      res.status(400).json({ error: { message: "Missing queueId", status: "INVALID_ARGUMENT" } });
      return;
    }

    const queueDoc = await db.collection('queues').doc(queueId).get();
    if (!queueDoc.exists) {
      res.status(404).json({ error: { message: "Queue not found", status: "NOT_FOUND" } });
      return;
    }

    if (queueDoc.data().cashierEmail !== email) {
      res.status(403).json({ error: { message: "You are not assigned to this queue", status: "PERMISSION_DENIED" } });
      return;
    }

    try {
      const result = await callNextInternal(queueId);
      res.status(200).json(result);
    } catch (e) {
      console.error('callNext internal error:', e);
      res.status(500).json({ error: { message: e.message, status: "INTERNAL" } });
    }

  } catch (error) {
    console.error('callNext error:', error);
    res.status(500).json({ error: { message: error.message, status: "INTERNAL" } });
  }
});

// ---------------------------------------------------------
// CASHIER → CLEAR CURRENT TOKEN
// ---------------------------------------------------------
exports.clearCurrent = functions.https.onCall(async (data, context) => {
  // Try context.auth first, then data.email
  let email = null;
  
  if (context.auth) {
    email = context.auth.token.email;
  } else if (data && data.email) {
    email = data.email;
  }

  if (!email) {
    throw new functions.https.HttpsError("unauthenticated", "Not logged in");
  }

  const queueId = data.queueId;
  if (!queueId) {
    throw new functions.https.HttpsError("invalid-argument", "Missing queueId");
  }

  const queueDoc = await db.collection("queues").doc(queueId).get();
  if (!queueDoc.exists) {
    throw new functions.https.HttpsError("not-found", "Queue not found");
  }

  if (queueDoc.data().cashierEmail !== email) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Not assigned cashier"
    );
  }

  const currentRef = db
    .collection("queues")
    .doc(queueId)
    .collection("current")
    .doc("token");

  await currentRef.delete().catch(() => {});
  return { success: true };
});

// ---------------------------------------------------------
// CASHIER → MARK NO-SHOW (HTTP function)
// - Can mark current token as no-show and optionally trigger next
// - Can mark a token in the queue as no-show (removes it)
// ---------------------------------------------------------
exports.markNoShow = functions.https.onRequest(async (req, res) => {
  // Handle CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).json({ error: { message: "Method not allowed", status: "INVALID_ARGUMENT" } });
    return;
  }

  try {
    const requestData = req.body.data || req.body;
    const auth = await verifyAuthFromReq(req);
    const email = (auth && auth.email) || requestData.requestedBy;
    const queueId = requestData.queueId;
    const tokenId = requestData.tokenId; // optional

    if (!email) {
      res.status(401).json({ error: { message: "Not logged in", status: "UNAUTHENTICATED" } });
      return;
    }

    if (!queueId) {
      res.status(400).json({ error: { message: "Missing queueId", status: "INVALID_ARGUMENT" } });
      return;
    }

    const queueDoc = await db.collection('queues').doc(queueId).get();
    if (!queueDoc.exists) {
      res.status(404).json({ error: { message: "Queue not found", status: "NOT_FOUND" } });
      return;
    }

    if (queueDoc.data().cashierEmail !== email) {
      res.status(403).json({ error: { message: "You are not assigned to this queue", status: "PERMISSION_DENIED" } });
      return;
    }

    const noShowsRef = db.collection('queues').doc(queueId).collection('noShows');
    const tokensRef = db.collection('queues').doc(queueId).collection('tokens');
    const currentRef = db.collection('queues').doc(queueId).collection('current').doc('token');

    if (tokenId) {
      // Mark a queued token as no-show
      const doc = await tokensRef.doc(tokenId).get();
      if (!doc.exists) {
        res.status(404).json({ error: { message: "Token not found", status: "NOT_FOUND" } });
        return;
      }
      const data = doc.data();
      await noShowsRef.add({
        uid: data.uid,
        email: data.email,
        markedAt: Date.now(),
        reason: requestData.reason || 'marked by cashier',
      });
      await doc.ref.delete();
      res.status(200).json({ success: true });
      return;
    }

    // Otherwise, process current token as no-show
    const currentSnap = await currentRef.get();
    if (!currentSnap.exists) {
      res.status(404).json({ error: { message: "No current token", status: "NOT_FOUND" } });
      return;
    }
    const currentData = currentSnap.data();

    await noShowsRef.add({
      uid: currentData.uid,
      email: currentData.email,
      calledAt: currentData.calledAt,
      markedAt: Date.now(),
      reason: requestData.reason || 'no-show (marked by cashier)',
    });

    await currentRef.delete().catch(() => {});

    // Trigger next
    const next = await callNextInternal(queueId);

    res.status(200).json({ success: true, next });
  } catch (error) {
    console.error('markNoShow error:', error);
    res.status(500).json({ error: { message: error.message, status: "INTERNAL" } });
  }
});

// ---------------------------------------------------------
// CASHIER → PROCESS NO-SHOWS (HTTP function)
// - Checks current token for expiry and rotates if expired
// ---------------------------------------------------------
exports.processNoShows = functions.https.onRequest(async (req, res) => {
  // Handle CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).json({ error: { message: "Method not allowed", status: "INVALID_ARGUMENT" } });
    return;
  }

  try {
    const requestData = req.body.data || req.body;
    const auth = await verifyAuthFromReq(req);
    const email = (auth && auth.email) || requestData.requestedBy;
    const queueId = requestData.queueId;

    if (!email) {
      res.status(401).json({ error: { message: "Not logged in", status: "UNAUTHENTICATED" } });
      return;
    }

    if (!queueId) {
      res.status(400).json({ error: { message: "Missing queueId", status: "INVALID_ARGUMENT" } });
      return;
    }

    const queueDoc = await db.collection('queues').doc(queueId).get();
    if (!queueDoc.exists) {
      res.status(404).json({ error: { message: "Queue not found", status: "NOT_FOUND" } });
      return;
    }

    if (queueDoc.data().cashierEmail !== email) {
      res.status(403).json({ error: { message: "You are not assigned to this queue", status: "PERMISSION_DENIED" } });
      return;
    }

    const currentRef = db.collection('queues').doc(queueId).collection('current').doc('token');
    const noShowsRef = db.collection('queues').doc(queueId).collection('noShows');

    const currentSnap = await currentRef.get();
    if (!currentSnap.exists) {
      res.status(200).json({ success: true, message: 'No current token' });
      return;
    }

    const currentData = currentSnap.data();
    const timeoutSeconds = queueDoc.data().noShowTimeoutSeconds || 300;

    if (currentData.calledAt + timeoutSeconds * 1000 < Date.now()) {
      // Mark as no-show and rotate
      await noShowsRef.add({
        uid: currentData.uid,
        email: currentData.email,
        calledAt: currentData.calledAt,
        markedAt: Date.now(),
        reason: 'auto-processed by processNoShows',
      });

      await currentRef.delete().catch(() => {});
      const next = await callNextInternal(queueId);
      res.status(200).json({ success: true, processed: true, next });
      return;
    }

    res.status(200).json({ success: true, processed: false });
  } catch (error) {
    console.error('processNoShows error:', error);
    res.status(500).json({ error: { message: error.message, status: "INTERNAL" } });
  }
});

// Helper: process no-shows for a given queueId (extract for scheduled function)
async function processNoShowsForQueue(queueId) {
  const queueDoc = await db.collection('queues').doc(queueId).get();
  if (!queueDoc.exists) {
    return { processed: false, reason: 'queue not found' };
  }

  const currentRef = db.collection('queues').doc(queueId).collection('current').doc('token');
  const noShowsRef = db.collection('queues').doc(queueId).collection('noShows');

  const currentSnap = await currentRef.get();
  if (!currentSnap.exists) {
    return { processed: false, reason: 'no current token' };
  }

  const currentData = currentSnap.data();
  const timeoutSeconds = queueDoc.data().noShowTimeoutSeconds || _cfg.defaultNoShowTimeout;

  if (currentData.calledAt + timeoutSeconds * 1000 < Date.now()) {
    await noShowsRef.add({
      uid: currentData.uid,
      email: currentData.email,
      calledAt: currentData.calledAt,
      markedAt: Date.now(),
      reason: 'auto-processed by scheduledProcessNoShows',
    });

    await currentRef.delete().catch(() => {});
    const next = await callNextInternal(queueId);
    return { processed: true, next };
  }

  return { processed: false, reason: 'not expired' };
}

// Scheduled function to run periodically and process expired tokens
if (functions.pubsub && typeof functions.pubsub.schedule === 'function') {
  exports.scheduledProcessNoShows = functions.pubsub
    .schedule('every 1 minutes')
    .onRun(async (context) => {
      console.log('scheduledProcessNoShows running...');
      const queuesSnap = await db.collection('queues').get();
      const results = [];
      for (const qdoc of queuesSnap.docs) {
        try {
          const result = await processNoShowsForQueue(qdoc.id);
          if (result.processed) {
            console.log('Processed no-show for queue', qdoc.id, result);
          }
          results.push({ queue: qdoc.id, result });
        } catch (e) {
          console.error('Error processing queue', qdoc.id, e);
          results.push({ queue: qdoc.id, error: e.message });
        }
      }
      return { success: true, results };
    });
} else {
  console.warn('Scheduled functions (pubsub.schedule) not available in this environment; scheduledProcessNoShows not registered.');
}

// Export internal helpers for unit tests (non-production)
module.exports._test = {
  computePriorityFromEmail,
  callNextInternal,
  processNoShowsForQueue,
};
