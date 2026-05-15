const { https } = require('firebase-functions/v1');
const { onDocumentWritten, onDocumentCreated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

admin.initializeApp();

// 상대방 FCM 토큰에 알림 전송
async function sendToOthers({ authorUid, title, body }) {
  const usersSnap = await admin.firestore().collection('users').get();
  const tokens = [];
  usersSnap.forEach(doc => {
    const data = doc.data();
    if (doc.id !== authorUid && data.fcmToken) {
      tokens.push(data.fcmToken);
    }
  });
  if (tokens.length === 0) return;

  try {
    await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      android: { priority: 'high' },
      webpush: {
        notification: { icon: '/icons/Icon-192.png' },
      },
    });
  } catch (e) {
    console.error('FCM 전송 오류:', e);
  }
}

// 관리자 회원 탈퇴
exports.deleteAuthUser = https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', 'https://love-app-4e2ac.web.app');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');

  if (req.method === 'OPTIONS') { res.status(204).send(''); return; }
  if (req.method !== 'POST') { res.status(405).json({ error: 'Method not allowed' }); return; }

  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      res.status(401).json({ error: 'Unauthorized' }); return;
    }
    const idToken = authHeader.substring(7);
    const decoded = await admin.auth().verifyIdToken(idToken);
    if (decoded.email !== 'gksdud9685@loveapp.com') {
      res.status(403).json({ error: 'Forbidden' }); return;
    }
    const uid = req.body.uid;
    if (!uid) { res.status(400).json({ error: 'UID required' }); return; }
    await admin.auth().deleteUser(uid);
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// 일기 저장 알림
exports.onDiarySaved = onDocumentWritten('diaries/{dateId}', async (event) => {
  const after = event.data?.after?.data();
  if (!after) return;
  const authorUid = after.authorUid;
  if (!authorUid) return;
  const email = after.authorEmail || '';
  const username = email.replace('@loveapp.com', '') || '상대방';
  const dateId = event.params.dateId; // 예: 2026-05-15
  const [year, month, day] = dateId.split('-');
  const dateStr = `${parseInt(month)}월 ${parseInt(day)}일`;
  await sendToOthers({
    authorUid,
    title: '💕 일기가 작성됐어요',
    body: `${username}이(가) ${dateStr}에 일기를 작성했어요!`,
  });
});

// 메모 저장 알림
exports.onMemoSaved = onDocumentWritten('memos/{dateId}', async (event) => {
  const after = event.data?.after?.data();
  if (!after) return;
  const authorUid = after.authorUid;
  if (!authorUid) return;
  const email = after.authorEmail || '';
  const username = email.replace('@loveapp.com', '') || '상대방';
  const dateId = event.params.dateId;
  const [year, month, day] = dateId.split('-');
  const dateStr = `${parseInt(month)}월 ${parseInt(day)}일`;
  const text = after.text || '';
  await sendToOthers({
    authorUid,
    title: '📝 메모가 작성됐어요',
    body: `${username}이(가) ${dateStr}에 메모를 남겼어요!`,
  });
});

// 버킷리스트 추가 알림
exports.onBucketListAdded = onDocumentCreated('bucket_list/{docId}', async (event) => {
  const data = event.data?.data();
  if (!data) return;
  const authorUid = data.authorUid;
  if (!authorUid) return;
  await sendToOthers({
    authorUid,
    title: '🎯 버킷리스트가 추가됐어요',
    body: data.title || '새 버킷리스트를 확인해보세요!',
  });
});

// 하트 전송 알림
exports.onHeartSent = onDocumentCreated('hearts/{docId}', async (event) => {
  const data = event.data?.data();
  if (!data) return;
  await sendToOthers({
    authorUid: data.sentBy,
    title: '💝 하트를 받았어요!',
    body: '상대방이 하트를 보냈어요 💕',
  });
});
