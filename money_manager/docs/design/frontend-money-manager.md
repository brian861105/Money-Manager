# frontend/money_manager Software Design Specification

## 1. Overview

`frontend/money_manager` is the Flutter client for Micro Ledger. It owns sign-in UI, session state, active ledger selection, record listing, and record creation against the backend HTTP API.

## 2. Goals

- Provide a usable client for OAuth and IAP dev authentication modes.
- Keep API calls centralized in `MicroLedgerApi`.
- Keep UI state in testable controllers.

## 3. Non-Goals

- Enforce backend resource permissions.
- Persist sessions locally.
- Implement full ledger administration or record editing beyond current UI.

## 4. Current State

The app has a signed-out Google sign-in screen and a signed-in ledger home page. It lists ledgers, selects an active ledger, lists records, and creates records.

## 5. Proposed Design

The frontend should keep platform concerns behind adapters, API transport behind `MicroLedgerApi`, and screen state in `AuthController` and `LedgerController`. UI widgets should render controller state and call controller actions.

## 6. Interfaces and Contracts

- Entry point: `lib/main.dart`.
- Root widget: `MoneyManagerApp`.
- API client: `MicroLedgerApi`.
- Controllers: `AuthController`, `LedgerController`.
- Platform adapters: HTTP client factory, URL launcher, Google auth provider.
- Build-time config:
  - `API_BASE_URL`, default `http://localhost:8080`.
  - `API_DEV_EMAIL`, default `you@example.com`.
  - `API_AUTH_MODE`, default `oauth`; dev aliases include `iap-dev`, `iap_dev`, and `iapdev`.
  - `GOOGLE_SERVER_CLIENT_ID`, default empty.
  - `GOOGLE_CLIENT_ID`, default empty.
- Backend routes:
  - `/api/auth/google/login`
  - `/api/auth/google/id-token`
  - `/api/auth/me`
  - `/api/auth/logout`
  - `/api/context/active-ledger`
  - `/api/ledgers`
  - `/api/ledgers/{ledger_id}/records`
- DTOs: `AuthSession`, `Ledger`, and `LedgerRecord`.

## 7. Data Design

Client DTOs mirror backend JSON:

- `AuthSession`: `email`, `user_id`.
- `Ledger`: `id`, `name`, `type`, `owner_email`.
- `LedgerRecord`: `id`, `ledger_id`, `creator_email`, `date`, `category`, `description`, `amount_cents`.

No local persistent storage is currently used.

## 8. Error Handling

- API failures throw `ApiException(statusCode, code, message)`.
- HTTP `204` decodes as an empty object.
- Invalid JSON responses become `invalid_response`.
- `GET /api/auth/me` returning `401` is treated as no current session.
- Amount input strips commas, spaces, `NT$`, `$`, and `元`, then parses as decimal currency and stores rounded cents.
- Invalid amount input sets controller error and avoids an API call.

## 9. Security and Authorization

OAuth mode stores the returned session token in memory and sends it as `Authorization: Bearer <token>`. IAP dev mode sends `X-Goog-Authenticated-User-Email`. The frontend displays backend authorization errors but does not enforce permissions itself.

Tokens, cookies, OAuth codes, ID tokens, and authorization headers must not be logged.

## 10. Observability

No telemetry layer exists today. Future instrumentation should capture screen-level failures and API latency without recording sensitive credentials.

## 11. Compatibility and Migration

Backend route paths, JSON field names, build-time environment names, and auth mode names are contracts for deployment and local development.

## 12. Testing Strategy

- API client tests for request headers, JSON decoding, error decoding, `204` handling, OAuth bearer flow, and IAP dev header flow.
- Auth controller tests for load session, login success/cancel/failure, logout, and switch account.
- Ledger controller tests for initial load, ledger selection, record creation, amount parsing, and error states.
- Widget tests for signed-out, loading, signed-in, empty records, populated records, and form submission states.

## 13. Open Questions

- Whether session tokens should be persisted securely for refresh across app restarts.
- Whether ledger administration should move into the frontend scope.
