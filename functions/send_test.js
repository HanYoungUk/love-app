const fs = require('fs');
const os = require('os');
const https = require('https');

const PROJECT_ID = 'love-app-4e2ac';

function httpsPost(hostname, path, headers, body) {
  return new Promise((resolve, reject) => {
    const req = https.request({ hostname, path, method: 'POST', headers }, res => {
      let data = '';
      res.on('data', d => data += d);
      res.on('end', () => resolve({ status: res.statusCode, body: JSON.parse(data) }));
    });
    req.on('error', reject);
    req.write(typeof body === 'string' ? body : JSON.stringify(body));
    req.end();
  });
}

function httpsGet(hostname, path, headers) {
  return new Promise((resolve, reject) => {
    const req = https.request({ hostname, path, method: 'GET', headers }, res => {
      let data = '';
      res.on('data', d => data += d);
      res.on('end', () => resolve({ status: res.statusCode, body: JSON.parse(data) }));
    });
    req.on('error', reject);
    req.end();
  });
}

async function getAccessToken() {
  const cfg = JSON.parse(fs.readFileSync(os.homedir() + '/.config/configstore/firebase-tools.json', 'utf8'));
  const token = cfg.tokens?.access_token;
  if (!token) throw new Error('저장된 access_token 없음. firebase login 먼저 해주세요.');
  return token;
}

async function main() {
  const token = await getAccessToken();
  console.log('액세스 토큰 획득 성공');

  // Firestore에서 모든 사용자 FCM 토큰 조회
  const fsRes = await httpsGet(
    'firestore.googleapis.com',
    `/v1/projects/${PROJECT_ID}/databases/(default)/documents/users`,
    { Authorization: `Bearer ${token}` }
  );

  const docs = fsRes.body.documents || [];
  const tokens = [];
  docs.forEach(doc => {
    const fcmToken = doc.fields?.fcmToken?.stringValue;
    const email = doc.fields?.email?.stringValue || '알 수 없음';
    if (fcmToken) {
      console.log(`  토큰 발견: ${email}`);
      tokens.push(fcmToken);
    }
  });

  if (tokens.length === 0) {
    console.log('저장된 FCM 토큰이 없어요. 앱에서 알림 허용을 먼저 해주세요.');
    return;
  }

  // FCM v1으로 각 토큰에 알림 전송
  let sent = 0;
  for (const fcmToken of tokens) {
    const msgBody = {
      message: {
        token: fcmToken,
        notification: {
          title: '💕 테스트 알림이에요',
          body: '알림이 정상적으로 작동하고 있어요!',
        },
        webpush: {
          notification: { icon: '/icons/Icon-192.png' },
        },
      },
    };
    const res = await httpsPost(
      'fcm.googleapis.com',
      `/v1/projects/${PROJECT_ID}/messages:send`,
      { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      msgBody
    );
    if (res.status === 200) {
      console.log(`전송 성공!`);
      sent++;
    } else {
      console.log(`전송 실패: ${JSON.stringify(res.body)}`);
    }
  }
  console.log(`완료: ${sent}/${tokens.length}개 전송됨`);
}

main().catch(e => { console.error('오류:', e.message); process.exit(1); });
