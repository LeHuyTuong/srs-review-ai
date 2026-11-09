# SRS Review AI — Admin Web

Flutter Web dashboard for administrators.

## Configure the backend URL

Copy `.env.example` to `.env` and set `SRS_API_BASE_URL` to the FastAPI server's
base address, for example `http://localhost:8000` for local development. Do not
include endpoint paths such as `/admin/remote-config` in this value.

Run/build from this directory so Flutter can read the environment file:

```powershell
flutter run -d chrome --dart-define-from-file=.env
flutter build web --dart-define-from-file=.env
```

The same `SRS_API_BASE_URL` is used by Admin Remote Config and Push Notifications.
The browser must be able to reach the backend, and the backend `CORS_ORIGINS`
must include the Admin Web origin.
