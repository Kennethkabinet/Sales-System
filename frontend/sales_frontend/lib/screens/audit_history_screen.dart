import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/data_provider.dart';
import '../models/audit_log.dart';

class AuditHistoryScreen extends StatefulWidget {
  const AuditHistoryScreen({super.key});

  @override
  State<AuditHistoryScreen> createState() => _AuditHistoryScreenState();
}

class _AuditHistoryScreenState extends State<AuditHistoryScreen> {
  String? _actionFilter;
  String? _entityFilter;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DataProvider>().loadAuditLogs();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Audit History',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () => context.read<DataProvider>().loadAuditLogs(
                        action: _actionFilter,
                        entity: _entityFilter,
                        startDate: _startDate,
                        endDate: _endDate,
                      ),
                      tooltip: 'Refresh',
                    ),
                    IconButton(
                      icon: const Icon(Icons.download),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Export feature coming soon')),
                        );
                      },
                      tooltip: 'Export',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Filters
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _actionFilter,
                        decoration: const InputDecoration(
                          labelText: 'Action',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('All Actions')),
                          DropdownMenuItem(value: 'CREATE', child: Text('Create')),
                          DropdownMenuItem(value: 'UPDATE', child: Text('Update')),
                          DropdownMenuItem(value: 'DELETE', child: Text('Delete')),
                          DropdownMenuItem(value: 'LOGIN', child: Text('Login')),
                          DropdownMenuItem(value: 'EXPORT', child: Text('Export')),
                        ],
                        onChanged: (value) {
                          setState(() => _actionFilter = value);
                          _applyFilters();
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _entityFilter,
                        decoration: const InputDecoration(
                          labelText: 'Entity',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('All Entities')),
                          DropdownMenuItem(value: 'file', child: Text('Files')),
                          DropdownMenuItem(value: 'row', child: Text('Rows')),
                          DropdownMenuItem(value: 'formula', child: Text('Formulas')),
                          DropdownMenuItem(value: 'user', child: Text('Users')),
                        ],
                        onChanged: (value) {
                          setState(() => _entityFilter = value);
                          _applyFilters();
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: InkWell(
                        onTap: () => _selectDateRange(),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Date Range',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _startDate != null && _endDate != null
                                    ? '${_formatDateShort(_startDate!)} - ${_formatDateShort(_endDate!)}'
                                    : 'All Time',
                              ),
                              const Icon(Icons.calendar_today, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _actionFilter = null;
                          _entityFilter = null;
                          _startDate = null;
                          _endDate = null;
                        });
                        _applyFilters();
                      },
                      icon: const Icon(Icons.clear),
                      label: const Text('Clear'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Audit logs list
            Expanded(
              child: Consumer<DataProvider>(
                builder: (context, data, _) {
                  if (data.isLoading && data.auditLogs.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (data.auditLogs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No audit logs found',
                            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: data.auditLogs.length,
                    itemBuilder: (context, index) {
                      final log = data.auditLogs[index];
                      return _AuditLogCard(log: log);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _applyFilters() {
    context.read<DataProvider>().loadAuditLogs(
      action: _actionFilter,
      entity: _entityFilter,
      startDate: _startDate,
      endDate: _endDate,
    );
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _applyFilters();
    }
  }

  String _formatDateShort(DateTime date) {
    return '${date.month}/${date.day}';
  }
}

class _AuditLogCard extends StatelessWidget {
  final AuditLog log;

  const _AuditLogCard({required this.log});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _getActionColor(log.action).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getActionIcon(log.action),
            color: _getActionColor(log.action),
            size: 20,
          ),
        ),
        title: Row(
          children: [
            _ActionBadge(action: log.action),
            const SizedBox(width: 8),
            Text(
              log.entityType,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            if (log.entityName != null || log.entityId != null) ...[
              const SizedBox(width: 4),
              Text(
                log.entityName != null
                    ? '- ${log.entityName}'
                    : '#${log.entityId!.length > 8 ? '${log.entityId!.substring(0, 8)}...' : log.entityId!}',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ],
          ],
        ),
        subtitle: Row(
          children: [
            Icon(Icons.person, size: 14, color: Colors.grey[500]),
            const SizedBox(width: 4),
            Text(log.userName ?? 'Unknown'),
            const SizedBox(width: 16),
            Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
            const SizedBox(width: 4),
            Text(_formatDateTime(log.timestamp)),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (log.description != null && log.description!.isNotEmpty) ...[
                  Text(
                    'Description',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(log.description!),
                  const SizedBox(height: 16),
                ],
                if (log.oldValue != null || log.newValue != null) ...[
                  Text(
                    'Changes',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (log.oldValue != null)
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red[200]!),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Old Value',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red[700],
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatValue(log.oldValue),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (log.oldValue != null && log.newValue != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.arrow_forward, color: Colors.grey[400]),
                        ),
                      if (log.newValue != null)
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green[200]!),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'New Value',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green[700],
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatValue(log.newValue),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.computer, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      'IP: ${log.ipAddress ?? 'Unknown'}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getActionIcon(String action) {
    switch (action.toUpperCase()) {
      case 'CREATE':
        return Icons.add_circle;
      case 'UPDATE':
        return Icons.edit;
      case 'DELETE':
        return Icons.delete;
      case 'LOGIN':
        return Icons.login;
      case 'LOGOUT':
        return Icons.logout;
      case 'EXPORT':
        return Icons.download;
      default:
        return Icons.info;
    }
  }

  Color _getActionColor(String action) {
    switch (action.toUpperCase()) {
      case 'CREATE':
        return Colors.green;
      case 'UPDATE':
        return Colors.blue;
      case 'DELETE':
        return Colors.red;
      case 'LOGIN':
      case 'LOGOUT':
        return Colors.orange;
      case 'EXPORT':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    
    return '${dt.month}/${dt.day}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatValue(dynamic value) {
    if (value == null) return 'null';
    if (value is Map) {
      return value.entries
          .map((e) => '${e.key}: ${e.value}')
          .join('\n');
    }
    return value.toString();
  }
}

class _ActionBadge extends StatelessWidget {
  final String action;

  const _ActionBadge({required this.action});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (action.toUpperCase()) {
      case 'CREATE':
        color = Colors.green;
        break;
      case 'UPDATE':
        color = Colors.blue;
        break;
      case 'DELETE':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        action.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
