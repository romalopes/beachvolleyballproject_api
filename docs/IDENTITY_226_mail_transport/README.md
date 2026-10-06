# Issue 226: email delivery infrastructure

This folder records the plan and implementation for [API issue 226](https://github.com/romalopes/beachvolleyballproject_api/issues/226): portable Action Mailer delivery through Brevo, Resend, SMTP, or local files.

The implementation and this documentation both live in the API repository. The frontend does not send email, so it has no application-code changes for this issue.

## Phases

1. [Audit and transport selection](01_AUDIT_AND_TRANSPORT_SELECTION.md)
2. [HTTP provider adapters](02_HTTP_PROVIDER_ADAPTERS.md)
3. [Environment, sender, and rollout](03_ENVIRONMENT_SENDER_AND_ROLLOUT.md)
4. [Operations and verification](04_OPERATIONS_AND_VERIFICATION.md)

## Result

At boot, the API selects a configured delivery method. `MAIL_TRANSPORT` can force `brevo`, `resend`, `smtp`, or `file`; automatic selection chooses Brevo, then Resend, then SMTP, then file delivery. The test environment remains on Action Mailer's `:test` adapter.
