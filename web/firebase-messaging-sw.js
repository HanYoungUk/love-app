importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBZNCYJOWxUOC-73lARl6P85iCQNcvFBaU',
  appId: '1:498711263043:web:50bb4df6f8358c4c3921f6',
  messagingSenderId: '498711263043',
  projectId: 'love-app-4e2ac',
  authDomain: 'love-app-4e2ac.firebaseapp.com',
  storageBucket: 'love-app-4e2ac.firebasestorage.app',
});

const messaging = firebase.messaging();

// FCM 백그라운드 메시지 (Android/Chrome)
messaging.onBackgroundMessage(function(payload) {
  const notification = payload.notification || {};
  self.registration.showNotification(notification.title || 'Love App 💕', {
    body: notification.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    vibrate: [200, 100, 200],
  });
});

self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  event.waitUntil(
    clients.openWindow('/')
  );
});
