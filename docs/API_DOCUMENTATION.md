# API & WebSocket Event Documentation

## Base URL
```
http://localhost:3001/api
```

## Authentication

### POST /auth/register
Register a new user.

**Request Body:**
```json
{
  "username": "john_doe",
  "email": "john@company.com",
  "password": "securePassword123",
  "full_name": "John Doe",
  "department_id": 1
}
```

**Response:**
```json
{
  "success": true,
  "message": "User registered successfully",
  "user": {
    "id": 1,
    "username": "john_doe",
    "email": "john@company.com",
    "role": "user"
  }
}
```

---

### POST /auth/login
Authenticate user and receive JWT token.

**Request Body:**
```json
{
  "username": "john_doe",
  "password": "securePassword123"
}
```

**Response:**
```json
{
  "success": true,
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": 1,
    "username": "john_doe",
    "role": "user",
    "department_id": 1,
    "department_name": "Sales"
  }
}
```

---

### GET /auth/me
Get current authenticated user info.

**Headers:**
```
Authorization: Bearer <token>
```

**Response:**
```json
{
  "id": 1,
  "username": "john_doe",
  "email": "john@company.com",
  "full_name": "John Doe",
  "role": "user",
  "department_id": 1,
  "department_name": "Sales"
}
```

---

## Users

### GET /users
Get all users (Admin only).

**Headers:**
```
Authorization: Bearer <token>
```

**Response:**
```json
{
  "users": [
    {
      "id": 1,
      "username": "john_doe",
      "email": "john@company.com",
      "full_name": "John Doe",
      "role": "user",
      "department_name": "Sales",
      "created_at": "2026-02-12T10:00:00Z"
    }
  ]
}
```

### PUT /users/:id/role
Update user role (Admin only).

**Request Body:**
```json
{
  "role": "admin"
}
```

---

## Files

### GET /files
Get files accessible to current user.

**Query Parameters:**
- `department_id` (optional): Filter by department
- `page` (optional): Page number (default: 1)
- `limit` (optional): Items per page (default: 20)

**Response:**
```json
{
  "files": [
    {
      "id": 1,
      "name": "Sales_Q1.xlsx",
      "original_filename": "Sales_Q1_2026.xlsx",
      "department_id": 1,
      "department_name": "Sales",
      "created_by": "john_doe",
      "version": 3,
      "created_at": "2026-02-12T10:00:00Z",
      "updated_at": "2026-02-12T15:30:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "limit": 20,
    "total": 45,
    "pages": 3
  }
}
```

### POST /files/upload
Upload a new Excel file.

**Headers:**
```
Content-Type: multipart/form-data
Authorization: Bearer <token>
```

**Form Data:**
- `file`: Excel file (.xlsx, .xls)
- `name`: Display name
- `department_id`: Target department
- `column_mapping`: JSON string of column mappings

**Column Mapping Example:**
```json
{
  "A": "product_name",
  "B": "quantity",
  "C": "unit_price",
  "D": "supplier",
  "E": "total"
}
```

**Response:**
```json
{
  "success": true,
  "file": {
    "id": 1,
    "name": "Sales_Q1.xlsx",
    "rows_imported": 150,
    "columns": ["product_name", "quantity", "unit_price", "supplier", "total"]
  }
}
```

### GET /files/:id/data
Get file data for table view.

**Query Parameters:**
- `page` (optional): Page number
- `limit` (optional): Rows per page

**Response:**
```json
{
  "file": {
    "id": 1,
    "name": "Sales_Q1.xlsx",
    "columns": ["product_name", "quantity", "unit_price", "supplier", "total"]
  },
  "data": [
    {
      "row_id": 1,
      "row_number": 1,
      "values": {
        "product_name": "Widget A",
        "quantity": 100,
        "unit_price": 25.00,
        "supplier": "Acme Corp",
        "total": 2500.00
      },
      "locked_by": null
    },
    {
      "row_id": 2,
      "row_number": 2,
      "values": {
        "product_name": "Widget B",
        "quantity": 50,
        "unit_price": 45.00,
        "supplier": "Beta Co",
        "total": 2250.00
      },
      "locked_by": "john_doe"
    }
  ],
  "pagination": {
    "page": 1,
    "limit": 50,
    "total": 150
  }
}
```

### PUT /files/:id/data/:rowId
Update a specific row.

**Request Body:**
```json
{
  "values": {
    "quantity": 150,
    "total": 3750.00
  }
}
```

**Response:**
```json
{
  "success": true,
  "row": {
    "row_id": 1,
    "values": {
      "product_name": "Widget A",
      "quantity": 150,
      "unit_price": 25.00,
      "supplier": "Acme Corp",
      "total": 3750.00
    }
  },
  "audit": {
    "id": 123,
    "changes": [
      {
        "field": "quantity",
        "old_value": "100",
        "new_value": "150"
      },
      {
        "field": "total",
        "old_value": "2500.00",
        "new_value": "3750.00"
      }
    ]
  }
}
```

### GET /files/:id/versions
Get file version history.

**Response:**
```json
{
  "versions": [
    {
      "version": 3,
      "created_at": "2026-02-12T15:30:00Z",
      "created_by": "mary_smith",
      "changes_count": 12
    },
    {
      "version": 2,
      "created_at": "2026-02-11T10:00:00Z",
      "created_by": "john_doe",
      "changes_count": 5
    }
  ]
}
```

### POST /files/:id/export
Export file as Excel.

**Response:**
Binary Excel file download.

---

## Formulas

### GET /formulas
Get all formulas accessible to user.

**Response:**
```json
{
  "formulas": [
    {
      "id": 1,
      "name": "Profit Margin",
      "description": "Calculate profit margin percentage",
      "expression": "((selling_price - cost_price) / selling_price) * 100",
      "input_columns": ["selling_price", "cost_price"],
      "output_column": "profit_margin",
      "created_by": "admin",
      "is_shared": true,
      "created_at": "2026-02-10T08:00:00Z"
    }
  ]
}
```

### POST /formulas
Create a new formula.

**Request Body:**
```json
{
  "name": "Tax Calculation",
  "description": "Calculate 10% tax on total",
  "expression": "total * 0.10",
  "input_columns": ["total"],
  "output_column": "tax_amount",
  "is_shared": true
}
```

### POST /formulas/:id/apply
Apply formula to a file.

**Request Body:**
```json
{
  "file_id": 1,
  "column_mapping": {
    "selling_price": "unit_price",
    "cost_price": "cost"
  }
}
```

**Response:**
```json
{
  "success": true,
  "rows_affected": 150,
  "sample_result": {
    "row_1": {
      "profit_margin": 30.5
    }
  }
}
```

### POST /formulas/preview
Preview formula result without saving.

**Request Body:**
```json
{
  "expression": "((selling_price - cost_price) / selling_price) * 100",
  "test_values": {
    "selling_price": 100,
    "cost_price": 70
  }
}
```

**Response:**
```json
{
  "result": 30,
  "valid": true
}
```

---

## Audit Logs

### GET /audit
Get audit logs.

**Query Parameters:**
- `file_id` (optional): Filter by file
- `user_id` (optional): Filter by user
- `action` (optional): Filter by action type (CREATE, UPDATE, DELETE)
- `start_date` (optional): Start date filter
- `end_date` (optional): End date filter
- `page` (optional): Page number
- `limit` (optional): Items per page

**Response:**
```json
{
  "logs": [
    {
      "id": 1,
      "user_id": 1,
      "username": "john_doe",
      "action": "UPDATE",
      "entity_type": "file_data",
      "entity_id": 1,
      "file_name": "Sales_Q1.xlsx",
      "row_number": 5,
      "field": "quantity",
      "old_value": "100",
      "new_value": "150",
      "timestamp": "2026-02-12T10:30:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "limit": 50,
    "total": 1250
  }
}
```

### GET /audit/summary
Get audit summary statistics.

**Response:**
```json
{
  "summary": {
    "total_changes": 1250,
    "today": 45,
    "this_week": 320,
    "by_action": {
      "CREATE": 150,
      "UPDATE": 980,
      "DELETE": 120
    },
    "by_user": [
      { "username": "john_doe", "count": 450 },
      { "username": "mary_smith", "count": 380 }
    ],
    "recent_activity": [
      {
        "username": "john_doe",
        "action": "UPDATE",
        "file_name": "Sales_Q1.xlsx",
        "timestamp": "2026-02-12T10:30:00Z"
      }
    ]
  }
}
```

---

## Dashboard

### GET /dashboard/stats
Get dashboard statistics.

**Response:**
```json
{
  "stats": {
    "total_sales": 125430.50,
    "total_inventory": 2340,
    "active_users": 12,
    "files_count": 45,
    "formulas_count": 15
  },
  "sales_trend": [
    { "date": "2026-02-06", "amount": 15000 },
    { "date": "2026-02-07", "amount": 18500 },
    { "date": "2026-02-08", "amount": 22000 }
  ],
  "top_products": [
    { "name": "Widget A", "quantity": 500, "revenue": 12500 },
    { "name": "Gadget X", "quantity": 350, "revenue": 8750 }
  ],
  "department_breakdown": [
    { "department": "Sales", "percentage": 45 },
    { "department": "Operations", "percentage": 30 },
    { "department": "Finance", "percentage": 25 }
  ]
}
```

---

## WebSocket Events

### Connection
```javascript
// Client connects with auth token
const socket = io('http://localhost:3001', {
  auth: {
    token: 'Bearer <jwt_token>'
  }
});
```

### Events (Client → Server)

#### join_file
Join a file editing session.
```javascript
socket.emit('join_file', { file_id: 1 });
```

#### leave_file
Leave a file editing session.
```javascript
socket.emit('leave_file', { file_id: 1 });
```

#### lock_row
Request lock on a row for editing.
```javascript
socket.emit('lock_row', { file_id: 1, row_id: 5 });
```

#### unlock_row
Release lock on a row.
```javascript
socket.emit('unlock_row', { file_id: 1, row_id: 5 });
```

#### update_row
Update row data (broadcasts to other users).
```javascript
socket.emit('update_row', {
  file_id: 1,
  row_id: 5,
  values: { quantity: 150 }
});
```

#### cursor_position
Share cursor position for collaboration indicator.
```javascript
socket.emit('cursor_position', {
  file_id: 1,
  row_id: 5,
  column: 'quantity'
});
```

### Events (Server → Client)

#### user_joined
Notifies when a user joins the file.
```javascript
socket.on('user_joined', (data) => {
  // data: { user_id: 2, username: 'mary_smith', file_id: 1 }
});
```

#### user_left
Notifies when a user leaves the file.
```javascript
socket.on('user_left', (data) => {
  // data: { user_id: 2, username: 'mary_smith', file_id: 1 }
});
```

#### row_locked
Notifies when a row is locked.
```javascript
socket.on('row_locked', (data) => {
  // data: { file_id: 1, row_id: 5, locked_by: 'john_doe', user_id: 1 }
});
```

#### row_unlocked
Notifies when a row is unlocked.
```javascript
socket.on('row_unlocked', (data) => {
  // data: { file_id: 1, row_id: 5 }
});
```

#### row_updated
Notifies when row data changes.
```javascript
socket.on('row_updated', (data) => {
  // data: {
  //   file_id: 1,
  //   row_id: 5,
  //   values: { quantity: 150, total: 3750 },
  //   updated_by: 'john_doe'
  // }
});
```

#### active_users
List of users currently editing the file.
```javascript
socket.on('active_users', (data) => {
  // data: {
  //   file_id: 1,
  //   users: [
  //     { user_id: 1, username: 'john_doe', current_row: 5 },
  //     { user_id: 2, username: 'mary_smith', current_row: 12 }
  //   ]
  // }
});
```

#### cursor_moved
Another user's cursor position changed.
```javascript
socket.on('cursor_moved', (data) => {
  // data: {
  //   user_id: 2,
  //   username: 'mary_smith',
  //   row_id: 12,
  //   column: 'price'
  // }
});
```

#### error
Error notification.
```javascript
socket.on('error', (data) => {
  // data: { code: 'ROW_LOCKED', message: 'Row is being edited by john_doe' }
});
```

---

## Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| AUTH_REQUIRED | 401 | Authentication token required |
| AUTH_INVALID | 401 | Invalid or expired token |
| FORBIDDEN | 403 | Insufficient permissions |
| NOT_FOUND | 404 | Resource not found |
| VALIDATION_ERROR | 400 | Invalid request data |
| ROW_LOCKED | 409 | Row is being edited by another user |
| FORMULA_ERROR | 400 | Invalid formula expression |
| FILE_ERROR | 400 | Invalid file format |
| SERVER_ERROR | 500 | Internal server error |

---

## Response Format

### Success Response
```json
{
  "success": true,
  "data": { ... },
  "message": "Operation completed successfully"
}
```

### Error Response
```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Invalid request data",
    "details": {
      "field": "email",
      "issue": "Invalid email format"
    }
  }
}
```
