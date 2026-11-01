Warmbly is an open-source platform for B2B cold outreach and email warmup:
multi-step campaigns across many mailboxes, a unified inbox for every reply,
a CRM, and the deliverability tooling that keeps those mailboxes out of spam.

### Features

* **Campaigns:** multi-step sequences with per-mailbox caps and spacing.
* **Unified inbox:** every connected mailbox and reply in one place.
* **CRM:** contacts, pipelines, deals, tasks and meetings.
* **Warmup:** a monitored pool of real mailboxes.
* **Deliverability:** bounces, complaints, suppression lists and open/click
  tracking on your own tracking domain.
* **Hosted forms:** lead-capture pages and embeds.
* **Automations:** visual reply playbooks, with optional AI steps using your
  own provider key.
* **Integrations:** HubSpot, Pipedrive, Slack, Zapier, REST API and webhooks.
* **Realtime:** live presence and updates across the team.

### Cloudron integration

* **Single sign-on:** Cloudron users can sign in with their Cloudron account.
* **Outgoing mail:** sign-in codes, password resets and invitations go
  through the Cloudron mail relay.
* **Own domains:** the dashboard, API, admin panel, tracking and forms each
  get a domain with a Cloudron certificate. Add customers' tracking domains
  as aliases of the app.
* **Backups:** the PostgreSQL database, stored files and the encryption keys
  are in Cloudron backups.

The whole self-host stack (API, event consumer, mailbox worker, tracking,
forms, realtime gateway and NATS) runs in one container on Cloudron's
PostgreSQL and Redis. No cloud account is needed.

[Warmbly](https://github.com/warmbly/warmbly) is open source under the
Apache-2.0 licence. This package is maintained independently of the Warmbly
project.
