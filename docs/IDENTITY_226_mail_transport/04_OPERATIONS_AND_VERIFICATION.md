# Phase 4: operations and verification

## Operational model

Email is selected at boot. Restart the API after changing any delivery variable. In automatic mode, credentials decide the provider; explicit `MAIL_TRANSPORT` is preferable for production because it makes provider changes intentional.

| Situation | Expected result |
| --- | --- |
| No transport credentials | Mail appears in `beachvolleyballproject_api/tmp/mails`. |
| Brevo key only | Brevo delivery is selected. |
| Resend key only | Resend delivery is selected. |
| Both HTTP keys with no selector | Brevo is selected and a warning is logged. |
| Explicit provider missing credentials | A warning is logged and automatic fallback is selected. |
| Test environment | Action Mailer remains on `:test`. |

## Verification checklist

Run these checks in the target deployment environment after adding the selected credentials:

1. Confirm boot logs contain no `[email_delivery]` fallback warning.
2. Trigger a mailer flow such as password reset or an invitation.
3. Confirm the message uses `MAIL_FROM` and `MAIL_REPLY_TO`.
4. Confirm HTML, text, recipient, and reply-to fields at the provider.
5. Send a mail with an attachment if that workflow is used in the application.
6. In development with `MAIL_TRANSPORT=file`, inspect `tmp/mails` instead of sending external email.

## Rollback

Set `MAIL_TRANSPORT=smtp` with the existing SMTP variables, or set `MAIL_TRANSPORT=file` to stop external delivery while retaining mail output for inspection. No database migration is part of issue 226.

## Automated coverage to add when the project schedules mailer testing

- Resolver precedence, explicit choice, and fallback warnings.
- Brevo and Resend payloads for multipart mail, reply-to, CC/BCC, and attachments.
- Boot configuration keeps `:test` delivery in the test environment.
- Application default sender headers honour environment values.
