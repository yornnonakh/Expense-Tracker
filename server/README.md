# Expense Tracker — Backend

The iOS app is **not self-contained**. Sign-in posts to this server, so the app
cannot log anyone in unless it is running.

## Running it

```sh
cd server
npm install     # first time only
npm run dev     # listens on :8787
```

No `.env` is needed for local work — every value in `src/lib/config.ts` has a
development default. Copy `.env.example` to `.env` only to change something.

## Where the app points

`AppEnvironment.swift` resolves the base URL in this order:

1. `API_BASE_URL` in the process environment (Xcode scheme)
2. `APIBaseURL` in Info.plist
3. Compiled-in default — `http://localhost:8787` for Debug

**Simulator works out of the box. A physical iPhone does not**: `localhost` on
the device means the phone itself. Set `API_BASE_URL` in the scheme to the
Mac's LAN address, e.g. `http://192.168.1.104:8787`, with both on the same
Wi-Fi.

## Do I need the server every time I open the app?

**No — only to sign in.** Once you are signed in, reopening the app works with
the server stopped.

Tokens live in the Keychain, so they survive app restarts and device reboots.
`AuthRepositoryImpl.currentSession()` restores the session from the Keychain
plus the locally cached profile without touching the network, and a refresh
that fails because there is *no network* deliberately keeps you signed in —
only a rejected refresh token ends the session. Expenses and budgets are
served from `LocalExpenseDataSource`, which is the app's source of truth; the
server catches up afterwards.

| Action | Server required? |
|---|---|
| Reopen the app while signed in | **No** |
| Browse, add, edit, delete expenses | **No** — written locally first |
| Sign in for the first time, or after signing out | **Yes** |
| Sync across devices | **Yes** — queued until it is reachable |
| Restore on a fresh install with no cached profile | **Yes** |

The refresh token lasts 30 days and the access token 15 minutes. Staying
offline past 30 days means the next successful contact with the server ends
the session and you sign in again.

## Deploying for real users

The app talks to whatever `APIBaseURL` says. Shipping to the App Store means
running this server somewhere always-on — a laptop is not a host. Existing
users keep working offline if it goes down, but nobody can sign in or sync.

### 1. Deploy the server

A `Dockerfile` is included and works on Fly.io, Render, or Railway.

**The database is a file.** `better-sqlite3` writes to `DATABASE_PATH`, so the
host must give it a **persistent volume**. A container filesystem is recreated
on every deploy; a database inside the image loses every account each time you
ship. The image defaults to `/data/expense-tracker.db` — mount a volume there.

Fly.io, as a worked example:

```sh
fly launch --no-deploy                     # writes fly.toml
fly volumes create data --size 1           # persistent disk
fly secrets set NODE_ENV=production \
  JWT_ACCESS_SECRET="$(openssl rand -base64 48)" \
  JWT_REFRESH_SECRET="$(openssl rand -base64 48)"
fly deploy
```

Mount the volume at `/data` in `fly.toml`:

```toml
[[mounts]]
  source = "data"
  destination = "/data"
```

Point the health check at `/health` — it is deliberately database-free, so a
degraded database reports itself through `/api/v1/health` instead of
triggering a restart loop.

### 2. Set the secrets

Generate two **different** values; the server refuses to boot with
`NODE_ENV=production` otherwise, and equal secrets would let a refresh token
act as a permanent access token.

```sh
openssl rand -base64 48    # JWT_ACCESS_SECRET
openssl rand -base64 48    # JWT_REFRESH_SECRET
```

See `.env.production.example`. Set them as host environment variables rather
than committing a file — `.gitignore` excludes `.env` for this reason.

### 3. Point the app at it

Edit `Config/Info-Release.plist` and replace `APIBaseURL` with your HTTPS
domain. Until you do, the placeholder is the `.invalid` host that
`AppEnvironment.isProductionEndpointConfigured` recognises, so `DIContainer`
logs "Release build has no APIBaseURL configured" and the app runs
offline-only rather than failing in a way nobody can diagnose.

HTTPS is not optional: `Info-Release.plist` carries no
`NSAppTransportSecurity` key, so App Transport Security stays at its strict
defaults and cleartext HTTP is blocked in shipped builds.

### 4. Before submitting

- **Apple Developer Program enrollment** ($99/year). `DEVELOPMENT_TEAM` is
  currently a free account, which has no distribution certificate — archiving
  for the App Store fails until you enroll.
- **Password reset.** Nothing is emailed (see below). A real user who forgets
  their password is locked out permanently, and `set-password` needs shell
  access to the server. Wire up a mail provider before strangers use this.
- **Verify the Release build**, which is not exercised by day-to-day work:

  ```sh
  xcodebuild -scheme expense_tracker -configuration Release \
    -sdk iphonesimulator build
  ```

  Previews are wrapped in `#if DEBUG` because they call DEBUG-only helpers on
  `DIContainer`; without that guard the Release build fails to compile.

## Symptoms and causes

| What you see | Cause |
|---|---|
| Connection / offline banner | Server not running, or a device build pointing at `localhost` |
| "Incorrect email or password." | Genuinely wrong credentials — `APIClient` maps transport failures to a *different* error, so this one is never a dead server |
| "An account already exists for that email." | `users.email` is `UNIQUE`; one account per address |

## Accounts

Email validation is deliberately permissive on both sides (client
`AuthValidator`, server `emailSchema`): `something@something.tld`. **Real
addresses — Gmail included, with dots and `+` tags — work for signup and
sign-in today.** Strict RFC-5322 regexes reject addresses that genuinely
work; the only real authority on deliverability is a confirmation email.

Demo account, recreated by `npm run seed`:

```
demo@expensetracker.app / demo1234
```

## Forgotten passwords: no email is ever sent

`POST /auth/password-reset` is **not wired to a mail provider**. It logs the
request and returns 202 — an honest gap rather than a fake "email sent" that
does nothing. Nothing is delivered, and there is no self-service recovery.

A locked-out account is recovered only by an operator with filesystem access:

```sh
npm run set-password -- <email> <password>
```

This rewrites `password_hash` alone; expenses and budgets stay attached to the
same user id. Passwords are bcrypt (cost 12) and are **not recoverable** — the
script sets a new one, it cannot reveal the old one.

Closing this gap for real users needs a mail provider plus a reset-token table,
a confirm endpoint, and an iOS new-password screen. Email verification on
signup is a separate, larger change (`users.verified_at` and a restricted state
for unverified accounts).
