# Company Deployment Guide (On‑Prem)

This guide deploys the Sales & Inventory Management System **inside your company network**.

**How it works (important):**
- Flutter app → connects to **Backend** (HTTP + WebSocket)
- Backend → connects to **PostgreSQL**
- The Flutter app does **not** connect to PostgreSQL directly.

---

1) Make the Server PC IP static (2 good options)

Option A (recommended): DHCP Reservation on the router

On your router / DHCP server, create a “Reservation” that maps the Server PC’s MAC address → a fixed IP (example 192.168.1.10).
This keeps the PC on automatic networking, but the IP never changes.
After saving it, reboot the Server PC or run ipconfig /release then ipconfig /renew.
Option B: Manually set a static IP on the Server PC (Windows)

On the Server PC: Control Panel → Network and Internet → Network and Sharing Center → Change adapter settings
Right‑click your network adapter → Properties → select “Internet Protocol Version 4 (TCP/IPv4)” → Properties
Choose “Use the following IP address” and fill:
IP address: e.g. 192.168.1.10
Subnet mask: usually 255.255.255.0
Default gateway: usually your router, e.g. 192.168.1.1
DNS: your router (192.168.1.1) or your company DNS
Click OK, then confirm with ipconfig.
Tip: Pick an IP outside your DHCP pool (or coordinate with IT) so you don’t accidentally conflict with another device.

2) Open port 3000 on the Server PC (Windows Firewall)

This means allowing inbound connections to the backend service on TCP port 3000.

GUI method

Start Menu → search “Windows Defender Firewall with Advanced Security”
Inbound Rules → New Rule…
Rule Type: Port
TCP → Specific local ports: 3000
Action: Allow the connection
Profile: typically Private (and Domain if this is a domain network); avoid Public unless you know you need it
Name: SGCO Backend 3000
PowerShell method (run as Administrator)

New-NetFirewallRule -DisplayName "SGCO Backend 3000" -Direction Inbound -Protocol TCP -LocalPort 3000 -Action Allow
3) Quick verification

On the Server PC, start the backend (node server.js).
From another PC on the same network, open in a browser:
http://SERVER_IP:3000/api/status
If that page doesn’t load, the usual causes are: wrong IP, firewall rule not applied to the right profile (Private vs Public), backend not running, or the backend only listening on localhost (yours should be on 0.0.0.0, so it’s typically fine).

If you tell me your current Server PC IP (ipconfig output summary is enough) and whether your network is “Private” or “Public” in Windows, I can give the exact best choice (reservation vs manual) and the right firewall profile.

## 0) Quick path (most common)

If you just want the simplest way to go live:
1. Pick a Server PC IP (static) and open port `3000` on that PC.
2. Install PostgreSQL on the server.
3. Create the database and DB user.
4. Choose ONE database setup method:
   - **A. Fresh install** → run `node backend\database\init.js`
   - **B. Use your provided dump** → restore `db\DBSGCO.sql` (steps below)
   - **C. Move existing laptop DB** → `pg_dump` on laptop → `pg_restore` on server
5. Start backend on the server.
6. Build the Windows app with your server IP (`--dart-define=API_BASE_URL=...`).
7. Install the same app on Admin and User PCs (roles control what they see).

---

## 1) What you will deploy (high level)

### Components
- Backend API + WebSocket: [backend/server.js](../backend/server.js)
  - Default port: `3000` (configurable via `PORT`)
  - Health endpoints:
    - `GET /api/status`
    - `GET /api/db-test`
- PostgreSQL database
  - Backend connects via env vars in [backend/db.js](../backend/db.js):
    - `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`
- Frontend (Flutter Windows desktop)
  - API endpoints are compiled in from Dart defines in [frontend/sales_frontend/lib/config/constants.dart](../frontend/sales_frontend/lib/config/constants.dart):
      - `API_BASE_URL` (example: `http://SERVER_IP:3000/api`)
      - `WS_BASE_URL`  (example: `http://SERVER_IP:3000`)

### Admin vs other users
You do **not** need a separate “admin app” vs “user app”. You can ship **one** Windows app to everyone.
- Admin login → shows full dashboard and admin tabs
- Editor/User login → goes directly to sheet editor module
- Viewer login → goes directly to sheet viewer module

Role routing is enforced in [frontend/sales_frontend/lib/main.dart](../frontend/sales_frontend/lib/main.dart).

---

## 2) Decisions you must lock before installing

Fill this in first (it prevents rework later):

- Server PC hostname: `SGCO-SERVER` (example)
- Server PC static IP: `192.168.1.10` (example)
- Backend HTTP/WebSocket port: `3000` (recommended)
- PostgreSQL port: `5432` (default)
- Database name: `sales_system` (recommended)
- Database user for backend: either:
   - `synergygraphics` (matches `db/DBSGCO.sql` ownership/grants), or
   - `sgco_app` (generic recommended name)
- Where backend code lives on server: `C:\SGCO\backend` (example)
- Where logs will be written: `C:\SGCO\logs` (example)

Tip: If you will restore [db/DBSGCO.sql](../db/DBSGCO.sql), use `synergygraphics` as the DB user to avoid owner/grant errors.

### Placeholders used in this guide
- `SERVER_IP`: your Server PC IP address (example: `192.168.1.10`)
- `APP_DB_USER`: the PostgreSQL user the backend will use (example: `synergygraphics`)
- `APP_DB_PASSWORD`: your chosen DB password
- `ADMIN_PASSWORD`: the admin login password you are testing with

PowerShell note:
- Don’t copy placeholders with `<` `>` into PowerShell. Replace the placeholder text with your real values.

Security: never paste real passwords into shared docs/chats.

---

## 3) Server PC setup (Windows) — PostgreSQL + Backend

### 3.1 Server PC prerequisites
Recommended (works well with this repo):
- Windows 10/11 Pro or Windows Server
- Node.js **20 LTS** (Node 18+ required if you want to run the included smoke test that uses `fetch`)
- PostgreSQL **16+** for normal operation.

If you are restoring [db/DBSGCO.sql](../db/DBSGCO.sql):
- That dump says it was created from **PostgreSQL 18.1**.
- Best practice is to restore using the **same major version** of PostgreSQL/psql as the dump (or newer).
- If your server runs an older major version, create a new dump from the laptop using that server version.

Network:
- Server PC must be reachable from client PCs (same LAN/VPN)
- Allow inbound TCP on backend port (default `3000`) from your company network
- PostgreSQL (`5432`) can be **blocked inbound** if backend and DB are on the same server (recommended)

### 3.2 Install PostgreSQL on the server PC
1. Download PostgreSQL installer and install it.
2. During install:
   - Keep the PostgreSQL service set to start automatically.
   - Set a strong password for the `postgres` superuser.
3. After install, confirm the service is running:
   - Windows Services → `postgresql-x64-16` (name may differ)

### 3.3 Create the application database + user
Use **pgAdmin** or **psql**.

Option A (psql — recommended for repeatability):
1. Open “SQL Shell (psql)” on the server
2. Run:

```sql
-- Pick ONE database user name.
-- If you will restore db/DBSGCO.sql, prefer: synergygraphics
-- Otherwise you can use: sgco_app

-- 1) Create DB user for the backend
CREATE USER APP_DB_USER WITH PASSWORD 'APP_DB_PASSWORD';

-- 2) Create database
CREATE DATABASE sales_system OWNER APP_DB_USER;

-- 3) (Optional) tighten defaults
REVOKE ALL ON DATABASE sales_system FROM PUBLIC;
GRANT CONNECT, TEMPORARY ON DATABASE sales_system TO APP_DB_USER;
```

### 3.4 Choose your database setup method

You have 3 valid options. Choose the one that matches your situation.

#### Option A — Fresh install (recommended if you don’t need old data)
Use the repo’s schema + seed logic.

Steps:
1. Copy the repo (or at least the `backend/` folder) to the server, for example `C:\SGCO\backend`.
2. Configure [backend/.env](../backend/.env) on the server.
3. Install deps and run init:

```powershell
cd C:\SGCO\backend
npm ci --omit=dev
node database\init.js
```

This executes [backend/database/schema.sql](../backend/database/schema.sql) and ensures an admin user exists.

Default admin after init:
- username: `admin`
- password: `admin123`

Change it after first login.

#### Option B — Use your provided dump file (db/DBSGCO.sql)
Use this when `db/DBSGCO.sql` is the “source of truth” schema you want on the server.

What this file is:
- [db/DBSGCO.sql](../db/DBSGCO.sql) is a **pg_dump SQL script**.
- It includes ownership/grants for a role named `synergygraphics`.
- It was dumped from **PostgreSQL 18.1**.

What to expect:
- This file looks like it contains **schema objects** (tables, views, functions, constraints, grants).
- It does **not** appear to include table data (no `COPY` / `INSERT` sections were found).
- If you need your real data from the laptop, use **Option C** (pg_dump/pg_restore) instead.

Before you run it:
1. Ensure PostgreSQL/psql on the server is compatible.
   - If `psql` errors on `\\restrict`/`\\unrestrict`, you’re using an older client.
   - Fix by installing a newer PostgreSQL client OR delete those two lines from the file.
2. Create the required role:

```sql
CREATE USER synergygraphics WITH PASSWORD 'YOUR_STRONG_PASSWORD';
CREATE DATABASE sales_system OWNER synergygraphics;
```

Restore the dump (run from the repo root on the server, or copy the file onto the server):

```powershell
# Run as a superuser (postgres) so OWNER/GRANT statements succeed.
psql -h localhost -p 5432 -U postgres -d sales_system -v ON_ERROR_STOP=1 -f db\DBSGCO.sql
```

pgAdmin note:
- You *can* run SQL scripts in pgAdmin, but this dump uses `psql` meta-commands (`\\restrict`/`\\unrestrict`).
- If pgAdmin fails on those lines, remove them and run via `psql`.

After restore:
1. Point the backend to the same DB user you restored with:
   - In [backend/.env](../backend/.env): set `DB_USER=synergygraphics` and `DB_PASSWORD=...`
2. Ensure you can log in:
   - If the dump did not include users, run:

```powershell
cd C:\SGCO\backend
node check-admin.js
```

That script creates/fixes the `admin` account to use password `admin123`.

#### Option C — Transfer the full database from laptop to server (keeps data)
Use this when you already have real company data on your laptop DB and want to move it to the server.

Use the “Laptop → Server PC” steps in section 4 (pg_dump/pg_restore).

### 3.5 (Optional) Allow DB admin access from your laptop (pgAdmin)
If you want to manage PostgreSQL from your laptop (pgAdmin/psql) instead of only on the server:

1. On the **server PC**, locate your PostgreSQL data directory (typical):
   - `C:\Program Files\PostgreSQL\16\data\`
2. Edit `postgresql.conf`:
   - Set `listen_addresses` to allow LAN connections.
     - Safer example: `listen_addresses = 'localhost,192.168.1.10'`
     - Broad example: `listen_addresses = '*'`
3. Edit `pg_hba.conf` and add a rule that only allows your company network:

```conf
host    sales_system     APP_DB_USER     192.168.1.0/24     scram-sha-256
```

4. Restart PostgreSQL service.
5. Windows Firewall: allow inbound TCP `5432` only from trusted IPs (ideally just your laptop).

If backend + DB are on the same server, this is optional. The app will work even if `5432` is blocked inbound.

---

## 4) Migrating your existing database (Laptop → Server PC)

If you already have data on your laptop, you should **migrate** it instead of running fresh init.

### 4.1 Migration approach
Recommended:
- Use `pg_dump` to create a backup file on the laptop
- Copy backup file to the server PC
- Restore into a new `sales_system` database on the server

This preserves data, IDs, and relationships.

Important:
- If you restore a full DB dump, **do not run** `node database\init.js` afterward (it can overwrite the admin password).
- After restore, log in using whatever users exist in the restored DB.
- If you cannot log in (for example, you forgot the admin password), you can run `node check-admin.js` to force-reset/create `admin` with password `admin123`.

### 4.2 On the laptop: create a backup
On the laptop (where the current PostgreSQL DB lives):

1. Stop users from using the app (avoid writes during backup).
2. Create a backup file that includes **schema + data**.

#### Recommended: one portable backup file (`.dump`)
This is the safest option for transferring to another PC.

```powershell
pg_dump -h localhost -p 5432 -U YOUR_LAPTOP_DB_USER -d sales_system -Fc -f sales_system_backup.dump
```

Recommended (avoids restore errors from owners/privileges when moving between PCs):

```powershell
pg_dump -h localhost -p 5432 -U YOUR_LAPTOP_DB_USER -d sales_system -Fc --no-owner --no-privileges -f sales_system_backup.dump
```

Step-by-step notes for this method:
- [OFFICE_DB_MIGRATION_NOTES.md](OFFICE_DB_MIGRATION_NOTES.md)

#### Alternative: a single SQL file (schema + data in SQL)
If you specifically want “schema queries with data” in one readable file:

You can export this SQL file using **pgAdmin** (GUI):
1. Right-click `sales_system` → **Backup…**
2. Format: `Plain`
3. In **Data Options**:
   - Sections: `Pre-data` ON, `Data` ON, `Post-data` ON
   - Type of objects: `Only data` OFF, `Only schemas` OFF
   - Do not save (recommended when moving to a different PC): `Owner` ON, `Privileges` ON

```powershell
pg_dump -h localhost -p 5432 -U YOUR_LAPTOP_DB_USER -d sales_system --no-owner --no-privileges -f sales_system_full.sql
```

Optional flags you may want:
- Add `--clean --if-exists` to drop objects before recreating them during restore.
- Add `--create` to include `CREATE DATABASE` in the SQL file.

Example (single SQL that can recreate everything):

```powershell
pg_dump -h localhost -p 5432 -U YOUR_LAPTOP_DB_USER -d sales_system --no-owner --no-privileges --clean --if-exists --create -f sales_system_full.sql
```

If you don’t have `pg_dump` in PATH, run it from:
- `C:\Program Files\PostgreSQL\YOUR_VERSION\bin\pg_dump.exe`

Step-by-step notes for this method:
- [OFFICE_DB_MIGRATION_SQL_NOTES.md](OFFICE_DB_MIGRATION_SQL_NOTES.md)

### 4.3 Transfer the backup file to the server PC
Copy your export file to the server using one of:
- USB drive
- Shared folder on LAN
- Secure copy method used by your company

File to copy:
- If you used `.dump`: `sales_system_backup.dump`
- If you used `.sql`: `sales_system_full.sql`

### 4.4 On the server PC: restore
1. Create the DB and user (if not already created):

```sql
CREATE USER APP_DB_USER WITH PASSWORD 'APP_DB_PASSWORD';
CREATE DATABASE sales_system OWNER APP_DB_USER;
```

2. Restore the dump into the server database:

```powershell
pg_restore -h localhost -p 5432 -U APP_DB_USER -d sales_system --clean --if-exists sales_system_backup.dump
```

If you exported a **plain SQL** file instead (`sales_system_full.sql`), restore it with `psql`:

```powershell
# If the SQL was created WITHOUT --create, restore into an existing DB:
psql -h localhost -p 5432 -U postgres -d sales_system -v ON_ERROR_STOP=1 -f sales_system_full.sql
```

```powershell
# If the SQL was created WITH --create, run it while connected to any DB (commonly postgres):
psql -h localhost -p 5432 -U postgres -d postgres -v ON_ERROR_STOP=1 -f sales_system_full.sql
```

Notes:
- `--clean --if-exists` drops existing objects in the target DB first.
- If the dump was made by a different owner, you may need to restore as `postgres` and then fix ownership.

3. After restore, run the backend DB test endpoint (section 6) to confirm the backend can connect.

---

## 5) Backend deployment on the Server PC

### 5.1 Configure backend environment
The backend reads configuration from [backend/.env](../backend/.env) and uses:
- [backend/db.js](../backend/db.js) for PostgreSQL connection
- [backend/middleware/auth.js](../backend/middleware/auth.js) for JWT secret (`JWT_SECRET`)

Production checklist for `.env`:
- `JWT_SECRET` is set and long (32+ chars)
- `DB_PASSWORD` is strong and not shared
- `PORT` is fixed (recommend `3000`)
- `DB_HOST=localhost` (if DB is on same server)

Security note:
- Treat `.env` as a secret. Don’t store real passwords in Git or share them in chat.

### 5.2 Start backend manually (first time)

```powershell
cd C:\SGCO\backend
node server.js
```

Confirm from a client PC browser:
- `http://SERVER_IP:3000/api/status`

### 5.3 Run backend as a Windows service (recommended)
Two common options:

Option A: PM2 (simplest for Node apps)
1. Install pm2:

```powershell
npm install -g pm2
```

2. Start and name the process:

```powershell
cd C:\SGCO\backend
pm2 start server.js --name sgco-backend
pm2 save
```

3. Enable startup on boot:

```powershell
pm2 startup
```

Follow the printed instructions (pm2 will show a command you must run as Administrator).

Option B: NSSM (Windows Service wrapper)
- Use NSSM to create a service that runs `node` with `server.js` as argument.

---

## 6) Frontend deployment (Admin and other users)

### 6.1 How the frontend finds the backend
The Flutter app uses compile-time defines:
- `API_BASE_URL` default is currently `http://192.168.1.3:3000/api`
- `WS_BASE_URL` default is currently `http://192.168.1.3:3000`

For company deployment, you should build with your server IP/hostname.

### 6.2 Build Windows release with the correct server address
On a build machine (your laptop is fine):

```powershell
cd frontend\sales_frontend
flutter pub get

flutter build windows --release `
   --dart-define=API_BASE_URL=http://SERVER_IP:3000/api `
   --dart-define=WS_BASE_URL=http://SERVER_IP:3000
```

Resulting build folder (typical):
- `frontend\sales_frontend\build\windows\x64\runner\Release\`

### 6.3 Distribute the app to Admin PCs and User PCs
You can distribute the **same** build to everyone.
- Admin users see admin UI after login.
- Editors/Viewers see their restricted UI after login.

First-day setup flow (recommended):
1. Install the app on the **Admin PC** first.
2. Login as `admin`.
3. Go to **Users** and create accounts for staff:
   - Editors (can edit sheets)
   - Viewers (read-only)
4. Install the same app on user PCs and give them their credentials.

If you want a proper installer, this repo includes an Inno Setup script:
- [installer/SGCO.iss](../installer/SGCO.iss)

That script packages everything under `C:\SGCO\` into an installer.
A practical workflow is:
1. Copy the Windows release build output into `C:\SGCO\`
2. Ensure the exe name matches what the installer expects (`SGCO.exe`) or update the script.
3. Build the installer using Inno Setup.

---

## 7) Connecting PostgreSQL “to the frontend” (what this really means)

The frontend never talks to PostgreSQL directly.
To “connect PostgreSQL to the frontend”, you must:
1. Make backend → PostgreSQL connection work (`DB_*` env vars)
2. Make frontend → backend connection work (`API_BASE_URL` and `WS_BASE_URL`)

Quick validation sequence:
- Server:
  - `GET http://localhost:3000/api/status` returns OK
  - `GET http://localhost:3000/api/db-test` returns “Database connected”
- Client:
  - Flutter app Settings screen shows backend reachable and DB OK (if available in UI)

---

## 8) Testing checklist (before go-live)

### 8.1 Backend smoke checks
From any PC on the network:
- `GET http://SERVER_IP:3000/api/status`
- `GET http://SERVER_IP:3000/api/db-test`

### 8.2 Backend automated smoke test script
The backend includes a basic smoke test:
- [backend/tests/folder_creation_smoke.js](../backend/tests/folder_creation_smoke.js)

Run it on the server PC (or any machine with Node 18+):

```powershell
cd C:\SGCO\backend
$env:API_BASE = "http://SERVER_IP:3000/api"
$env:TEST_USERNAME = "admin"
$env:TEST_PASSWORD = "YOUR_ADMIN_PASSWORD"

node tests\folder_creation_smoke.js
```

Expected output:
- `folder_creation_smoke: PASS`

### 8.3 End-to-end app tests (recommended)
1. Admin login
   - Login as admin
   - Confirm you see admin dashboard/tabs
2. Create users
   - Create an Editor user and a Viewer user
3. Editor client test
   - Login as editor
   - Open a sheet, edit a cell, save
4. Viewer client test
   - Login as viewer
   - Open the same sheet, confirm it is read-only
5. Realtime test (Socket.IO)
   - Open the same sheet on 2 PCs
   - Confirm edits update in near real-time

Go-live “minimum pass”:
- Admin can create/deactivate/reactivate a user
- Editor can edit and save a sheet
- Viewer cannot edit (UI blocks + API blocks)
- `/api/db-test` shows DB connected

---

## 9) Operational notes (basic production hygiene)

### Backups
Minimum backup plan:
- Nightly `pg_dump` from the server DB to a secure location.
Example:

```powershell
pg_dump -h localhost -p 5432 -U APP_DB_USER -d sales_system -Fc -f D:\Backups\sales_system_$(Get-Date -Format yyyyMMdd).dump
```

Also do this at least once:
- Test a restore into a temporary database (verifies backups are actually usable).

### Updating the backend
- Pull/copy new backend code to the server
- Run `npm ci --omit=dev`
- Restart service (`pm2 restart sgco-backend`)

### Updating the frontend
- Rebuild Windows app with the same `--dart-define` values
- Reinstall/replace the client app

---

## 10) Troubleshooting quick map

### Frontend can’t connect
- Confirm client can open `http://SERVER_IP:3000/api/status` in a browser
- Rebuild the Flutter app with correct `API_BASE_URL` / `WS_BASE_URL`
- Check Windows Firewall on the server allows inbound `3000`

### Backend connects but DB test fails
- Verify `.env` values on the server
- Confirm PostgreSQL service is running
- Confirm `DB_NAME` exists and user can connect

### Admin login works but no admin screens
- Confirm admin user has role `admin` in DB (`roles` table)
- Log out and log back in (role routing happens on auth state)
