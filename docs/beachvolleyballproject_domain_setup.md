# BeachVolleyballProject / BeachVolleyballHub — Domain, DNS and Email Setup

**Scope:** Cloudflare domain registration and DNS, Vercel React frontend, Render Rails API, Cloudflare R2 object storage, and transactional email via **Resend or Brevo**.

> **Domain placeholder:** This guide uses `beachvolleyballhub.com` as an **example**, not a confirmed purchased or available domain. Replace it everywhere with the domain you actually register. The repository/application may still use the BeachVolleyballProject name internally.

## 1. Proposed architecture

| Public hostname | Responsibility | Service |
|---|---|---|
| `beachvolleyballhub.com` | Main React website | Vercel |
| `www.beachvolleyballhub.com` | Redirect to main website | Vercel |
| `api.beachvolleyballhub.com` | Rails JSON API | Render |
| `mail.beachvolleyballhub.com` (optional) | Dedicated email sending subdomain | Resend **or** Brevo |
| `assets.beachvolleyballhub.com` (optional) | Public assets, only if explicitly configured | Cloudflare R2 custom domain |

Cloudflare manages the DNS records; it does **not** have to host the React frontend or Rails API. R2 is storage and should not be confused with the PostgreSQL database (Neon or Supabase).

```text
Browser → beachvolleyballhub.com → Vercel (React)
                                   │
                                   └─ HTTPS → api.beachvolleyballhub.com → Render (Rails)
                                                                       ├─ Neon/Supabase PostgreSQL
                                                                       ├─ Cloudflare R2 objects
                                                                       └─ Resend OR Brevo HTTP email API
Cloudflare Registrar/DNS → authoritative DNS for all hostnames
```

## 2. Useful links

| Purpose | Link |
|---|---|
| Cloudflare dashboard | https://dash.cloudflare.com/ |
| Cloudflare Registrar | https://www.cloudflare.com/products/registrar/ |
| Cloudflare DNS documentation | https://developers.cloudflare.com/dns/ |
| Cloudflare R2 | https://dash.cloudflare.com/ (select account → R2) |
| Vercel dashboard | https://vercel.com/dashboard |
| Vercel custom domains | https://vercel.com/docs/domains/set-up-custom-domain |
| Render dashboard | https://dashboard.render.com/ |
| Render custom domains | https://render.com/docs/custom-domains |
| Render Cloudflare DNS | https://render.com/docs/configure-cloudflare-dns |
| Resend dashboard | https://resend.com/overview |
| Resend domains | https://resend.com/domains |
| Resend domain documentation | https://resend.com/docs/dashboard/domains/introduction |
| Resend Rails integration | https://resend.com/docs/send-with-rails |
| Resend email API | https://resend.com/docs/api-reference/emails/send-email |
| Brevo dashboard | https://app.brevo.com/ |
| Brevo domain authentication | https://help.brevo.com/hc/en-us/articles/12163873383186-Authenticate-your-domain-with-Brevo-Brevo-code-DKIM-DMARC |
| Brevo API docs | https://developers.brevo.com/docs/send-a-transactional-email |
| Brevo domain setup | https://help.brevo.com/hc/en-us/articles/35337929909778-Set-up-your-domain-in-Brevo |
| BVP frontend repository | https://github.com/romalopes/beachvolleyballproject |
| BVP Rails API repository | https://github.com/romalopes/beachvolleyballproject_api |
| Existing BVP dev API | https://beachvolleyballproject-dev.onrender.com |

## 3. Phase 1 — Register domain with Cloudflare

1. Open [Cloudflare Registrar](https://www.cloudflare.com/products/registrar/) and check whether your desired domain is available.
2. Purchase the domain and enable automatic renewal and account 2FA.
3. In [Cloudflare](https://dash.cloudflare.com/), select the domain → **DNS → Records**.
4. Keep Cloudflare as the authoritative DNS provider. Avoid adding records at another provider.
5. Record the purchased spelling and replace every `beachvolleyballhub.com` placeholder below.

## 4. Phase 2 — Configure frontend on Vercel

1. Open [Vercel](https://vercel.com/dashboard), select the BVP frontend project → **Settings → Domains**.
2. Add `beachvolleyballhub.com` and `www.beachvolleyballhub.com`.
3. Set `beachvolleyballhub.com` as the primary domain and redirect `www` to it.
4. Copy **the exact DNS values shown in your Vercel project** into Cloudflare DNS.

Example only (Vercel may show project-specific values):

| Type | Name | Target | Proxy |
|---|---|---|---|
| A | `@` | `76.76.21.21` (only if Vercel confirms) | DNS only initially |
| CNAME | `www` | Vercel-supplied CNAME | DNS only initially |

Wait for Vercel to confirm DNS verification and issue its HTTPS certificate. Keep the old `*.vercel.app` deployment for troubleshooting.

## 5. Phase 3 — Configure Rails API on Render

1. In [Render](https://dashboard.render.com/), open the **correct production Rails service**. Do not accidentally map the development service to production.
2. Under **Settings → Custom Domains**, add `api.beachvolleyballhub.com`.
3. Add the DNS record in Cloudflare:

| Type | Name | Target | Proxy |
|---|---|---|---|
| CNAME | `api` | **Your production** `*.onrender.com` hostname | **DNS only** until Render verifies and issues SSL |

4. Return to Render and verify the domain and TLS certificate. Cloudflare proxying can be considered later but is not necessary.
5. Keep the original `onrender.com` hostname as a fallback. Do not confuse it with the existing `beachvolleyballproject-dev.onrender.com` dev service.

## 6. Phase 4 — Update application configuration

### Vercel production environment

In **Project → Settings → Environment Variables**, set the actual frontend variable name used by your codebase:

```dotenv
VITE_API_BASE_URL=https://api.beachvolleyballhub.com/api/v1
```

Rebuild/redeploy the frontend: Vite environment variables are embedded at build time. Confirm that your API client actually reads `VITE_API_BASE_URL` before using this example.

### Rails CORS

In the Rails API, adjust `rack-cors` to allow the production frontend and intentional development/preview origins, for example:

```ruby
# config/initializers/cors.rb — illustrative; merge with existing config
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins 'https://beachvolleyballhub.com',
            'https://www.beachvolleyballhub.com'
    resource '/api/*',
             headers: :any,
             methods: %i[get post put patch delete options]
  end
end
```

If using cookie-based authentication, configure `credentials: true` and explicit trusted origins, plus cookie SameSite/Secure settings; do not use `*` with credentials. If using bearer tokens, ensure authorization headers and preflight requests work. Keep local `http://localhost:5174` as an explicit development origin where appropriate.

### Rails host and URL configuration

Verify host authorization if enabled, default URL options for mailers, redirects, OAuth callback URLs, password reset links, and any allowed frontend return URLs. Example production variables:

```dotenv
FRONTEND_URL=https://beachvolleyballhub.com
API_BASE_URL=https://api.beachvolleyballhub.com
```

These are illustrative names; check the actual app code and existing environment variables. Configure Google OAuth and other third-party callback/origin allowlists to match the actual auth flow. Keep secrets only in Render environment settings.

## 7. Phase 5 — Email: choose Resend OR Brevo

**Recommendation:** Choose **one primary transactional sender** for BVP initially. Both providers can be verified on separate sending subdomains if you want a fallback, but avoid overlapping SPF/DKIM names and avoid sending duplicate emails. Use an HTTP API from Render rather than depending on outbound SMTP availability.

Typical messages: invitation to claim PlayerProfile/CoachProfile, invitation to join an organisation, account verification, password reset, and security/login alerts. Send only necessary messages; rate-limit invitation and reset endpoints.

### Option A — Resend

1. Open [Resend Domains](https://resend.com/domains) → **Add Domain**.
2. Choose `mail.beachvolleyballhub.com` for transactional sending, or the root domain if you specifically want sender addresses like `no-reply@beachvolleyballhub.com`.
3. Copy the **exact** verification, SPF, DKIM, and optional return-path DNS records shown by Resend into Cloudflare. Do not invent the record values.
4. Set mail-related CNAMEs to **DNS only**. TXT/MX records are not proxied.
5. Verify the domain in Resend, create an API key, and store it in Render's secret environment variables.
6. Configure Rails to send via Resend's HTTPS API (using an appropriate adapter/service), and test an invitation and password-reset email end to end.

Example conceptual settings:

```dotenv
EMAIL_PROVIDER=resend
RESEND_API_KEY=<secret from Resend>
MAIL_FROM=no-reply@mail.beachvolleyballhub.com
```

These environment variable names require corresponding implementation in the Rails code. See [Resend Rails documentation](https://resend.com/docs/send-with-rails).

### Option B — Brevo

1. Open [Brevo](https://app.brevo.com/) → **Settings → Senders, Domains, IPs → Domains** (menu names may differ).
2. Add the sending domain, e.g. `mail.beachvolleyballhub.com`.
3. Select manual DNS authentication or supported automatic Cloudflare setup.
4. Copy Brevo's verification TXT, DKIM TXT/CNAME, and DMARC guidance into Cloudflare. Use exact values supplied for your account.
5. Verify the domain, configure an approved sender address, and generate a **Brevo API key** for transactional email.
6. Store it in Render and implement the Brevo transactional HTTPS API integration; test account email flows.

```dotenv
EMAIL_PROVIDER=brevo
BREVO_API_KEY=<secret from Brevo>
MAIL_FROM=no-reply@mail.beachvolleyballhub.com
```

Again, these names are examples and must match the Rails implementation. Reference: [Brevo transactional email API](https://developers.brevo.com/docs/send-a-transactional-email).

### Email DNS design: SPF, DKIM, DMARC

- **SPF:** only **one SPF TXT record per hostname**; merge authorized senders if necessary rather than adding multiple competing SPF records. A dedicated mail subdomain reduces collisions.
- **DKIM:** use each provider's own selector(s); distinct selectors can coexist, but avoid overlapping names.
- **DMARC:** start with a monitoring policy if appropriate, review reports and alignment, then tighten enforcement. There should be only one DMARC policy record per exact hostname.
- **MX:** do not change the root domain's incoming-mail MX records just to enable outbound transactional email. Provider-specified MX records may apply to a dedicated return-path subdomain.
- **Sender address:** DNS verification does **not** create an inbox. If you want `support@beachvolleyballhub.com` to receive messages, arrange mailbox hosting or forwarding separately.
- **Resend + Brevo simultaneously:** if using both, prefer distinct sending subdomains (e.g. `mail` and `notify`) and independent provider configurations. You can still use a consistent reply-to address with a real mailbox.

## 8. Phase 6 — Cloudflare DNS inventory (illustrative)

| Record | Host | Destination / value | Purpose |
|---|---|---|---|
| A | `@` | Value supplied by Vercel | Main frontend |
| CNAME | `www` | Value supplied by Vercel | Website alias |
| CNAME | `api` | Production Render hostname | Rails API |
| TXT/CNAME/MX | Provider-defined mail hostnames | Exact Resend **or** Brevo values | Email authentication / return path |
| TXT | `_dmarc.mail` or provider-required hostname | Carefully chosen DMARC policy | Sending-domain protection |
| CNAME | `assets` (optional) | R2-provided target after custom-domain setup | Public R2 assets |

Do not add the optional R2 hostname until your application needs it and Cloudflare R2 has explicitly provided the custom-domain configuration. Avoid exposing private objects publicly.

## 9. Phase 7 — Verify DNS, HTTPS and API

Run from a terminal after DNS changes:

```bash
dig +short beachvolleyballhub.com A
dig +short www.beachvolleyballhub.com CNAME
dig +short api.beachvolleyballhub.com CNAME
curl -I https://beachvolleyballhub.com
curl -I https://www.beachvolleyballhub.com
curl -I https://api.beachvolleyballhub.com
```

A `401`, `404`, or `405` on the API root can be normal; test an **actual existing health endpoint** and a representative API endpoint as well. Check certificate validity, redirects, browser network requests, CORS preflights, OAuth login, invitations, password reset, R2 uploads, and outbound email delivery.

For email DNS, use the exact hostnames shown in the provider dashboard:

```bash
dig TXT mail.beachvolleyballhub.com
dig TXT _dmarc.mail.beachvolleyballhub.com
```

Check DKIM selector records by their **actual provider-supplied names**; the examples above alone do not prove email authentication is complete.

## 10. Recommended rollout order

1. Purchase the chosen domain in Cloudflare.
2. Add Vercel main + `www` custom domains, configure DNS, verify HTTPS.
3. Add **production** Render API custom domain, verify DNS/HTTPS.
4. Update Vercel API URL, Rails CORS, frontend/host/mail URLs and OAuth settings; redeploy.
5. Choose Resend **or** Brevo; authenticate a sending domain and implement HTTP API email delivery.
6. Test full flows: sign-in, invitation, profile claim, password reset, mail delivery, database connectivity and R2 objects.
7. Keep original Vercel/Render provider URLs until the new domain is stable.

## 11. Troubleshooting

- **Vercel domain pending:** confirm records match Vercel's *project-specific* instructions; remove conflicting apex A/AAAA records.
- **Render TLS pending:** keep the `api` CNAME DNS-only while Render verifies it.
- **Browser reports CORS + 502:** investigate Render availability/memory/restarts first; a gateway failure may omit CORS headers, making CORS look like the root cause.
- **Frontend still calls old API:** redeploy after changing Vite variables; inspect the built JavaScript and network tab.
- **Email provider not verified:** inspect the provider-specific DKIM/SPF/verification hostnames and DNS propagation; don't guess values.
- **Email sends but is not delivered:** inspect provider event logs, sender verification, SPF/DKIM/DMARC alignment, bounces and spam placement.
- **Email arrives but replies bounce:** configure a real inbox/forwarding service and Reply-To.
- **OAuth fails:** add the new production origins and exact redirect URIs to the OAuth provider.

## 12. Completion checklist

- [ ] Actual domain purchased and substituted for examples
- [ ] Cloudflare DNS zone active; 2FA enabled
- [ ] Main Vercel domain verified with HTTPS
- [ ] `www` redirects to main domain
- [ ] Production Render service verified at `api` with HTTPS
- [ ] Frontend calls new API hostname
- [ ] CORS, auth, callback and mailer URLs updated
- [ ] One primary email provider selected
- [ ] Email domain verified; SPF/DKIM/DMARC checked
- [ ] API key stored securely in Render, not committed to Git
- [ ] Invitation and password reset emails tested
- [ ] Real Reply-To inbox configured if required
- [ ] PostgreSQL and R2 functionality tested
- [ ] Existing provider URLs retained for rollback

---

**Important:** Domain availability, exact DNS targets, current provider limits, and account-specific settings must be checked in each provider's dashboard before applying changes. This document is a setup plan, not a claim that the domain or configuration is already active.
