/// Inventory Module Models

// ─── ProductMaster ────────────────────────────────────────────────────────────
class ProductMaster {
  final int id;
  final String productName;
  final String? qcCode;
  final int maintainingQty;
  final int criticalQty;
  final bool isActive;
  final int? createdBy;
  final String? createdByName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ProductMaster({
    required this.id,
    required this.productName,
    this.qcCode,
    required this.maintainingQty,
    required this.criticalQty,
    this.isActive = true,
    this.createdBy,
    this.createdByName,
    this.createdAt,
    this.updatedAt,
  });

  factory ProductMaster.fromJson(Map<String, dynamic> json) {
    return ProductMaster(
      id: json['id'] ?? 0,
      productName: json['product_name'] ?? '',
      qcCode: json['qc_code'],
      maintainingQty: _parseInt(json['maintaining_qty']),
      criticalQty: _parseInt(json['critical_qty']),
      isActive: json['is_active'] ?? true,
      createdBy: json['created_by'],
      createdByName: json['created_by_name'],
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'product_name': productName,
        'qc_code': qcCode,
        'maintaining_qty': maintainingQty,
        'critical_qty': criticalQty,
        'is_active': isActive,
      };

  ProductMaster copyWith({
    String? productName,
    String? qcCode,
    int? maintainingQty,
    int? criticalQty,
    bool? isActive,
  }) =>
      ProductMaster(
        id: id,
        productName: productName ?? this.productName,
        qcCode: qcCode ?? this.qcCode,
        maintainingQty: maintainingQty ?? this.maintainingQty,
        criticalQty: criticalQty ?? this.criticalQty,
        isActive: isActive ?? this.isActive,
        createdBy: createdBy,
        createdByName: createdByName,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

// ─── StockSnapshot ────────────────────────────────────────────────────────────
/// Current stock level per product, computed by the DB view
class StockSnapshot {
  final int id;
  final String productName;
  final String? qcCode;
  final int maintainingQty;
  final int criticalQty;
  final bool isActive;
  final int totalIn;
  final int totalOut;
  final int currentStock;

  /// 'ok', 'warning' (≤ maintaining), 'critical' (≤ critical)
  final String stockStatus;

  StockSnapshot({
    required this.id,
    required this.productName,
    this.qcCode,
    required this.maintainingQty,
    required this.criticalQty,
    this.isActive = true,
    required this.totalIn,
    required this.totalOut,
    required this.currentStock,
    required this.stockStatus,
  });

  factory StockSnapshot.fromJson(Map<String, dynamic> json) {
    return StockSnapshot(
      id: json['id'] ?? 0,
      productName: json['product_name'] ?? '',
      qcCode: json['qc_code'],
      maintainingQty: _parseInt(json['maintaining_qty']),
      criticalQty: _parseInt(json['critical_qty']),
      isActive: json['is_active'] ?? true,
      totalIn: _parseInt(json['total_in']),
      totalOut: _parseInt(json['total_out']),
      currentStock: _parseInt(json['current_stock']),
      stockStatus: json['stock_status'] ?? 'ok',
    );
  }
}

// ─── InventoryTransaction ─────────────────────────────────────────────────────
class InventoryTransaction {
  final int id;
  final int productId;
  final String productName;
  final String? qcCode;
  final int maintainingQty;
  final int criticalQty;
  final DateTime transactionDate;
  final int qtyIn;
  final int qtyOut;
  final String? referenceNo;
  final String? remarks;
  final int? createdBy;
  final String? createdByName;
  final int? updatedBy;
  final String? updatedByName;
  final int? runningTotal; // stock level after this entry (within that date)
  final DateTime? createdAt;
  final DateTime? updatedAt;

  InventoryTransaction({
    required this.id,
    required this.productId,
    required this.productName,
    this.qcCode,
    required this.maintainingQty,
    required this.criticalQty,
    required this.transactionDate,
    required this.qtyIn,
    required this.qtyOut,
    this.referenceNo,
    this.remarks,
    this.createdBy,
    this.createdByName,
    this.updatedBy,
    this.updatedByName,
    this.runningTotal,
    this.createdAt,
    this.updatedAt,
  });

  factory InventoryTransaction.fromJson(Map<String, dynamic> json) {
    return InventoryTransaction(
      id: json['id'] ?? 0,
      productId: json['product_id'] ?? 0,
      productName: json['product_name'] ?? '',
      qcCode: json['qc_code'],
      maintainingQty: _parseInt(json['maintaining_qty']),
      criticalQty: _parseInt(json['critical_qty']),
      transactionDate: _parseDate(json['transaction_date']) ?? DateTime.now(),
      qtyIn: _parseInt(json['qty_in']),
      qtyOut: _parseInt(json['qty_out']),
      referenceNo: json['reference_no'],
      remarks: json['remarks'],
      createdBy: json['created_by'],
      createdByName: json['created_by_name'],
      updatedBy: json['updated_by'],
      updatedByName: json['updated_by_name'],
      runningTotal: json['running_total'] != null
          ? _parseInt(json['running_total'])
          : null,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'qty_in': qtyIn,
        'qty_out': qtyOut,
        'reference_no': referenceNo,
        'remarks': remarks,
        'transaction_date': transactionDate.toIso8601String().split('T').first,
      };

  InventoryTransaction copyWith({
    int? qtyIn,
    int? qtyOut,
    String? referenceNo,
    String? remarks,
  }) =>
      InventoryTransaction(
        id: id,
        productId: productId,
        productName: productName,
        qcCode: qcCode,
        maintainingQty: maintainingQty,
        criticalQty: criticalQty,
        transactionDate: transactionDate,
        qtyIn: qtyIn ?? this.qtyIn,
        qtyOut: qtyOut ?? this.qtyOut,
        referenceNo: referenceNo ?? this.referenceNo,
        remarks: remarks ?? this.remarks,
        createdBy: createdBy,
        createdByName: createdByName,
        updatedBy: updatedBy,
        updatedByName: updatedByName,
        runningTotal: runningTotal,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  /// Status based on running total vs thresholds
  String get stockStatus {
    if (runningTotal == null) return 'ok';
    if (runningTotal! <= criticalQty) return 'critical';
    if (runningTotal! <= maintainingQty) return 'warning';
    return 'ok';
  }
}

// ─── Internal helpers ─────────────────────────────────────────────────────────
int _parseInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  try {
    return DateTime.parse(value.toString());
  } catch (_) {
    return null;
  }
}
