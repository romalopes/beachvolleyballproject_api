# Phase 3: environment, sender, and rollout

## Goal

Make email identity and credentials deploy-time configuration while preserving the current SMTP setup as a supported fallback.

## Implementation

`lib/mail_sender.rb` centralises Action Mailer's default headers:

- `MAIL_FROM` sets the sender.
- `MAIL_REPLY_TO` sets the reply-to address.

`ApplicationMailer` uses those values for every application mailer. If either variable is absent, the historic BVB sender values remain as the compatibility default.

Development and production retain the existing `SMTP_*` configuration when `SMTP_ADDRESS` is set. They no longer choose the delivery method themselves; `MailTransport` does that once for every environment.

The API's `.env.example` documents every relevant variable, including `MAIL_TRANSPORT`, sender headers, Brevo, Resend, and SMTP settings. Credentials belong in the runtime environment or the deployment secret store. They must not be committed to `.env.example`.

## Deployment examples

Brevo:

```dotenv
MAIL_TRANSPORT=brevo
BREVO_API_KEY=...
MAIL_FROM="BVB Project <no-reply@your-domain.example>"
MAIL_REPLY_TO=support@your-domain.example
```

Resend:

```dotenv
MAIL_TRANSPORT=resend
RESEND_API_KEY=re_...
```

SMTP:

```dotenv
MAIL_TRANSPORT=smtp
SMTP_ADDRESS=smtp.example.com
SMTP_USERNAME=...
SMTP_PASSWORD=...
```

Local files:

```dotenv
MAIL_TRANSPORT=file
```

## Rollout order

1. Configure and verify the sender domain with the chosen provider.
2. Add provider credentials and `MAIL_FROM` to the deployment secrets.
3. Deploy with an explicit `MAIL_TRANSPORT`.
4. Send a controlled password-reset or invitation email and inspect the provider activity log.
5. Monitor application logs for `[email_delivery]` fallback warnings.
