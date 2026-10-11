/* eslint-disable no-undef */
// Firebase Messaging service worker for web push (Hosting).
// Keep config in sync with lib/firebase_options.dart (web).

importScripts(
  'https://www.gstatic.com/firebasejs/11.0.2/firebase-app-compat.js',
);
importScripts(
  'https://www.gstatic.com/firebasejs/11.0.2/firebase-messaging-compat.js',
);

firebase.initializeApp({
  apiKey: 'AIzaSyDOmcjbdw5avragU8YHX-3KpLJvZekkWLk',
  authDomain: 'circulo-mvp.firebaseapp.com',
  projectId: 'circulo-mvp',
  storageBucket: 'circulo-mvp.firebasestorage.app',
  messagingSenderId: '302212210419',
  appId: '1:302212210419:web:e92ad1c262d7ac6cb1e186',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title || 'Circle';
  const options = {
    body: payload.notification?.body || 'New message',
    data: payload.data || {},
  };
  self.registration.showNotification(title, options);
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const circleId = event.notification.data?.circleId;
  const target = circleId
    ? `/circles/${circleId}`
    : '/';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const client of list) {
        if ('focus' in client) {
          client.navigate(target);
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow(target);
      }
    }),
  );
});
