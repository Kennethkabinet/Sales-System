# Office DB Migration Notes (Laptop → Office Server)

Goal: move **schema + data** from your laptop PostgreSQL database `sales_system` to the office Server PC.

## 0) What you already confirmed
- Your database name: `sales_system`
- Your DB role (username): `synergygraphics`
- You successfully created an export file: `C:\Temp\sales_system_backup.dump` (Length > 0)

## 1) Export (run on the laptop)
If you don’t already have the dump:

```powershell
# Create export folder (only needed once)
New-Item -ItemType Directory -Path C:\Temp -Force

# Export schema + data to a portable dump file
& "C:\Program Files\PostgreSQL\18\bin\pg_dump.exe" -h localhost -p 5432 -U synergygraphics -d sales_system -Fc --no-owner --no-privileges -f C:\Temp\sales_system_backup.dump
```

When it prompts for a password:
- Type the PostgreSQL password for `synergygraphics` and press Enter
- The cursor won’t move (Windows hides password input) — that’s normal

Confirm the file exists:

```powershell
dir C:\Temp\sales_system_backup.dump
```

## 2) Copy the dump file to the office Server PC
Copy this file from the laptop to the office server using any method:
- USB drive
- Shared folder

File to copy:
- `C:\Temp\sales_system_backup.dump`

## 3) Restore (run on the office Server PC)
### 3.1 Install PostgreSQL
- Install PostgreSQL (ideally same major version as laptop; your laptop is PostgreSQL 18).

### 3.2 Create the role + database (server)
Run these on the server (PowerShell):

```powershell
# Creates the DB role used by the app
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -h localhost -p 5432 -U postgres -d postgres -c "CREATE USER synergygraphics WITH PASSWORD 'YOUR_DB_PASSWORD';"

# Creates the app database owned by that role
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -h localhost -p 5432 -U postgres -d postgres -c "CREATE DATABASE sales_system OWNER synergygraphics;"
```

### 3.3 Restore the dump (server)
Put the dump on the server at a known path, e.g. `C:\Temp\sales_system_backup.dump`, then run:

```powershell
& "C:\Program Files\PostgreSQL\18\bin\pg_restore.exe" -h localhost -p 5432 -U postgres -d sales_system --clean --if-exists --no-owner --role=synergygraphics C:\Temp\sales_system_backup.dump
```

## 4) Point the backend to the restored DB (server)
Update the server’s backend environment file:
- [backend/.env](../backend/.env)

Minimum required values:
- `DB_HOST=localhost`
- `DB_PORT=5432`
- `DB_NAME=sales_system`
- `DB_USER=synergygraphics`
- `DB_PASSWORD=YOUR_DB_PASSWORD`

Restart the backend after changing `.env`.

## 5) Quick verification
On the server PC:
- Start backend
- Open these in a browser (server itself or another PC on the LAN):
  - `http://SERVER_IP:3000/api/status`
  - `http://SERVER_IP:3000/api/db-test`

## Important security note
Do not store real passwords in git or notes files. Use placeholders like `YOUR_DB_PASSWORD` and keep the real password only in the server’s `.env` (or in a company password manager).
