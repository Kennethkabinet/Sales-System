# Company Deployment Guide (Short / Easy)

This is a **short checklist** to deploy the system inside your office network.

How it works:
- Flutter app → talks to Backend (HTTP + WebSocket)
- Backend → talks to PostgreSQL
- Flutter does **not** connect to PostgreSQL directly

If you want the full detailed version, see: [COMPANY_DEPLOYMENT_GUIDE.md](COMPANY_DEPLOYMENT_GUIDE.md)

---

## 1) Network (Server PC)
1. Pick a **static Server PC IP** (recommended: DHCP reservation on the router).
2. Open inbound TCP **port 3000** on the Server PC firewall.  
3. Later, you will verify from another PC:
   - `http://SERVER_IP:3000/api/status`

---

## 2) PostgreSQL (Server PC)
1. Install PostgreSQL (prefer the same major version as your laptop if possible).
2. Create the role + database (example names):

```sql
CREATE USER synergygraphics WITH PASSWORD 'YOUR_DB_PASSWORD';
CREATE DATABASE sales_system OWNER synergygraphics;
```

---

## 3) Move your database (choose ONE)

### Option A (recommended): portable dump file (.dump)
This is the most reliable way to move schema + data.

Export on laptop:
```powershell
New-Item -ItemType Directory -Path C:\Temp -Force
& "C:\Program Files\PostgreSQL\18\bin\pg_dump.exe" -h localhost -p 5432 -U synergygraphics -d sales_system -Fc --no-owner --no-privileges -f C:\Temp\sales_system_backup.dump
```

Copy to Server PC:
- `C:\Temp\sales_system_backup.dump`

Restore on Server PC:
```powershell
& "C:\Program Files\PostgreSQL\18\bin\pg_restore.exe" -h localhost -p 5432 -U postgres -d sales_system --clean --if-exists --no-owner --role=synergygraphics C:\Temp\sales_system_backup.dump
```

More detailed notes: [OFFICE_DB_MIGRATION_NOTES.md](OFFICE_DB_MIGRATION_NOTES.md)

### Option B: single SQL file (.sql) via pgAdmin (schema + data)
Export on laptop:
- pgAdmin → right-click `sales_system` → Backup…
- Format: `Plain`
- Filename: `C:\Temp\sales_system_full.sql`
- Data Options:
  - Sections: `Pre-data` ON, `Data` ON, `Post-data` ON
  - Type of objects: `Only data` OFF, `Only schemas` OFF
  - Do not save: `Owner` ON, `Privileges` ON

Copy to Server PC:
- `C:\Temp\sales_system_full.sql`

Import on Server PC:
```powershell
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -h localhost -p 5432 -U postgres -d sales_system -v ON_ERROR_STOP=1 -f C:\Temp\sales_system_full.sql
```

More detailed notes: [OFFICE_DB_MIGRATION_SQL_NOTES.md](OFFICE_DB_MIGRATION_SQL_NOTES.md)

---

## 4) Backend (Server PC)
1. Copy the `backend/` folder to the Server PC (example: `C:\SGCO\backend`).
2. Configure `backend/.env` on the Server PC:
   - `PORT=3000`
   - `DB_HOST=localhost`
   - `DB_PORT=5432`
   - `DB_NAME=sales_system`
   - `DB_USER=synergygraphics`
   - `DB_PASSWORD=YOUR_DB_PASSWORD`
   - `JWT_SECRET=YOUR_LONG_RANDOM_SECRET`
3. Install deps + start:

```powershell
cd C:\SGCO\backend
npm ci --omit=dev
node server.js
```

Verify:
- `http://SERVER_IP:3000/api/status`
- `http://SERVER_IP:3000/api/db-test`

---

## 5) Frontend (all PCs)
### What “building the app” means
When you run `flutter build windows --release`, Flutter creates the **Windows app files** (an `.exe` plus required DLLs/assets).

You can run the app immediately by opening the build output folder and double-clicking the `.exe` inside it.

### Build the Windows app (Flutter)
Build the Windows app so it points to your Server PC:

```powershell
cd frontend\sales_frontend
flutter pub get
flutter build windows --release `
  --dart-define=API_BASE_URL=http://SERVER_IP:3000/api `
  --dart-define=WS_BASE_URL=http://SERVER_IP:3000
```

Alternative (no rebuild):
- Put a `sgco_config.json` file next to the app EXE (or in the same folder you run it from).
- Example file is included in the repo at `frontend/sales_frontend/sgco_config.example.json`.

### After the build (what to do next)
1. Find the build output folder:
  - `frontend\sales_frontend\build\windows\x64\runner\Release\`
2. Choose how you will install it on office PCs:
  - **Simple copy (no installer):** copy the entire `Release\` folder to each PC and run the EXE inside it.
  - **Installer EXE (recommended):** use the Inno Setup steps below.
3. Quick check on one PC before distributing:
  - Run the EXE.
  - Confirm login works.
  - Confirm it connects to the server (no connection errors).
4. If Windows shows a missing runtime error (for example, MSVC DLL missing):
  - Install the **Microsoft Visual C++ Redistributable (x64)** on that PC, then run the app again.

### (Optional) Build an installer EXE (Inno Setup)
This repo includes an Inno Setup script: [installer/SGCO.iss](../installer/SGCO.iss)

### What Inno Setup does (simple explanation)
Inno Setup does **not** build Flutter.

Instead, it creates a **Setup installer EXE** that:
- Copies your already-built Flutter app files into `Program Files\KO\SGCO`
- Creates Start Menu + Desktop shortcuts

So the flow is:
1. Build app with Flutter → you get a runnable `.exe`
2. Compile installer with Inno Setup → you get `SGCO_Setup_1.0.exe` (easy to install on office PCs)

What the script does:
- Packages everything under `C:\SGCO\*` into `Program Files\KO\SGCO`
- Expects the main app EXE to be named `SGCO.exe`
- Produces an installer named like `SGCO_Setup_1.0.exe` inside the `installer\` folder

Steps (on your build machine):
1. Install **Inno Setup 6+**.
2. Prepare the folder that the installer will package (File Explorer):
  - Create `C:\SGCO\`
  - Copy everything from:
    - `frontend\sales_frontend\build\windows\x64\runner\Release\`
    into:
    - `C:\SGCO\`

3. Ensure the EXE name matches what the installer expects (File Explorer):
- If your build output is `sales_frontend.exe`, rename it to `SGCO.exe`, OR
- Edit [installer/SGCO.iss](../installer/SGCO.iss) and change `AppExeName` to match your EXE name.

4. Compile the installer (GUI):
  - Open **Inno Setup Compiler**
  - File → Open → select [installer/SGCO.iss](../installer/SGCO.iss)
  - Click **Build → Compile** (or the Compile button)

Result:
- `installer\SGCO_Setup_1.0.exe`

Install on each PC:
- Copy `installer\SGCO_Setup_1.0.exe` to that PC
- Double-click it → Next → Install
- Run the app from the Start Menu shortcut (or Desktop shortcut)

Install the same app on Admin + User PCs.
- Roles control what each user sees after login (no separate admin build needed).

---

## 6) Quick go-live test
- From any PC: `http://SERVER_IP:3000/api/status`
- From any PC: `http://SERVER_IP:3000/api/db-test`
- Login as admin, create an Editor + Viewer, verify permissions.

---

## Security note
Do not store real passwords in shared docs. Keep real secrets only in the Server PC `backend/.env` (or your company password manager).
