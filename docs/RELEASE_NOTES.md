# Release notes

## v2.0.2 (2026-09-09)

**What's new**
- **New app icon** — Kharcha now has its own logo instead of the default
  Flutter icon.
- **Refreshed look** — updated app theme (Neon Mint).

**Fixed**
- Sign-up confirmation and password-reset emails now link back into the
  app correctly — they previously pointed at a `localhost` address that
  only worked on the developer's own machine, so anyone else's
  confirm/reset link would fail to open Kharcha.
- Confirmation and password-reset emails are now sent through a proper
  mail service, so they arrive reliably instead of hitting a very low
  hourly sending limit.
- A member who leaves or is removed from a household, or deletes their
  account, now correctly disappears from other members' devices on the
  next sync — previously their name/profile could keep showing up until
  a full cache clear.
- Fixed a startup crash that could happen because a notification
  referenced an app icon that no longer existed.

## v2.0.1 (2026-09-08)

Fixes a packaging bug in v2.0.0 (below) that silently broke sign-in for
everyone — the Android manifest was missing the internet permission, so
the app could install but could never actually reach the network. v2.0.0
should not be used; please install v2.0.1 instead.

## v2.0.0 (2026-09-08)

The first release anyone outside the Panicker family can install and use on
their own.

**What's new**
- **Sign up and create your own household** — Kharcha is no longer limited
  to one hardcoded family. Create a household and invite others with a
  code, or join one you were invited to.
- **Invite codes** — share an 8-character code (or a link) to bring someone
  into your household; regenerate or revoke it any time from Household
  management.
- **Leave / manage your household** — admins can promote, deactivate, or
  remove members; anyone can leave.
- **Send feedback** — a Feedback screen (Settings, or from Diagnostics)
  goes straight to the developer.
- **Delete your account** — Settings → Account lets you export your data
  and permanently delete your account and everything you added, without
  affecting your household-mates.
- **Privacy policy & terms** — published and linked from the sign-up
  screen and Settings → About.

**Everything from v1.0 is unchanged**: offline-first expense/income
tracking, budgets, recurring bills, receipts, analytics, exports, and
notifications all work exactly as before — this release just makes the
app usable by more than one family.

**Known limitations**
- Android only for now — iOS requires the developer's own Mac and Apple ID
  to install, so it isn't sideloadable by anyone else yet.
- If you leave a household, other members may still see your name on your
  old expenses/receipts for a little while until their app resyncs.
