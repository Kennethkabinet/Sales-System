# User Management Module - Implementation Guide

## Overview
This document describes the implementation of the User Management Module with integrated Sheet tracking system, replacing the self-registration functionality with admin-controlled user creation.

## Major Changes

### 1. Authentication System Updates

#### Backend Changes
- **Removed**: Self-registration endpoint (`POST /auth/register`)
- **Login remains**: `POST /auth/login` unchanged

#### Frontend Changes
- **Removed**: Registration screen (`register_screen.dart`)
- **Updated**: Login screen - removed "Register" link, added admin contact message
- **Updated**: API Service - removed `register()` method

### 2. User Management Module (Admin Only)

#### New Backend Endpoints

**User Management** (All require Admin role)
- `POST /users` - Create new user
  - Required fields: username, email, password, full_name, role
  - Allowed roles: 'user', 'editor'
  - Optional: department_id
  
- `GET /users` - Get all users with details
  - Returns: user list with role, department, status, created_by info
  
- `PUT /users/:id` - Update user information
  - Updateable fields: username, email, password, full_name, role, department_id
  - Cannot change own role if admin
  
- `DELETE /users/:id` - Deactivate user
  - Sets is_active = false
  - Records deactivated_at timestamp and deactivated_by user
  - Cannot deactivate self
  
- `PUT /users/:id/reactivate` - Reactivate deactivated user
  - Sets is_active = true
  - Clears deactivation fields

#### Database Changes

**Users Table** - New columns:
```sql
deactivated_at TIMESTAMP WITH TIME ZONE
deactivated_by INTEGER REFERENCES users(id)
created_by INTEGER REFERENCES users(id)
```

**Roles Table** - New role:
```sql
'editor' - Editor with full sheet edit access
```

#### Frontend - User Management Screen

**Location**: `frontend/sales_frontend/lib/screens/user_management_screen.dart`

**Features**:
- User list with status (Active/Inactive)
- Create new user dialog
  - Full name, username, email, password
  - Role selection (User or Editor only)
  - Department assignment (optional)
- Edit user dialog
  - Update all user fields
  - Change password (optional)
- Deactivate/Reactivate users
- Visual role badges (color-coded)
- User statistics dashboard

**Access**: Only visible to Admin users in the navigation rail

### 3. Sheet Module Access Control

#### Access Restrictions
- **Old behavior**: admin, manager, editor could access sheets
- **New behavior**: Only user, editor, and admin can access sheets
- Middleware: `requireSheetAccess` checks user role

#### Sheet Edit Tracking

**Database**: New table `sheet_edit_history`
```sql
CREATE TABLE sheet_edit_history (
    id SERIAL PRIMARY KEY,
    sheet_id INTEGER,
    row_number INTEGER,
    column_name VARCHAR(100),
    old_value TEXT,
    new_value TEXT,
    edited_by INTEGER REFERENCES users(id),
    edited_at TIMESTAMP WITH TIME ZONE,
    action VARCHAR(50)  -- INSERT, UPDATE, DELETE, RENAME_COLUMN, RENAME_ROW
);
```

**Sheets Table** - New column:
```sql
last_edited_by INTEGER REFERENCES users(id)
```

#### Edit Tracking Features
- Tracks every cell change (old value → new value)
- Records column renames
- Stores editor user ID and timestamp
- New endpoint: `GET /sheets/:id/history` - Get edit history with pagination

#### Frontend API Updates
```dart
// New methods in ApiService
createUser() - Create user account
updateUser() - Update user information
deactivateUser() - Deactivate user
reactivateUser() - Reactivate user
getSheetHistory() - Get sheet edit history
```

### 4. Role Definitions

| Role | Description | Sheet Access | Can Create Sheets | Can Edit Sheets | Can Delete Sheets | User Management |
|------|-------------|--------------|-------------------|-----------------|-------------------|-----------------|
| admin | System Administrator | ✅ Full | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Full Control |
| editor | Sheet Editor | ✅ Full | ✅ Yes | ✅ Yes | ❌ No | ❌ No |
| user | Standard User | ✅ Full | ✅ Yes | ✅ Yes | ❌ No | ❌ No |
| viewer | Read-Only | ❌ No Access | ❌ No | ❌ No | ❌ No | ❌ No |

**Note**: Only 'user' and 'editor' roles can be assigned by admin during user creation.

## Migration Instructions

### Step 1: Database Migration
Run the migration script to update your database:
```bash
cd backend/database
psql -U your_user -d your_database -f migration_user_module.sql
```

Or through your database client, execute the SQL from `migration_user_module.sql`.

### Step 2: Update Backend
The backend changes are already in place:
- `backend/routes/auth.js` - Registration removed
- `backend/routes/users.js` - User management endpoints added
- `backend/routes/sheets.js` - Access control and tracking added
- `backend/database/schema.sql` - Updated for new installations

### Step 3: Update Frontend
The frontend changes are already in place:
- `frontend/sales_frontend/lib/services/api_service.dart` - API methods updated
- `frontend/sales_frontend/lib/screens/user_management_screen.dart` - New screen added
- `frontend/sales_frontend/lib/screens/dashboard_screen.dart` - Navigation updated
- `frontend/sales_frontend/lib/screens/login_screen.dart` - Registration link removed

### Step 4: Restart Services
```bash
# Backend
cd backend
npm restart

# Frontend
cd frontend/sales_frontend
flutter run
```

## Usage Guide

### For Administrators

#### Creating a New User
1. Navigate to "Users" tab in the left sidebar
2. Click "Create User" button
3. Fill in required fields:
   - Full Name
   - Username (min 3 characters)
   - Email
   - Password (min 6 characters)
   - Role (User or Editor)
   - Department (optional)
4. Click "Create"

#### Editing a User
1. Find the user in the list
2. Click the menu icon (⋮) next to their name
3. Select "Edit"
4. Update any fields (leave password blank to keep current)
5. Click "Update"

#### Deactivating a User
1. Find the user in the list
2. Click the menu icon (⋮) next to their name
3. Select "Deactivate"
4. Confirm the action

**Note**: Deactivated users cannot log in but their data is preserved. They can be reactivated later.

#### Reactivating a User
1. Find the deactivated user in the list (shown with gray "INACTIVE" badge)
2. Click the menu icon (⋮) next to their name
3. Select "Reactivate"

### For Users

#### Accessing Sheets (User or Editor only)
- Users and Editors can access the Sheet module
- All sheet edits are automatically tracked
- Edit history shows who made changes and when

#### Viewing Edit History
- Future feature: Sheet edit history viewer
- Backend endpoint available: `GET /sheets/:id/history`

## Security Features

1. **No Self-Registration**: All accounts must be created by admin
2. **Role-Based Access Control**: Enforced at API level
3. **Audit Logging**: All user management actions are logged
4. **Edit Tracking**: Complete history of sheet modifications
5. **Account Deactivation**: Soft delete preserves data integrity
6. **Permission Checks**: Multiple layers of authorization

## API Endpoint Summary

### Authentication
- `POST /auth/login` - User login
- `GET /auth/me` - Get current user
- `POST /auth/logout` - Logout

### User Management (Admin Only)
- `GET /users` - List all users
- `POST /users` - Create user
- `GET /users/:id` - Get user details
- `PUT /users/:id` - Update user
- `DELETE /users/:id` - Deactivate user
- `PUT /users/:id/reactivate` - Reactivate user
- `GET /users/meta/departments` - Get departments
- `GET /users/meta/roles` - Get roles

### Sheets (User/Editor/Admin)
- `GET /sheets` - List sheets
- `GET /sheets/:id` - Get sheet data
- `POST /sheets` - Create sheet
- `PUT /sheets/:id` - Update sheet (with edit tracking)
- `DELETE /sheets/:id` - Delete sheet (Admin only)
- `GET /sheets/:id/history` - Get edit history
- `GET /sheets/:id/export` - Export sheet
- `POST /sheets/:id/import` - Import sheet

## Database Schema Changes Summary

### New Tables
- `sheet_edit_history` - Tracks all sheet modifications

### Modified Tables
- `users`: Added deactivated_at, deactivated_by, created_by
- `sheets`: Added last_edited_by
- `roles`: Added 'editor' role

### New Indexes
- `idx_sheet_edit_history_sheet` - Fast history lookups
- `idx_sheet_edit_history_user` - User activity tracking
- `idx_sheet_edit_history_date` - Time-based queries

## Troubleshooting

### "Access Denied" when trying to register
**Solution**: Registration is disabled. Contact your administrator to create your account.

### Cannot see "Users" tab in navigation
**Solution**: User Management is only visible to Admin users. Contact your administrator if you need admin access.

### Sheet edit history not showing
**Solution**: Make sure you've run the migration script. Edit tracking only works for changes made after the migration.

### User cannot be deactivated
**Possible causes**:
- Trying to deactivate your own account (not allowed)
- Not an admin user
- Network error

## Development Notes

### Frontend Components
- `UserManagementScreen` - Main user management interface
- Uses Flutter Material Design
- Integrated with Provider state management
- Form validation on all inputs

### Backend Architecture
- RESTful API design
- JWT authentication
- PostgreSQL database
- Audit logging for all actions
- Transaction support for data integrity

### Testing Recommendations
1. Test user creation with all role types
2. Verify deactivated users cannot log in
3. Test sheet edit tracking with multiple concurrent users
4. Verify permission boundaries between roles
5. Test reactivation flow

## Future Enhancements

Potential features for future development:
1. Password reset functionality
2. Email notifications for account creation
3. Bulk user import/export
4. Advanced user search and filtering
5. Sheet edit history viewer in frontend
6. User activity dashboard
7. Two-factor authentication
8. Session management
9. Password complexity requirements
10. Account lockout after failed attempts

## Support

For issues or questions:
1. Check this documentation
2. Review backend logs: `backend/logs/`
3. Check database connectivity
4. Verify JWT token validity
5. Ensure proper role assignments

## Version History

- **v2.0.0** (Current) - User Management Module & Edit Tracking
  - Removed self-registration
  - Added admin-controlled user management
  - Implemented sheet edit tracking
  - Updated access control for sheets
  - Added user deactivation/reactivation

- **v1.0.0** - Initial Release
  - Self-registration enabled
  - Basic role system
  - Sheet module without tracking
