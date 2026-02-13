# Role-Based Access Control Implementation

## Overview
The Sales & Inventory System implements strict role-based modules where users are automatically redirected to their specific interface based on their role. Editors and Viewers have NO dashboard access - they see only the Excel sheet and system settings.

## User Roles & Module Access

### 1. **Admin Module**
- **Interface**: Full Admin Dashboard with complete system access
- **Access Rights**:
  - Dashboard with overview statistics and analytics
  - Complete sheet management (create, edit, delete, view)
  - User management (create, edit, deactivate users)
  - File management
  - Formula management
  - Audit log access
  - System configuration
- **Login Redirect**: Multi-tab Admin Dashboard
- **Navigation**: Dashboard, Sheet, Files, Formulas, Audit Log, Users tabs
- **Features**:
  - Complete control over all system resources
  - Can assign roles and manage access rights
  - Full oversight of all activities

### 2. **Editor Module**
- **Interface**: Simplified sheet editor (NO dashboard)
- **Access Rights**:
  - Excel sheet editing ONLY
  - System settings view (username, email, department)
  - Create new sheets
  - Import/Export sheets
  - Add/remove rows and columns
  - Save changes to sheets
  - View sheet edit history
- **Login Redirect**: Direct to Sheet Editor (no dashboard)
- **Navigation**: NONE - Direct single-page interface
- **Features**:
  - Clean, focused editing interface
  - Top bar with user info, settings toggle, and logout
  - Real-time sync indicator showing "Live Sync"
  - "Edit Mode" badge indicating editing capability
  - Full spreadsheet toolbar (New, Import, Export, Add/Remove, Save)
  - Collapsible settings panel for account information
  - Changes tracked and synchronized in real-time
  - NO access to dashboard, files, formulas, or audit logs

### 3. **Viewer Module**
- **Interface**: Simplified sheet viewer (NO dashboard, NO editing)
- **Access Rights**:
  - Excel sheet viewing ONLY (read-only)
  - System settings view (username, email, department)
  - Export sheets
  - **CANNOT** create, edit, or delete sheets
  - **CANNOT** modify any data
- **Login Redirect**: Direct to Sheet Viewer (no dashboard)
- **Navigation**: NONE - Direct single-page interface
- **Features**:
  - Clean, read-only viewing interface
  - Top bar with user info, settings toggle, and logout
  - Real-time updates indicator showing "Live Updates"
  - "Read-Only" badge clearly indicating view-only mode
  - Export functionality available
  - Collapsible settings panel for account information
  - Receives real-time updates when editors make changes
  - NO editing controls visible (New, Import, Add/Remove, Save hidden)
  - NO access to dashboard, files, formulas, or audit logs

### 4. **User Role** (Legacy)
- **Interface**: Same as Editor Module
- **Access Rights**: Same as Editor
- **Note**: Backward compatibility - users get editor access

## Module Comparison

| Feature | Admin | Editor | Viewer |
|---------|-------|--------|--------|
| Dashboard Access | ✅ Yes | ❌ No | ❌ No |
| Sheet Viewing | ✅ Yes | ✅ Yes | ✅ Yes |
| Sheet Editing | ✅ Yes | ✅ Yes | ❌ No |
| Create Sheets | ✅ Yes | ✅ Yes | ❌ No |
| Import/Export | ✅ Yes | ✅ Yes | ✅ Export Only |
| File Management | ✅ Yes | ❌ No | ❌ No |
| Formula Management | ✅ Yes | ❌ No | ❌ No |
| User Management | ✅ Yes | ❌ No | ❌ No |
| Audit Logs | ✅ Yes | ❌ No | ❌ No |
| Settings View | ✅ Yes | ✅ Yes | ✅ Yes |
| Real-Time Sync | ✅ Yes | ✅ Yes | ✅ Yes |
| Navigation Tabs | ✅ Yes | ❌ No | ❌ No |

## Technical Implementation

### Frontend (Flutter/Dart)

#### 1. Role-Based Module Routing (`lib/main.dart`)
```dart
switch (userRole) {
  case 'admin':
    return const DashboardScreen();     // Full dashboard with all tabs
  case 'editor':
    return const EditorDashboard();     // Direct sheet editor, no dashboard
  case 'viewer':
    return const ViewerDashboard();     // Direct sheet viewer, no dashboard
  case 'user':
    return const EditorDashboard();     // User gets editor access
}
```

#### 2. Module Screens

**Admin Module** (`dashboard_screen.dart`)
- Multi-tab navigation rail (Dashboard, Sheet, Files, Formulas, Audit, Users)
- Full-featured interface with all capabilities
- Statistics and analytics dashboard
- Access to all system functions

**Editor Module** (`editor_dashboard.dart`)
- **Single-page interface** - NO navigation rail
- Top app bar with:
  - App icon and title "Sheet Editor"
  - Live sync indicator (green dot)
  - "Edit Mode" badge
  - User avatar and info
  - Settings button (toggles collapsible panel)
  - Logout button with confirmation
- Collapsible settings panel showing:
  - Username, Email, Full Name, Department
- Direct sheet access below header
- Full editing toolbar visible

**Viewer Module** (`viewer_dashboard.dart`)
- **Single-page interface** - NO navigation rail
- Top app bar with:
  - App icon and title "Sheet Viewer"
  - Live updates indicator (green dot)
  - "Read-Only" badge
  - User avatar and info
  - Settings button (toggles collapsible panel)
  - Logout button with confirmation
- Collapsible settings panel showing:
  - Username, Email, Full Name, Department
- Direct read-only sheet access below header
- Editing toolbar hidden

#### 3. Sheet Screen Configuration (`sheet_screen.dart`)
- `readOnly` parameter controls editing capability
- Conditional toolbar rendering based on role
- Disabled cell editing in read-only mode
- Hidden modification buttons for viewers
- Export always available

### Backend (Node.js/Express)

#### Access Control Middleware (`backend/routes/sheets.js`)

**`requireSheetAccess`** - View Access
```javascript
// Allows: admin, editor, user, viewer
// Used for: GET operations (viewing sheets)
```

**`requireSheetEdit`** - Edit Access
```javascript
// Allows: admin, editor, user
// Blocks: viewer
// Used for: POST, PUT operations (create/edit)
```

#### Protected Routes

**Read Operations** (All roles including viewer):
- `GET /sheets` - List all sheets
- `GET /sheets/:id` - Get single sheet
- `GET /sheets/:id/history` - View edit history
- `GET /sheets/:id/export` - Export sheet

**Write Operations** (Admin, Editor, User only):
- `POST /sheets` - Create sheet (requires `requireSheetEdit`)
- `PUT /sheets/:id` - Update sheet (requires `requireSheetEdit`)
- `POST /sheets/:id/import` - Import data (requires `requireSheetEdit`)

**Admin Only**:
- `DELETE /sheets/:id` - Delete sheet

## User Experience by Role

### Admin Experience
1. **Login** → Full Admin Dashboard
2. **Interface**: Multi-tab navigation with Dashboard as default
3. **Features**: Complete system access via tabs
4. **Navigation**: Switch between Dashboard, Sheet, Files, Formulas, Audit, Users
5. **Actions**: Full control - can do everything

### Editor Experience
1. **Login** → Direct to Sheet Editor (NO dashboard shown)
2. **Interface**: Clean single-page focused on sheet editing
3. **Top Bar**: 
   - Live sync indicator (green)
   - "Edit Mode" badge
   - User info
   - Settings toggle
   - Logout
4. **Settings Panel**: Collapsible panel showing account info
5. **Main Area**: Full sheet with complete editing toolbar
6. **Features**: 
   - Create, edit, save sheets
   - Import/export functionality
   - Real-time synchronization
   - NO access to other system features
7. **Actions**: Sheet editing only - focused workflow

### Viewer Experience
1. **Login** → Direct to Sheet Viewer (NO dashboard shown)
2. **Interface**: Clean single-page focused on viewing
3. **Top Bar**:
   - Live updates indicator (green)
   - "Read-Only" badge
   - User info
   - Settings toggle
   - Logout
4. **Settings Panel**: Collapsible panel showing account info
5. **Main Area**: Sheet with read-only view
6. **Features**:
   - View sheets with live updates
   - Export functionality
   - Real-time synchronization
   - NO editing controls visible
   - NO access to other system features
7. **Actions**: View and export only - monitoring workflow

## Real-Time Synchronization

### WebSocket Integration
- All users connected via Socket.IO
- Editor changes broadcast immediately
- Viewers receive instant updates
- No manual refresh required

### How It Works:
1. Editor makes a change (edit cell, add row, etc.)
2. Change validated and saved to database
3. WebSocket broadcasts update to all connected users
4. Viewers see change appear instantly in their interface
5. Full edit history tracked in database

## Security Architecture

### 1. Frontend Protection
- UI controls hidden/disabled based on role
- Read-only mode prevents accidental edits
- Visual indicators (badges) show user's access level

### 2. Backend Protection
- All routes protected with authentication
- Role-based middleware enforces access control
- Database operations validate user permissions
- Edit history tracks who made each change

### 3. Audit Trail
- All sheet modifications logged with:
  - User who made the change
  - Timestamp of change
  - Old and new values
  - Action type (INSERT, UPDATE, DELETE, RENAME)
- Audit logs accessible to admins

## User Experience

### Admin Experience
1. Login → Full Admin Dashboard
2. Access to all system features via multi-tab interface
3. Users tab for managing accounts
4. Complete oversight and control

### Editor Experience
1. Login → Clean Editor Module
2. Focused sheet editing interface
3. Real-time sync indicator shows live connection
4. Full editing capabilities with toolbar
5. Changes tracked and synced automatically

## Security Architecture

### 1. Frontend Protection
- **UI Simplification**: Editors and Viewers see ONLY what they need (no dashboard clutter)
- **Role-based interfaces**: Different screens for different roles
- **Read-only mode**: Prevents accidental edits for viewers
- **Visual indicators**: Clear badges show user's access level
- **No navigation for non-admins**: Editors/Viewers cannot navigate to unauthorized pages

### 2. Backend Protection
- All routes protected with authentication
- Role-based middleware enforces access control  
- Database operations validate user permissions
- Edit history tracks who made each change
- Viewers blocked from modification endpoints

### 3. Audit Trail
- All sheet modifications logged with:
  - User who made the change
  - Timestamp of change
  - Old and new values
  - Action type (INSERT, UPDATE, DELETE, RENAME)
- Audit logs accessible to admins only

## Testing Roles

### Creating Test Users (Admin Only)

**Via User Management Screen:**
1. Login as admin
2. Click **Users** tab in the navigation
3. Click **New User** button
4. Fill in user details:
   - Username, Email, Password
   - Full Name, Department
   - **Role**: Select Editor (for editing) or Viewer (for read-only)
5. Click **Create** button
6. Test by logging in with the new account

**Via Database:**
```sql
-- Create a viewer account (read-only)
INSERT INTO users (username, email, password, full_name, role_id)
VALUES ('viewer1', 'viewer@example.com', hashedPassword, 'Test Viewer', 
  (SELECT id FROM roles WHERE name = 'viewer'));

-- Create an editor account (can edit)
INSERT INTO users (username, email, password, full_name, role_id)
VALUES ('editor1', 'editor@example.com', hashedPassword, 'Test Editor',
  (SELECT id FROM roles WHERE name = 'editor'));
```

### Testing Each Module

**Test Admin Module:**
1. Login with admin account
2. Verify full dashboard with all tabs visible
3. Test navigation between Dashboard, Sheet, Files, Formulas, Audit, Users
4. Verify access to all features

**Test Editor Module:**
1. Login with editor account
2. Verify redirect to Sheet Editor (NO dashboard)
3. Verify clean interface with only top bar and sheet
4. Test editing capabilities (create, edit, save)
5. Verify settings panel opens/closes
6. Verify real-time sync indicator
7. Confirm NO access to other system features

**Test Viewer Module:**
1. Login with viewer account
2. Verify redirect to Sheet Viewer (NO dashboard)
3. Verify clean read-only interface
4. Test that editing is disabled (no double-click edit, no toolbar buttons)
5. Verify settings panel opens/closes
6. Verify live updates indicator
7. Have an editor make changes and confirm viewer sees them in real-time
8. Confirm NO access to other system features

## Architecture Benefits

### 1. Strict Separation of Concerns
- **Admin**: Full-featured dashboard with complete system access
- **Editor**: Simplified single-purpose interface - sheets only
- **Viewer**: Even simpler single-purpose interface - view only
- **No confusion**: Each role sees exactly what they need
- **No temptation**: Inaccessible features aren't even visible

### 2. Enhanced Security
- **Reduced attack surface**: Non-admins can't navigate to unauthorized pages
- **Clear boundaries**: No ambiguity about what each role can do
- **Multiple layers**: Frontend hiding + Backend enforcement
- **Audit trail**: Complete tracking for compliance

### 3. Superior User Experience
- **Focused workflows**: Each role optimized for their task
- **No clutter**: Only relevant features visible
- **Faster onboarding**: Simpler interfaces easier to learn
- **Clear visual cues**: Badges and indicators show capabilities
- **Efficient design**: Direct access without navigation overhead

### 4. Scalability & Maintainability
- **Easy to extend**: Add new roles with dedicated interfaces
- **Middleware-based**: Centralized access control
- **Clear code structure**: Each module independent
- **Consistent patterns**: Similar structure across modules

### 5. Real-Time Collaboration
- **Simultaneous editing**: Multiple editors can work together
- **Instant updates**: Viewers see changes immediately
- **No polling**: WebSocket-based efficient updates
- **Status indicators**: Live sync shows connection state

## Future Enhancements

Potential additions to enhance the RBAC system:

**Access Control:**
- Sheet-level permissions (assign specific users to specific sheets)
- Department-based access control (users see only their department's sheets)
- Time-based access (temporary access grants)
- Custom role creation interface for admins

**Collaboration:**
- In-sheet commenting for editors and viewers
- @mention notifications
- Change notifications (email/in-app)
- Collaborative cursors (see other users editing)

**Features:**
- Version control and rollback for sheets
- Sheet templates for editors
- Bulk export for viewers
- Scheduled reports for viewers

**Platform:**
- Mobile app with same role structure
- API access with role-based tokens
- Integration with external systems

## Summary

The system now provides a **streamlined role-based module system** with:

✅ **Automatic role-based redirection** to appropriate modules  
✅ **Admin Module**: Full-featured dashboard with complete system access  
✅ **Editor Module**: Simplified sheet editor with NO dashboard  
✅ **Viewer Module**: Simplified sheet viewer with NO dashboard, NO editing  
✅ **Comprehensive backend access control** enforcing permissions  
✅ **Real-time synchronization** across all roles via WebSockets  
✅ **Clear visual indicators** (badges, status indicators) showing access level  
✅ **Complete audit trail** tracking all changes  
✅ **Secure and scalable architecture** with multiple protection layers  
✅ **Focused user experiences** optimized for each role's workflow  

**Key Design Principle:**  
Users only see and access features appropriate to their role. Editors and Viewers get **direct, focused access** to sheets without dashboard complexity, while Admins retain full system control with complete feature access.

This implementation ensures maximum security, optimal user experience, and clear separation of responsibilities across the system.
