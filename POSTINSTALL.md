Warmbly is starting. The first start runs the database migrations and can
take a few minutes.

<sso>
**Claim the instance:** open the app and choose **Continue with** your
Cloudron on the sign-in screen; no email or password is needed. The first
person to sign in becomes the owner and platform admin. Later Cloudron
users with access to this app get an ordinary account on their first sign-in.
Set `OIDC_DEFAULT_ORG` in `/app/data/env` to the organization id they should
join; without it each new user gets their own organization.
</sso>
<nosso>
**Claim the instance.** In the app's **Terminal**, run:

    warmblyctl setup-link

Open the link it prints and create the owner account and organization. The
link is single-use; run the command again for a fresh one.
</nosso>

New sign-ups need an invitation by default (`DISABLE_REGISTRATION=invite_only`
in `/app/data/env`). Invite the team from the dashboard.

The admin panel is on the **Admin domain** you chose. Customers' own tracking
domains (a CNAME to your tracking domain) need adding as aliases of this app
so Cloudron issues their certificates.

Settings live in `/app/data/env`. Keep backups: `/app/data/.secrets.env`
holds the keys that decrypt connected mailbox credentials.

Setup guide: [README](https://github.com/marcusquinn/cloudron-warmbly-app/blob/main/README.md).
