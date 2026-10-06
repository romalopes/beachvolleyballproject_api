# Phase 1: audit and transport selection

## Goal

Replace duplicated environment-specific `SMTP_ADDRESS` checks with one predictable delivery-method decision made at application boot.

## Findings

Before this change, development and production each selected SMTP when `SMTP_ADDRESS` was set and local file delivery otherwise. The application had no HTTP provider adapter, no explicit selector, and a hard-coded default sender. The test environment already used Action Mailer's `:test` delivery method and must retain that behaviour.

## Implementation

`beachvolleyballproject_api/lib/mail_transport.rb` now exposes `MailTransport.resolve`.

The resolver accepts these explicit values:

| `MAIL_TRANSPORT` | Required configuration | Delivery method |
| --- | --- | --- |
| `brevo` | `BREVO_API_KEY` | `:brevo` |
| `resend` | `RESEND_API_KEY` | `:resend` |
| `smtp` | `SMTP_ADDRESS` | `:smtp` |
| `file` | none | `:file` |

When the variable is empty or `auto`, selection is Brevo, Resend, SMTP, then file delivery. Invalid explicit values, or explicit providers without their required value, log a warning and fall back through the same automatic order. If both HTTP provider keys exist in automatic mode, the resolver warns that Brevo wins and that the deployment should set `MAIL_TRANSPORT` explicitly.

`config/application.rb` registers the custom delivery methods and makes the selection after Action Mailer has been configured. It deliberately exits early in the test environment, preserving `:test` delivery.

## Acceptance criteria

- One resolution path is used by development and production.
- A missing provider configuration cannot leave Action Mailer without a usable delivery method.
- Local development works with no credentials by writing messages to `tmp/mails`.
- Test deliveries stay in the test mailer collection.
