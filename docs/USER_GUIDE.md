# Kharcha — User Guide

A plain-language walkthrough of everything Kharcha can do, written for
someone who has never opened the app before. If you just want the
install steps, see [`INSTALL.md`](../INSTALL.md) — this guide picks up
right after that and covers the app itself, start to finish.

Kharcha is a shared expense tracker: you (and anyone you invite) log
expenses and income, and the app rolls it up into totals, per-person
breakdowns, budgets, and reports. It works fully offline and syncs
automatically when you have data.

---

## 1. Installing the app

See [`INSTALL.md`](../INSTALL.md) for the download and sideload steps
(Android only, for now). Come back here once the app is installed and
open on your phone.

## 2. Creating your account

1. Open Kharcha and tap **Create an account**.
2. Enter your name, email, and a password (at least 8 characters).
3. Kharcha sends a confirmation email — open it and confirm. If it
   doesn't show up in a minute or two, check spam, or use the **Resend**
   button on the Verify Email screen (there's a 60-second cooldown
   between resends).
4. You can't create or join a household until your email is confirmed —
   this is deliberate, so an unconfirmed/fake address can't be used.

Already have an account? Use **Log in** instead, with the same email
and password.

## 3. Create a household, or join one

Right after your first sign-in, Kharcha shows two options, side by side.
Neither is a "default" — pick whichever fits:

- **Create a household** — for tracking your own spending, or a
  household you'll invite others into. Give it a name. You immediately
  become its **admin**. A household of just you is completely normal —
  the app doesn't treat solo use as a lesser case.
- **Join a household** — if someone already sent you an 8-character
  invite code (formatted like `ABCD-EFGH`), enter it here to join their
  household as a **member**.

You can't belong to more than one household at a time. You can leave
and join a different one later (see §9), but not both at once.

**If you created a household**, you'll immediately see your invite
code on screen with **Copy** and **Share** buttons — send it to whoever
you want to invite. You can skip this ("I'll do this later") and get the
code again anytime from Settings → Household.

## 4. The four main tabs

Once you're in a household, the app has a bottom navigation bar with
four tabs:

| Tab | What it's for |
|---|---|
| **Dashboard** | This month's totals, budget progress, per-member spend, top categories, and recent activity — the home screen |
| **Expenses** | The full list of every expense, with search and filters |
| **Analytics** | Charts: monthly trend, category breakdown, member comparison, payment-method split, day-of-week pattern, top merchants |
| **Settings** | Your profile, household management, categories, budgets, recurring bills, notifications, data export, and account settings |

There's a round **+** button floating above the nav bar on Dashboard
and Expenses:
- **Tap it** to add an expense.
- **Long-press it** to add income instead.

## 5. Logging an expense

This is the thing you'll do most often — it's designed to take under
10 seconds.

1. Tap the **+** button.
2. Enter the **amount**.
3. Pick a **category** (Groceries, Transport, etc.) and a **payment
   method** (Cash, UPI, Card, …) — both are editable lists, see §7.
4. Optionally add a **merchant** name and a **note**.
5. Optionally attach a **receipt photo** — tap the camera icon and
   choose **Camera** (take a new photo) or **Gallery** (pick an
   existing one). Photos are compressed before upload.
6. The date/time defaults to now — tap it to change it if you're
   logging something from earlier.
7. Save. If Kharcha thinks this might be a duplicate of something you
   already logged, it'll flag it before saving — you can save anyway
   or cancel.

Everything you log is visible to everyone in your household — but only
you (or an admin) can edit or delete it.

Working offline? Expenses save locally instantly and sync automatically
the next time you have a connection — you don't need to do anything.

## 6. Logging income

Long-press the **+** button, or open **Settings → Income**. Enter the
amount, a source (salary, freelance, etc.), and an optional note. Income
feeds into your dashboard's net savings figure (spend vs. income), it
isn't just tracked as a separate number.

## 7. Categories and payment methods

Both come pre-loaded with sensible defaults, and both are fully
editable — **Settings → Categories** / **Settings → Payment methods**.
You can add your own, rename, reorder, or archive ones you don't use
(archiving hides a category from the picker without deleting past
expenses that used it).

## 8. Budgets

**Settings → Budgets**, or the "Budgets" card on your Dashboard.

A budget is one month, one amount, and one of four scopes:

| Scope | Covers |
|---|---|
| **Household** | Everyone's spending combined |
| **Member** | One person, across all categories |
| **Category** | One category, everyone combined |
| **Member + category** | One person, one category |

Members can only set budgets that target themselves (Member, or Member
+ category); admins can set any scope for anyone.

When creating a budget you can also:
- Turn on **"Roll over unspent budget"** — leftover amount carries into
  next month instead of resetting.
- Tick **"Also create for the next 12 months"** to set up a whole year
  at once instead of recreating it monthly.
- Set an **alert threshold** (defaults to 80%) — you'll get a
  notification when you cross it, and another if you go over.

## 9. Recurring bills

**Settings → Recurring.** For anything that repeats — rent, a
subscription, a salary credit — set it up once instead of re-entering it
every month.

Fill in a title, amount, category/payment method, and how often it
repeats: **Daily, Weekly, Monthly,** or **Yearly** (with an interval, so
"every 2 weeks" works too; monthly/yearly rules also let you pin a
specific day of the month).

Turn on **Auto-post** if you want it to log itself automatically on the
due date with no confirmation — leave it off if you'd rather approve
each occurrence first (you'll get a "Pending confirmations" prompt on
the Dashboard when one comes due).

## 10. Reports and analytics

The **Analytics** tab has seven views for the selected month: monthly
trend, category breakdown, member comparison, payment-method split,
day-of-week pattern, top merchants, and month-over-month change by
category. Use the month selector at the top of Dashboard/Analytics to
look at a different month.

On the **Expenses** tab, tap the filter icon to narrow the list by date
range, member, category, payment method, "only mine," or "only with
receipts" — useful for answering a specific question ("how much did I
spend on dining last month?") without scrolling.

## 11. Exporting your data

**Settings → Export.** Choose a date range (this month / last month /
all time / custom), optionally filter by member or category, and pick a
format:
- **CSV** — for opening in Excel/Sheets. You can include a second CSV
  for income and/or a full transaction-list appendix.
- **PDF report** — a readable summary.

Admins additionally get **Export full backup (JSON)** — every row in
the household, useful as a safety copy before doing anything drastic.

## 12. Managing your household (admins)

**Settings → Household** (tap your household's name). Admins can:

- **Rename** the household.
- **View, copy, share, regenerate, or revoke** the invite code. A code
  expires after a set number of days and a set number of uses (you
  choose both when regenerating) — if a friend says "my code doesn't
  work," it's likely expired or used up; regenerate a fresh one.
- **Remove a member.** Their past expenses stay in the household's
  history (marked "(left)") — nothing is deleted, they just can't add
  anything new.
- **Promote/demote** members between admin and member.
- **Delete the household entirely** — this is destructive and asks you
  to type the household's name to confirm; export a full backup first
  if there's any chance you'll want the data later.

Any member (not just admins) can **leave a household** from the same
screen, at any time.

## 13. Notifications

**Settings → Notifications.** Everything here runs on-device — no push
notifications, so it works with no extra setup:

- **Daily reminder** — a nudge at a time you pick, in case you haven't
  logged anything that day.
- **Budget alerts** — when you cross a budget's warning threshold or go
  over it.
- **Monthly summary** — household spend/income, posted on the 1st of
  each month.
- **Recurring due** — when a recurring bill is coming up.
- **Sync issues** — if something hasn't synced in 24+ hours (usually
  means you've been offline a while).

For reminders to actually fire reliably, allow notifications when
Android asks, and set **Settings → Apps → Kharcha → Battery →
Unrestricted** on your phone (Android can otherwise silently kill
scheduled reminders in the background).

## 14. Your account

**Settings → Profile** (top of the list, shows your name) lets you
change your display name and colour. **Settings → Change password** is
right below it.

**Sign out** clears everything stored on this phone but keeps your
account and data in the cloud — sign back in anytime and it all comes
back.

## 15. Deleting your account

**Settings → Delete account.** This is permanent — you're offered
**Export my data** first (do this if you want a copy), then confirming
deletes your account and everything in it. Uninstalling the app does
**not** do this by itself — your account stays in the cloud until you
delete it from inside the app.

Full detail on exactly what gets deleted:
[Privacy Policy](https://vineet2102.github.io/Kharcha-App/privacy.html).

## 16. Staying in sync / troubleshooting

- Kharcha checks for updates itself and shows a banner when a new
  version's ready — just reinstall over the old one; your data isn't
  touched (it all lives in the cloud).
- **Settings → Sync now** forces an immediate sync if you don't want to
  wait for it to happen automatically.
- **Settings → Clear local cache and re-download** wipes what's stored
  on this phone and re-downloads everything from the server — you stay
  signed in. Useful if something on this phone looks wrong; harmless
  otherwise, since the phone is just a mirror of the cloud copy.
- **Settings → Diagnostics** has technical detail if you need to
  describe a problem to whoever gave you the app.
- **Settings → Send feedback** goes straight to the app's maintainer.

## 17. Common questions

**"I didn't get the confirmation email."** Check spam first. If it's
genuinely missing, use **Resend** on the Verify Email screen instead of
starting sign-up over.

**"My invite code doesn't work."** Codes expire and have a use limit —
ask your household's admin to check Settings → Household and regenerate
one.

**"Can I use this alone, without inviting anyone?"** Yes — creating a
household of just yourself is completely normal and fully supported.

**"What happens to my data if I uninstall the app?"** Nothing — it's
all in the cloud. Reinstall and sign back in and everything's there.

**"Is my data private from other households?"** Yes — every household's
data is completely isolated from every other one; you only ever see
your own.

---

Questions this guide doesn't answer? Contact
**vineetrpanicker2002@gmail.com**, or see the
[Privacy Policy](https://vineet2102.github.io/Kharcha-App/privacy.html)
and [Terms of Use](https://vineet2102.github.io/Kharcha-App/terms.html).
