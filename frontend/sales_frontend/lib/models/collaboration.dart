import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  CellPresence – a single user currently viewing/editing a sheet
// ─────────────────────────────────────────────────────────────────────────────

/// Palette of colors used to distinguish users in the presence panel.
const List<Color> kPresenceColors = [
  Color(0xFF1565C0), // blue
  Color(0xFF2E7D32), // green
  Color(0xFFE65100), // deep-orange
  Color(0xFF6A1B9A), // purple
  Color(0xFF00695C), // teal
  Color(0xFFC62828), // red
  Color(0xFF558B2F), // light-green
  Color(0xFF283593), // indigo
];

class CellPresence {
  final int userId;
  final String username;
  final String role;
  final String? departmentName;
  final String? currentCell; // e.g. "B4"

  const CellPresence({
    required this.userId,
    required this.username,
    required this.role,
    this.departmentName,
    this.currentCell,
  });

  factory CellPresence.fromJson(Map<String, dynamic> j) => CellPresence(
        userId: (j['user_id'] as num).toInt(),
        username: j['username'] as String? ?? '',
        role: j['role'] as String? ?? '',
        departmentName: j['department_name'] as String?,
        currentCell: j['current_cell'] as String?,
      );

  /// Deterministic color assignment based on userId.
  Color get color => kPresenceColors[userId % kPresenceColors.length];

  /// Single-letter avatar label.
  String get initials => username.isNotEmpty ? username[0].toUpperCase() : '?';

  CellPresence copyWith({String? currentCell}) => CellPresence(
        userId: userId,
        username: username,
        role: role,
        departmentName: departmentName,
        currentCell: currentCell ?? this.currentCell,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  EditRequest – a request to edit a historically-locked inventory cell
// ─────────────────────────────────────────────────────────────────────────────

enum EditRequestStatus { pending, approved, rejected }

class EditRequest {
  final int id;
  final int sheetId;
  final int rowNumber;
  final String columnName;
  final String? cellReference;
  final String? currentValue;
  final String? proposedValue;
  final int requestedBy;
  final String requesterUsername;
  final String? requesterRole;
  final String? requesterDept;
  final DateTime requestedAt;
  final EditRequestStatus status;
  final String? reviewerUsername;
  final DateTime? reviewedAt;
  final String? rejectReason;
  final DateTime? expiresAt;

  const EditRequest({
    required this.id,
    required this.sheetId,
    required this.rowNumber,
    required this.columnName,
    this.cellReference,
    this.currentValue,
    this.proposedValue,
    required this.requestedBy,
    this.requesterUsername = '',
    this.requesterRole,
    this.requesterDept,
    required this.requestedAt,
    this.status = EditRequestStatus.pending,
    this.reviewerUsername,
    this.reviewedAt,
    this.rejectReason,
    this.expiresAt,
  });

  bool get isPending => status == EditRequestStatus.pending;
  bool get isApproved => status == EditRequestStatus.approved;
  bool get isActive =>
      isApproved && (expiresAt == null || expiresAt!.isAfter(DateTime.now()));

  factory EditRequest.fromJson(Map<String, dynamic> j) {
    EditRequestStatus parseStatus(String? s) {
      switch (s) {
        case 'approved':
          return EditRequestStatus.approved;
        case 'rejected':
          return EditRequestStatus.rejected;
        default:
          return EditRequestStatus.pending;
      }
    }

    return EditRequest(
      id: j['id'] as int,
      sheetId: j['sheet_id'] as int,
      rowNumber: j['row_number'] as int,
      columnName: j['column_name'] as String? ?? '',
      cellReference: j['cell_reference'] as String?,
      currentValue: j['current_value'] as String?,
      proposedValue: j['proposed_value'] as String?,
      requestedBy: j['requested_by'] as int,
      requesterUsername: j['requester_username'] as String? ?? '',
      requesterRole: j['requester_role'] as String?,
      requesterDept: j['requester_dept'] as String?,
      requestedAt: DateTime.parse(j['requested_at'] as String),
      status: parseStatus(j['status'] as String?),
      reviewerUsername: j['reviewer_username'] as String?,
      reviewedAt: j['reviewed_at'] != null
          ? DateTime.parse(j['reviewed_at'] as String)
          : null,
      rejectReason: j['reject_reason'] as String?,
      expiresAt: j['expires_at'] != null
          ? DateTime.parse(j['expires_at'] as String)
          : null,
    );
  }
}
