# Phase 2: HTTP provider adapters

## Goal

Provide Action Mailer delivery methods for Brevo and Resend without changing existing mailer call sites.

## Implementation

The API adds a shared `HttpMailDelivery` module and two adapters:

- `lib/brevo_delivery.rb`
- `lib/resend_delivery.rb`

They receive a normal `Mail::Message` through `deliver!`, construct each provider's JSON payload, and submit it over HTTPS. Both use a ten-second open and read timeout and raise a provider-specific error when the service returns a non-success response.

Supported message fields are:

- sender and recipients
- subject
- HTML and plain-text bodies
- reply-to
- CC and BCC
- attachments encoded by the Mail gem

The adapter setup lives in the `email_delivery.transport` initializer. `:brevo` receives `BREVO_API_KEY`; `:resend` receives `RESEND_API_KEY`.

## Compatibility

Existing mailer classes still inherit from `ApplicationMailer` and call `mail` as before. The current application test-mode redirect remains in `ApplicationMailer#mail`; the selected transport delivers the redirected message only after that existing behaviour has applied.

## Failure behaviour

An absent API key fails delivery with a clear provider-specific exception if an adapter is invoked directly. Normal application boot avoids that path because `MailTransport` falls back before selecting an unconfigured provider. HTTP errors include the provider, response status, and a bounded response body for diagnosis.
