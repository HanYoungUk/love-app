const { https } = require('firebase-functions/v1');
const admin = require('firebase-admin');

admin.initializeApp();

exports.deleteAuthUser = https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', 'https://love-app-4e2ac.web.app');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    const idToken = authHeader.substring(7);
    const decoded = await admin.auth().verifyIdToken(idToken);

    if (decoded.email !== 'gksdud9685@loveapp.com') {
      res.status(403).json({ error: 'Forbidden' });
      return;
    }

    const uid = req.body.uid;
    if (!uid) {
      res.status(400).json({ error: 'UID required' });
      return;
    }

    await admin.auth().deleteUser(uid);
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});
