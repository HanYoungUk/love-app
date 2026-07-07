// 채팅(messages 컬렉션)에 '상대' 메시지를 1건 넣어 OS 알림 테스트.
// firebase-tools 저장 토큰으로 Firestore REST API 호출.
const fs = require('fs');
const os = require('os');
const https = require('https');

const PROJECT_ID = 'love-app-4e2ac';
const TEXT = process.argv[2] || '안녕! 클로드가 보내는 테스트 메시지야 💌 알림 잘 떠?';

function httpsReq(method, hostname, path, headers, body) {
  return new Promise((resolve, reject) => {
    const req = https.request({ hostname, path, method, headers }, res => {
      let data = '';
      res.on('data', d => (data += d));
      res.on('end', () => resolve({ status: res.statusCode, body: data ? JSON.parse(data) : null }));
    });
    req.on('error', reject);
    if (body) req.write(typeof body === 'string' ? body : JSON.stringify(body));
    req.end();
  });
}

function getAccessToken() {
  const cfg = JSON.parse(fs.readFileSync(os.homedir() + '/.config/configstore/firebase-tools.json', 'utf8'));
  const token = cfg.tokens?.access_token;
  if (!token) throw new Error('저장된 access_token 없음. firebase login 먼저 해주세요.');
  return token;
}

async function main() {
  const token = getAccessToken();
  const now = new Date().toISOString();
  const doc = {
    fields: {
      type: { stringValue: 'text' },
      text: { stringValue: TEXT },
      senderUid: { stringValue: 'claude-test-bot' }, // 내 uid가 아니어야 '상대'로 인식
      senderEmail: { stringValue: 'claude@loveapp.com' },
      createdAt: { timestampValue: now },
    },
  };
  const res = await httpsReq(
    'POST',
    'firestore.googleapis.com',
    `/v1/projects/${PROJECT_ID}/databases/(default)/documents/messages`,
    { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    doc
  );
  if (res.status === 200) {
    console.log('메시지 전송 성공! 문서:', res.body.name.split('/documents/')[1]);
  } else {
    console.log('전송 실패:', res.status, JSON.stringify(res.body));
  }
}

main().catch(e => { console.error('오류:', e.message); process.exit(1); });
