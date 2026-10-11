# Circle — Flutter MVP

Mobile app (iOS/Android) **Circle** — Evocative World elearning product — with Google Auth, realtime Firestore, Assignments coin rail, and typed thread. Also runs in **Chrome** (`flutter run -d chrome`) or on Hosting.

Contrato: [docs/13](../docs/13-diseno-tecnico-mvp-firebase.md) · Plan: [docs/15](../docs/15-plan-flutter-mvp.md)

**App online (Hosting):** https://circulo-mvp.web.app

## Setup

1. Instala Flutter 3.x y crea un proyecto Firebase.
2. Habilita **Google** en Authentication y crea Firestore.
3. Configura FlutterFire (`flutterfire configure`) o usa los `firebase_options` del repo.
4. Despliega rules e índices (ver **Deploy** abajo).
5. (Opcional) Seed manual de bootstrap en Firestore:

```
appConfig/settings → { selfPromoteEnabled: true }
```

If the doc is missing, the app creates it when you tap **Become a facilitator** in Settings.

6. Ejecuta en local:

```bash
flutter run -d chrome --web-port=5182
# o dispositivo iOS/Android cuando haya Xcode/emulador
```

7. First facilitator flow:
   - Google login → Settings → **Become a facilitator**
   - Home → FAB `+` → New Circle
   - (Optional) Settings → turn off “Allow new facilitator sign-ups”

## Deploy (Firebase backend + Hosting)

Requiere CLI logueada (`firebase login`) y proyecto **Blaze** (Functions).

```bash
cd circulo
firebase use circulo-mvp

# Backend (rules + indexes + Storage + Cloud Functions)
firebase deploy --only firestore:rules,firestore:indexes,storage,functions

# Cliente web → Hosting
flutter build web --release
firebase deploy --only hosting
```

Todo junto (si Hosting ya tiene `build/web` fresco):

```bash
flutter build web --release
firebase deploy --only firestore:rules,firestore:indexes,storage,functions,hosting
```

URL pública: **https://circulo-mvp.web.app** (también `https://circulo-mvp.firebaseapp.com`).

### Auth / Google en el dominio Hosting

1. Firebase Console → Authentication → Settings → **Authorized domains**  
   Deben figurar al menos:
   - `circulo-mvp.web.app`
   - `circulo-mvp.firebaseapp.com`
   - `localhost` (dev)
2. Si Google Sign-In falla en Hosting: Google Cloud Console → APIs & Services → Credentials → cliente OAuth **Web** → añade esos orígenes a *Authorized JavaScript origins* (y redirect URIs si aplica).

Hosting suele registrar `*.web.app` / `*.firebaseapp.com` automáticamente; comprueba tras el primer deploy.

### Smoke remoto (otro dispositivo)

- [ ] Abrir https://circulo-mvp.web.app
- [ ] Login Google
- [ ] Enviar texto / imagen / PDF
- [ ] PDF o video: portada tras Cloud Function (`generatePdfCover`)
- [ ] Segundo dispositivo ve el hilo en realtime

Logs Functions: `firebase functions:log --only generatePdfCover,notifyOnNewPost`

## Smoke checklist (E1–E5 + media)

- [ ] Login Google crea `users/{uid}` y abre home
- [ ] Facilitador se auto-promueve y ve FAB; member no
- [ ] Dos dispositivos ven posts `free` en realtime
- [ ] Admin publica instruction sticky y resource
- [ ] Coin rail + sheet: marcar objective actualiza la coin
- [ ] Adjuntar imagen (galería) en hilo; otros miembros la ven
- [ ] Cámara: foto y video ≤60 s; video muestra portada tras CF
- [ ] Micrófono: mantener pulsado envía nota de voz; deslizar cancela
- [ ] Adjuntar PDF; aparece portada (tras Cloud Function) y se puede descargar
- [ ] Preview home muestra “Imagen” / “PDF” / “Audio” / “Video” o el pie
- [ ] Rules bloquean lectura de posts sin membership
- [ ] FCM: dos usuarios; A background; B postea; A recibe push; tap abre hilo; sin self-notify

## Storage

1. En Firebase Console → Storage → Get started (bucket por defecto).
2. Deploy rules:

```bash
firebase deploy --only storage,firestore:rules
```

Límites: imagen ≤5 MB, audio ≤5 MB, PDF ≤20 MB, video ≤25 MB.  
Path: `circles/{circleId}/uploads/{uid}/{postId}/{fileName}`.

## Cloud Functions (covers PDF + video)

Requiere plan **Blaze**. Runtime actual: Node 20 (deprecado; migrar a Node 22 antes de oct 2026).

```bash
cd circulo/functions && npm install && npm run build
cd .. && firebase deploy --only functions,storage
```

`generatePdfCover` se dispara al subir PDF o video, escribe `cover.jpg` y actualiza `meta.coverStatus` / `coverStoragePath` / `coverDownloadUrl`.

`notifyOnNewPost` runs when a post is created and sends FCM to the other circle members (tokens in `users/{uid}/fcmTokens`).

## Push (FCM — Fase 2b)

1. **Web VAPID:** Firebase Console → Project settings → Cloud Messaging → Web Push certificates → Generate key pair. Luego:

```bash
flutter run -d chrome --dart-define=FCM_VAPID_KEY=YOUR_KEY
# o al build:
flutter build web --release --dart-define=FCM_VAPID_KEY=YOUR_KEY
firebase deploy --only hosting
```

El service worker `web/firebase-messaging-sw.js` debe desplegarse con Hosting.

2. **iOS APNs:** Firebase Console → Project settings → Cloud Messaging → Apple app configuration → subir APNs Auth Key (o cert). En Xcode, el target Runner ya tiene Push (`Runner.entitlements` + `UIBackgroundModes`).

3. **Android:** `POST_NOTIFICATIONS` en el manifest; `google-services` ya configurado.

### Smoke FCM (dos usuarios)

- [ ] A and B in the same circle; both allow notifications
- [ ] A backgrounds (or closes) the app
- [ ] B posts
- [ ] A gets a push titled with the circle name
- [ ] Tap opens `/circles/{circleId}`
- [ ] B does not get a push for their own post

Logs: `firebase functions:log --only notifyOnNewPost`

## Composer (estilo WhatsApp)

- Texto vacío → micrófono (mantener para grabar, soltar para enviar; deslizar a la izquierda cancela)
- Texto no vacío → enviar
- Clip → Galería / Cámara / Video / Documento (PDF)

## Estructura

```
lib/
  core/theme/
  core/utils/   # download_helper (web/io)
  domain/models/
  data/repositories/
  features/{auth,home,thread,coins,admin,settings}/
  router/
functions/      # Node 20 — PDF/video cover + notifyOnNewPost
build/web/      # output de flutter build web → Hosting
web/firebase-messaging-sw.js  # FCM web service worker
```
