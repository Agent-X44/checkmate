# Configure Supabase email delivery with Resend

CheckMate sends verification emails through Supabase Auth. Resend is configured
as Supabase's SMTP provider; the Resend API is not called from the Flutter app
or the FastAPI backend.

## Configure Resend

1. **Revoke any Resend API key that has been shared or exposed**, then create a
   replacement. Do not put the replacement in this repository, the Flutter app,
   or a client-side `.env` file.
2. For real sign-ups, add a domain you control in Resend and publish the DNS
   records Resend provides. A separate mailbox is not required to send from an
   address on the verified domain.
3. For local testing without a domain, `onboarding@resend.dev` can only be used
   within Resend's test-sending restrictions (typically to your own verified
   recipient). It is not a production sender for arbitrary CheckMate users.

## Configure Supabase SMTP

In the CheckMate Supabase project, open **Authentication → Emails → Set up
SMTP** and enter:

| Setting | Value |
| --- | --- |
| SMTP host | `smtp.resend.com` |
| Port | `465` (SSL) or `587` (STARTTLS), as supported by the Supabase form |
| Username | `resend` |
| Password | The replacement Resend API key, entered directly in Supabase |
| Sender email | `onboarding@resend.dev` for restricted testing, or an address on your verified domain |
| Sender name | `CheckMate` |

Use the currently recommended port/security combination shown in the Resend and
Supabase dashboards if their settings differ. Save the configuration in
Supabase; do not copy the SMTP password into the app.

## Check confirmation settings

1. In **Authentication → Sign In / Providers → Email**, enable email
   confirmation if sign-ups are meant to require verification.
2. In **Authentication → URL Configuration**, set the Site URL and allowed
   redirect URLs to the URLs used by the app's confirmation flow. An incorrect
   redirect can make the email link fail even when delivery succeeds.
3. In **Authentication → Emails → Confirm sign up**, review the confirmation
   template and ensure it uses Supabase's confirmation URL/token variable.
4. Sign up with a permitted test recipient, then inspect Supabase **Auth Logs**
   and Resend's delivery logs if the message is not received. Check spam and
   junk folders as well.

The sign-up UI displays Supabase Auth errors so SMTP and configuration failures
are easier to distinguish from invalid credentials.
