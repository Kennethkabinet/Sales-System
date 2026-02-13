/// Formula model for custom calculations
class Formula {
  final int id;
  final String? uuid;
  final String name;
  final String? description;
  final String expression;
  final List<String> inputColumns;
  final String outputColumn;
  final bool isShared;
  final String? createdBy;
  final int version;
  final DateTime? createdAt;

  Formula({
    required this.id,
    this.uuid,
    required this.name,
    this.description,
    required this.expression,
    this.inputColumns = const [],
    required this.outputColumn,
    this.isShared = false,
    this.createdBy,
    this.version = 1,
    this.createdAt,
  });

  factory Formula.fromJson(Map<String, dynamic> json) {
    return Formula(
      id: json['id'],
      uuid: json['uuid'],
      name: json['name'] ?? '',
      description: json['description'],
      expression: json['expression'] ?? '',
      inputColumns: json['input_columns'] != null
          ? List<String>.from(json['input_columns'])
          : [],
      outputColumn: json['output_column'] ?? 'result',
      isShared: json['is_shared'] ?? false,
      createdBy: json['created_by'],
      version: json['version'] ?? 1,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'expression': expression,
      'input_columns': inputColumns,
      'output_column': outputColumn,
      'is_shared': isShared,
    };
  }
}

/// Formula preview result
class FormulaPreview {
  final dynamic result;
  final bool valid;
  final String? error;

  FormulaPreview({
    this.result,
    required this.valid,
    this.error,
  });

  factory FormulaPreview.fromJson(Map<String, dynamic> json) {
    return FormulaPreview(
      result: json['result'],
      valid: json['valid'] ?? false,
      error: json['error'],
    );
  }
}

/// Formula application result
class FormulaApplyResult {
  final bool success;
  final int rowsAffected;
  final Map<String, dynamic>? sampleResult;
  final String? error;

  FormulaApplyResult({
    required this.success,
    this.rowsAffected = 0,
    this.sampleResult,
    this.error,
  });

  factory FormulaApplyResult.fromJson(Map<String, dynamic> json) {
    return FormulaApplyResult(
      success: json['success'] ?? false,
      rowsAffected: json['rows_affected'] ?? 0,
      sampleResult: json['sample_result'],
      error: json['error']?['message'],
    );
  }
}
