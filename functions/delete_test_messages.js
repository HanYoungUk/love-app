// 클로드가 보낸 테스트 메시지(senderUid == 'claude-test-bot') 전부 삭제.
const fs = require('fs');
const os = require('os');
const https = require('https');

const PROJECT_ID = 'love-app-4e2ac';
const BOT_UID = 'claude-test-bot';

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
  const auth = { Authorization: `Bearer ${token}` };

  // messages 컬렉션 전체 페이지네이션 조회
  let pageToken = '';
  const targets = [];
  do {
    const path =
      `/v1/projects/${PROJECT_ID}/databases/(default)/documents/messages?pageSize=300` +
      (pageToken ? `&pageToken=${encodeURIComponent(pageToken)}` : '');
    const res = await httpsReq('GET', 'firestore.googleapis.com', path, auth);
    const docs = res.body.documents || [];
    for (const doc of docs) {
      if (doc.fields?.senderUid?.stringValue === BOT_UID) {
        targets.push(doc.name); // 전체 리소스 경로
      }
    }
    pageToken = res.body.nextPageToken || '';
  } while (pageToken);

  console.log(`삭제 대상 테스트 메시지: ${targets.length}개`);
  let deleted = 0;
  for (const name of targets) {
    const path = '/v1/' + name.split('/v1/').pop().replace(/^.*\/projects\//, 'projects/');
    // name 형식: projects/PID/databases/(default)/documents/messages/DOCID
    const reqPath = `/v1/${name.substring(name.indexOf('projects/'))}`;
    const res = await httpsReq('DELETE', 'firestore.googleapis.com', reqPath, auth);
    if (res.status === 200) deleted++;
    else console.log('삭제 실패:', res.status, name);
  }
  console.log(`완료: ${deleted}/${targets.length}개 삭제됨`);
}

main().catch(e => { console.error('오류:', e.message); process.exit(1); });
