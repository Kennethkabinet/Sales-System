# Office DB Migration (Option 2) — Single SQL File (Schema + Data)

This option exports **one readable `.sql` file** from your laptop and imports it on the office Server PC.

✅ **Yes — data is included** as long as you export **Plain** format and you do **not** enable “Only schema” or “Only data”.

---

## A) Export a single SQL file (on the laptop)

### Option A1: pgAdmin 4 (GUI) — easiest
1. In pgAdmin, expand: **Servers → PostgreSQL → Databases**
2. Right-click `sales_system` → **Backup…**
3. Set:
   - **Format**: `Plain`
   - **Filename**: `C:\Temp\sales_system_full.sql`
4. In **Data Options** (the screen in your screenshot), set these:
   - **Sections**: turn ON `Pre-data`, `Data`, `Post-data` (this is schema + data)
   - **Type of objects**: keep BOTH OFF
     - `Only data` = OFF
     - `Only schemas` = OFF
   - **Do not save** (recommended for moving to a different PC):
     - `Owner` = ON
     - `Privileges` = ON
   - `Blobs` = OFF (turn ON only if you know you use large objects)
5. Click **Backup**

Confirm the file exists:

```powershell
dir C:\Temp\sales_system_full.sql
```

### Option A2: Command line (PowerShell)
If you prefer CLI:

```powershell
New-Item -ItemType Directory -Path C:\Temp -Force

& "C:\Program Files\PostgreSQL\18\bin\pg_dump.exe" -h localhost -p 5432 -U synergygraphics -d sales_system --no-owner --no-privileges -f C:\Temp\sales_system_full.sql
```

Optional (helpful when restoring into an existing DB):
- Add `--clean --if-exists` to drop objects before recreating them:

```powershell
& "C:\Program Files\PostgreSQL\18\bin\pg_dump.exe" -h localhost -p 5432 -U synergygraphics -d sales_system --no-owner --no-privileges --clean --if-exists -f C:\Temp\sales_system_full.sql
```

---

## B) Copy the SQL file to the office Server PC
Copy:
- `C:\Temp\sales_system_full.sql`

Use USB drive or a shared folder.

---

## C) Import the SQL file (on the office Server PC)

### Step C1: Install PostgreSQL on the office server
- Install PostgreSQL (prefer the same major version as the laptop when possible).

### Step C2: Create the DB role + database
Run on the server (PowerShell):

```powershell
# Create role
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -h localhost -p 5432 -U postgres -d postgres -c "CREATE USER synergygraphics WITH PASSWORD 'YOUR_DB_PASSWORD';"

# Create database
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -h localhost -p 5432 -U postgres -d postgres -c "CREATE DATABASE sales_system OWNER synergygraphics;"
```

### Step C3: Import the SQL file
Put the SQL file on the server at e.g. `C:\Temp\sales_system_full.sql`, then run:

```powershell
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -h localhost -p 5432 -U postgres -d sales_system -v ON_ERROR_STOP=1 -f C:\Temp\sales_system_full.sql
```

If it prompts for a password, enter the `postgres` password (or whatever superuser you used).

---

## D) Point the backend to the office database (server)
Update:
- `backend/.env`

Set:
- `DB_HOST=localhost`
- `DB_PORT=5432`
- `DB_NAME=sales_system`
- `DB_USER=synergygraphics`
- `DB_PASSWORD=YOUR_DB_PASSWORD`

Restart the backend after editing `.env`.

---

## E) Is this “easy” and reliable?
Yes, it’s easy and works well for small/medium databases.

Notes:
- Plain SQL restore can be slower than `.dump`/`pg_restore`.
- For very large databases, the `.dump` (Custom format) method is usually more reliable.

---

## F) Quick verification
After the backend is running on the server:
- `http://SERVER_IP:3000/api/status`
- `http://SERVER_IP:3000/api/db-test`

---

## Security note
Do not put real passwords in shared notes. Keep real passwords only in the server’s `backend/.env` (or a company password manager).
