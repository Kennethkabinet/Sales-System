# Quick Start Guide - User Management Module Deployment

## Prerequisites
- PostgreSQL database running
- Node.js backend server
- Flutter frontend app
- Admin account exists (default: admin/admin123)

## Deployment Steps

### 1. Database Migration (5 minutes)

**Option A: Using psql command line**
```bash
cd backend/database
psql -U your_username -d sales_system -f migration_user_module.sql
```

**Option B: Using pgAdmin or database GUI**
1. Open your PostgreSQL client
2. Connect to your database
3. Open and execute `backend/database/migration_user_module.sql`
4. Verify success message in output

**Option C: For new installations**
If this is a fresh installation, the schema.sql already includes all changes:
```bash
psql -U your_username -d sales_system -f schema.sql
```

### 2. Backend Deployment (2 minutes)

No additional packages needed. Changes are code-only.

```bash
cd backend
# If backend is running, restart it
# Ctrl+C to stop, then:
npm start
# OR
node server.js
```

Backend changes:
- ✅ Registration endpoint removed
- ✅ User management endpoints added
- ✅ Sheet access control updated
- ✅ Edit tracking implemented

### 3. Frontend Deployment (2 minutes)

No additional packages needed. Changes are code-only.

```bash
cd frontend/sales_frontend
# If app is running, stop it (Ctrl+C) then:
flutter run
# OR for release build
flutter build windows
```

Frontend changes:
- ✅ Registration screen removed
- ✅ User Management screen added
- ✅ API service updated
- ✅ Dashboard navigation updated
- ✅ Login screen updated

### 4. Testing (10 minutes)

#### Test 1: Login
1. Open the app
2. Login with admin credentials
3. ✅ Should see "Users" tab in navigation (admin only)

#### Test 2: Create User
1. Click "Users" tab
2. Click "Create User" button
3. Fill in details:
   - Full Name: Test User
   - Username: testuser
   - Email: test@example.com
   - Password: test123
   - Role: User
4. Click "Create"
5. ✅ User should appear in list

#### Test 3: User Login
1. Logout from admin
2. Login with newly created user (testuser/test123)
3. ✅ Should see Sheet tab
4. ✅ Should NOT see Users tab

#### Test 4: Sheet Access
1. As regular user, go to Sheet tab
2. Create a new sheet
3. Edit some cells
4. ✅ Changes should save
5. ✅ Edit tracking recorded in database

#### Test 5: Registration Disabled
1. Logout
2. On login screen
3. ✅ Should NOT see "Register" link
4. ✅ Should see "Contact your administrator" message

#### Test 6: Deactivate/Reactivate User
1. Login as admin
2. Go to Users tab
3. Click menu (⋮) on test user
4. Select "Deactivate"
5. ✅ User status changes to INACTIVE
6. Logout and try to login as test user
7. ✅ Login should fail
8. Login as admin, reactivate the user
9. ✅ User can login again

### 5. Verify Database Changes

```sql
-- Check new role exists
SELECT * FROM roles WHERE name = 'editor';

-- Check new user table columns
SELECT column_name FROM information_schema.columns 
WHERE table_name = 'users' 
AND column_name IN ('deactivated_at', 'deactivated_by', 'created_by');

-- Check sheet edit history table exists
SELECT EXISTS (
   SELECT FROM information_schema.tables 
   WHERE table_name = 'sheet_edit_history'
);

-- Check sheets table has edit tracking
SELECT column_name FROM information_schema.columns 
WHERE table_name = 'sheets' 
AND column_name = 'last_edited_by';
```

## Troubleshooting

### Issue: Migration script fails
**Solution**: Check if database is already migrated. Safe to run multiple times.

### Issue: Backend server won't start
**Symptoms**: Error about missing columns
**Solution**: 
1. Make sure migration ran successfully
2. Check PostgreSQL connection
3. Verify database name in backend/db.js

### Issue: Frontend shows old registration screen
**Solution**: 
1. Stop the Flutter app completely
2. Run `flutter clean`
3. Run `flutter pub get`
4. Run `flutter run` again

### Issue: "Users" tab not visible for admin
**Solution**: 
1. Logout and login again
2. Check user role in database: `SELECT username, r.name as role FROM users u JOIN roles r ON u.role_id = r.id WHERE username = 'admin';`
3. Make sure role is 'admin'

### Issue: Sheet edit history not recording
**Solution**: 
1. Verify sheet_edit_history table exists
2. Check backend logs for errors
3. Make sure migration ran successfully

## Rollback Plan

If you need to rollback:

### Backend
```bash
cd backend
git checkout HEAD~1 routes/auth.js routes/users.js routes/sheets.js
```

### Frontend
```bash
cd frontend/sales_frontend
git checkout HEAD~1 lib/screens/ lib/services/api_service.dart
```

### Database
```sql
-- Rollback is not recommended as it may cause data loss
-- If absolutely necessary:
DROP TABLE IF EXISTS sheet_edit_history;
ALTER TABLE sheets DROP COLUMN IF EXISTS last_edited_by;
ALTER TABLE users DROP COLUMN IF EXISTS deactivated_at;
ALTER TABLE users DROP COLUMN IF EXISTS deactivated_by;
ALTER TABLE users DROP COLUMN IF EXISTS created_by;
DELETE FROM roles WHERE name = 'editor';
```

## Post-Deployment Checklist

- [ ] Database migration completed successfully
- [ ] Backend server restarted
- [ ] Frontend app rebuilt and running
- [ ] Admin can login
- [ ] "Users" tab visible to admin
- [ ] User creation works
- [ ] Regular users can access sheets
- [ ] Regular users cannot see Users tab
- [ ] Registration link removed from login
- [ ] Sheet edits are being tracked
- [ ] User deactivation works
- [ ] Documentation updated (if needed)

## Security Notes

1. **Change Default Admin Password**: 
   - Login as admin
   - Go to Users tab
   - Edit admin user
   - Set a strong password

2. **Review Existing Users**:
   - Check all users in the system
   - Deactivate any that shouldn't have access
   - Assign appropriate roles

3. **Regular Backups**:
   - Sheet edit history can grow large
   - Set up regular database backups
   - Consider archiving old edit history

## Performance Considerations

- Edit history table can grow quickly with heavy usage
- Consider adding retention policy (e.g., keep 90 days)
- Monitor database size
- Index performance may degrade with millions of edits

## Next Steps

1. **Train Administrators**: Show them how to create/manage users
2. **Communicate Changes**: Inform users about new login process
3. **Monitor Logs**: Watch for any unexpected errors
4. **Plan Maintenance**: Schedule regular cleanup of edit history
5. **User Onboarding**: Create process for new user requests

## Support Contacts

- Database Issues: Check PostgreSQL logs
- Backend Issues: Check `backend/logs/` directory
- Frontend Issues: Check Flutter console output
- General Questions: See `docs/USER_MANAGEMENT_MODULE.md`

## Estimated Downtime

- **Database Migration**: 1-2 minutes
- **Backend Restart**: 10-30 seconds
- **Frontend Rebuild**: 1-2 minutes
- **Total**: 3-5 minutes

---

**Deployment Date**: _____________

**Deployed By**: _____________

**Verified By**: _____________

**Issues Encountered**: _____________

**Resolution**: _____________
