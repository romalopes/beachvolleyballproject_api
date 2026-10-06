# Phase 5: health API send-test-email tool

## Goal

Add a controlled, admin-visible way to send a one-off test email through the
health API, so an operator can verify that the configured `MAIL_TRANSPORT` is
actually being used to deliver mail. The tool exposes a UI (TO box, content box,
Send button) on the `/settings/api-health` page and keeps the effective transport
visible both in the UI and inside the sent message.

## UI specification (frontend)

Located on the API health diagnostics page (`/settings/api-health`):

- `TO` text box: recipient address for the test email (free-form, trimmed).
- Email `content` box: plain-text body of the test email (multi-line).
- `Send` button: posts the values to `POST /api/v1/health/email/test`.

The section also displays:

- Configured `MAIL_TRANSPORT`: from `GET /api/v1/health/email/transport` (field `configured_transport`).
- Effective transport used for this send: resolved by `MailTransport` at send time, echoed in the API response and rendered into the email.
- Result banner: `{ status: "delivered" or "error" }` plus a short message.

## Backend behaviour

### Routes

Add, inside the existing `namespace :api ... namespace :v1` block in `config/routes.rb`:

- `get "health/email/transport", to: "health#email_transport"`
- `post "health/email/test", to: "health#send_test_email"`

### Controller (HealthController)

- `GET /api/v1/health/email/transport` returns `{ configured_transport, effective_transport }`. Opted out of the test-access gate so health diagnostics stay readable; the value is read-only config.
- `POST /api/v1/health/email/test` is admin-only. Accepts `to`, `content` plus an optional `subject`. Resolves the configured transport with `MailTransport`, resolves the effective delivery name, builds the message with `TestEmailMailer`, and delivers it. Returns `{ configured_transport, effective_transport, status, message, recipients }`.

### Mailer (TestEmailMailer)

- Builds a plain-text message whose subject and body embed the effective transport (e.g. subject `[Email Test] via file`). This lets an operator see, from the message itself, which transport the delivery actually used — including when `MAIL_TRANSPORT` was left as `auto` and the resolver fell back.
- Bypasses `ApplicationMailer#mail` test-mode redirect so this diagnostics send always reaches the caller-supplied recipient.

## Acceptance criteria

- `GET /api/v1/health/email/transport` returns the configured and effective transport as JSON.
- `POST /api/v1/health/email/test` returns 422 when `to` or `content` is missing, 500 with a bounded error when delivery fails, and 200 with `status: "delivered"` otherwise.
- The sent email subject and body contain the effective transport name.
- The UI shows the configured `MAIL_TRANSPORT` and, after a send, the effective transport and result.

