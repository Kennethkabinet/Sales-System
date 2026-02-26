import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/inventory.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../config/constants.dart';

// ─── Theme colours ─────────────────────────────────────────────────────────────
const Color _kNavy = AppColors.primaryBlue; // primary blue for headings
const Color _kAccent = AppColors.primaryRed; // primary red for accents
const Color _kContentBg = AppColors.lightRed; // light red background
const Color _kWarning = Color(0xFFFFF3CD);
const Color _kWarningText = Color(0xFF856404);
const Color _kCritical = Color(0xFFFFE0E0);
const Color _kCriticalText = Color(0xFFB71C1C);

// ─── InventoryScreen ──────────────────────────────────────────────────────────
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final isAdmin = auth.user?.role == 'admin';
    _tabController = TabController(length: isAdmin ? 3 : 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final isAdmin = auth.user?.role == 'admin';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──
        Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          color: _kContentBg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.inventory_2_outlined, color: _kNavy, size: 28),
                  const SizedBox(width: 10),
                  Text(
                    'Inventory Management',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: _kNavy,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Product master, daily IN/OUT transactions, and stock levels.',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              const SizedBox(height: 12),
              TabBar(
                controller: _tabController,
                labelColor: _kNavy,
                unselectedLabelColor: Colors.grey,
                indicatorColor: _kAccent,
                tabs: [
                  const Tab(
                      icon: Icon(Icons.bar_chart), text: 'Stock Overview'),
                  const Tab(icon: Icon(Icons.swap_horiz), text: 'Transactions'),
                  if (isAdmin)
                    const Tab(
                        icon: Icon(Icons.inventory), text: 'Product Master'),
                ],
              ),
            ],
          ),
        ),

        // ── Tab Content ──
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              const _StockOverviewTab(),
              const _TransactionsTab(),
              if (isAdmin) const _ProductMasterTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// TAB 1: STOCK OVERVIEW
// =============================================================================
class _StockOverviewTab extends StatefulWidget {
  const _StockOverviewTab();

  @override
  State<_StockOverviewTab> createState() => _StockOverviewTabState();
}

class _StockOverviewTabState extends State<_StockOverviewTab> {
  List<StockSnapshot> _snapshots = [];
  bool _loading = true;
  String? _error;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService.getInventoryStock();
      final list = (res['products'] as List)
          .map((p) => StockSnapshot.fromJson(p))
          .toList();
      setState(() {
        _snapshots = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search product…',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (v) => setState(() => _filter = v.toLowerCase()),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: _kAccent),
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: _load,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildLegend(),
          const SizedBox(height: 8),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ]),
              ),
            )
          else
            Expanded(child: _buildStockTable()),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Wrap(spacing: 16, children: [
      _LegendDot(color: Colors.green[100]!, label: 'OK'),
      _LegendDot(color: _kWarning, label: '≤ Maintaining'),
      _LegendDot(color: _kCritical, label: '≤ Critical'),
    ]);
  }

  Widget _buildStockTable() {
    final filtered = _snapshots
        .where((s) =>
            _filter.isEmpty ||
            s.productName.toLowerCase().contains(_filter) ||
            (s.qcCode?.toLowerCase().contains(_filter) ?? false))
        .toList();

    if (filtered.isEmpty) {
      return const Center(child: Text('No products found.'));
    }

    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header
              _TableHeader(const [
                _Col('Product Name', flex: 3),
                _Col('QC Code', flex: 2),
                _Col('Stock', flex: 1, align: TextAlign.center),
                _Col('Maintaining', flex: 1, align: TextAlign.center),
                _Col('Critical', flex: 1, align: TextAlign.center),
                _Col('IN', flex: 1, align: TextAlign.center),
                _Col('OUT', flex: 1, align: TextAlign.center),
                _Col('Status', flex: 1, align: TextAlign.center),
              ]),
              const Divider(height: 1),
              ...filtered.asMap().entries.map((e) {
                final snap = e.value;
                final isEven = e.key.isEven;
                return _StockRow(snap: snap, isEven: isEven);
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockRow extends StatelessWidget {
  final StockSnapshot snap;
  final bool isEven;
  const _StockRow({required this.snap, required this.isEven});

  @override
  Widget build(BuildContext context) {
    Color rowBg;
    Color? badgeBg;
    Color? badgeText;
    String statusLabel;

    switch (snap.stockStatus) {
      case 'critical':
        rowBg = _kCritical;
        badgeBg = _kCriticalText;
        badgeText = Colors.white;
        statusLabel = 'Critical';
        break;
      case 'warning':
        rowBg = _kWarning;
        badgeBg = _kWarningText;
        badgeText = Colors.white;
        statusLabel = 'Warning';
        break;
      default:
        rowBg = isEven ? Colors.white : const Color(0xFFF9FBF9);
        badgeBg = Colors.green[700];
        badgeText = Colors.white;
        statusLabel = 'OK';
    }

    return Container(
      color: rowBg,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Row(children: [
          Expanded(
              flex: 3,
              child: Text(snap.productName,
                  style: const TextStyle(fontWeight: FontWeight.w500))),
          Expanded(
              flex: 2,
              child: Text(snap.qcCode ?? '—',
                  style: TextStyle(color: Colors.grey[700]))),
          Expanded(flex: 1, child: _CenterNum(snap.currentStock)),
          Expanded(
              flex: 1, child: _CenterNum(snap.maintainingQty, dimmed: true)),
          Expanded(flex: 1, child: _CenterNum(snap.criticalQty, dimmed: true)),
          Expanded(
              flex: 1,
              child: _CenterNum(snap.totalIn, color: Colors.green[700])),
          Expanded(
              flex: 1, child: _CenterNum(snap.totalOut, color: _kCriticalText)),
          Expanded(
            flex: 1,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(statusLabel,
                    style: TextStyle(
                        color: badgeText,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// =============================================================================
// TAB 2: TRANSACTIONS (Accordion by date)
// =============================================================================
class _TransactionsTab extends StatefulWidget {
  const _TransactionsTab();

  @override
  State<_TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends State<_TransactionsTab> {
  List<InventoryTransaction> _transactions = [];
  List<ProductMaster> _products = [];
  List<DateTime> _dates = [];
  final Set<String> _expandedDates = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiService.getInventoryTransactions(),
        ApiService.getInventoryDates(),
        ApiService.getInventoryProducts(),
      ]);

      _transactions = (results[0]['transactions'] as List)
          .map((t) => InventoryTransaction.fromJson(t))
          .toList();

      final rawDates = results[1]['dates'] as List;
      _dates = rawDates.map((d) {
        if (d is DateTime) return d;
        return DateTime.parse(d.toString());
      }).toList();

      _products = (results[2]['products'] as List)
          .map((p) => ProductMaster.fromJson(p))
          .where((p) => p.isActive)
          .toList();

      // Expand today by default
      final today = _fmtDate(DateTime.now());
      _expandedDates.add(today);

      setState(() {
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _fmtDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _displayDate(DateTime d) => DateFormat('EEEE, MMMM d, yyyy').format(d);

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final isAdmin = auth.user?.role == 'admin';
    final isViewer = auth.user?.role == 'viewer';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!isViewer)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kAccent,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Transaction'),
                  onPressed: () => _showAddDialog(context),
                ),
              const Spacer(),
              if (isAdmin)
                OutlinedButton.icon(
                  icon: const Icon(Icons.expand_outlined),
                  label: const Text('Expand All'),
                  onPressed: () => setState(() {
                    _expandedDates.addAll(_dates.map(_fmtDate));
                  }),
                ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: _kNavy),
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: _load,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ]),
              ),
            )
          else if (_dates.isEmpty)
            const Expanded(
              child: Center(
                  child: Text('No transactions yet. Add one to get started.')),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _dates.length,
                itemBuilder: (ctx, i) => _DateAccordion(
                  date: _dates[i],
                  displayDate: _displayDate(_dates[i]),
                  dateKey: _fmtDate(_dates[i]),
                  isExpanded: _expandedDates.contains(_fmtDate(_dates[i])),
                  isToday: _fmtDate(_dates[i]) == _fmtDate(DateTime.now()),
                  isAdmin: isAdmin,
                  isViewer: isViewer,
                  transactions: _transactions
                      .where((t) =>
                          _fmtDate(t.transactionDate) == _fmtDate(_dates[i]))
                      .toList(),
                  onToggle: () => setState(() {
                    final key = _fmtDate(_dates[i]);
                    if (_expandedDates.contains(key)) {
                      // Non-admin can only collapse; admin can expand/collapse any
                      if (isAdmin || key == _fmtDate(DateTime.now())) {
                        _expandedDates.remove(key);
                      }
                    } else {
                      if (isAdmin || key == _fmtDate(DateTime.now())) {
                        _expandedDates.add(key);
                      }
                    }
                  }),
                  onRefresh: _load,
                  products: _products,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _AddTransactionDialog(products: _products),
    );
    if (result == true) _load();
  }
}

// ─── Date Accordion ───────────────────────────────────────────────────────────
class _DateAccordion extends StatelessWidget {
  final DateTime date;
  final String displayDate;
  final String dateKey;
  final bool isExpanded;
  final bool isToday;
  final bool isAdmin;
  final bool? isViewer;
  final List<InventoryTransaction> transactions;
  final VoidCallback onToggle;
  final VoidCallback onRefresh;
  final List<ProductMaster> products;

  const _DateAccordion({
    required this.date,
    required this.displayDate,
    required this.dateKey,
    required this.isExpanded,
    required this.isToday,
    required this.isAdmin,
    this.isViewer,
    required this.transactions,
    required this.onToggle,
    required this.onRefresh,
    required this.products,
  });

  @override
  Widget build(BuildContext context) {
    final canToggle = isAdmin || isToday;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isToday ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
            color: isToday ? _kAccent : Colors.grey[300]!,
            width: isToday ? 1.5 : 0.5),
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: canToggle ? onToggle : null,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isToday ? _kNavy : Colors.grey[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: isToday ? Colors.white : Colors.grey[700],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    displayDate,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isToday ? Colors.white : Colors.grey[800],
                    ),
                  ),
                  if (isToday) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('TODAY',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    '${transactions.length} transaction${transactions.length != 1 ? 's' : ''}',
                    style: TextStyle(
                        color: isToday ? Colors.white70 : Colors.grey[600],
                        fontSize: 12),
                  ),
                  if (!canToggle) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.lock_outline,
                        size: 14,
                        color: isToday ? Colors.white54 : Colors.grey[400]),
                  ]
                ],
              ),
            ),
          ),

          // Body
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.all(12),
              child: _TransactionGrid(
                transactions: transactions,
                isToday: isToday,
                isAdmin: isAdmin,
                isViewer: isViewer ?? false,
                products: products,
                onRefresh: onRefresh,
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Transaction Grid ─────────────────────────────────────────────────────────
class _TransactionGrid extends StatelessWidget {
  final List<InventoryTransaction> transactions;
  final bool isToday;
  final bool isAdmin;
  final bool isViewer;
  final List<ProductMaster> products;
  final VoidCallback onRefresh;

  const _TransactionGrid({
    required this.transactions,
    required this.isToday,
    required this.isAdmin,
    required this.isViewer,
    required this.products,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No transactions for this day.',
            style: TextStyle(color: Colors.grey)),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[200]!),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: Column(
        children: [
          // Column headers
          _TableHeader(const [
            _Col('Product', flex: 3),
            _Col('QC Code', flex: 2),
            _Col('IN', flex: 1, align: TextAlign.center),
            _Col('OUT', flex: 1, align: TextAlign.center),
            _Col('Stock After', flex: 1, align: TextAlign.center),
            _Col('Reference', flex: 2),
            _Col('Remarks', flex: 2),
            _Col('By', flex: 1, align: TextAlign.center),
            _Col('', flex: 1), // actions
          ]),
          const Divider(height: 1),
          ...transactions.asMap().entries.map((e) {
            final tx = e.value;
            final isEven = e.key.isEven;
            final canEdit = (isAdmin || (isToday)) && !isViewer;
            return _TxRow(
              tx: tx,
              isEven: isEven,
              canEdit: canEdit,
              onRefresh: onRefresh,
              products: products,
            );
          }),
        ],
      ),
    );
  }
}

class _TxRow extends StatelessWidget {
  final InventoryTransaction tx;
  final bool isEven;
  final bool canEdit;
  final VoidCallback onRefresh;
  final List<ProductMaster> products;

  const _TxRow({
    required this.tx,
    required this.isEven,
    required this.canEdit,
    required this.onRefresh,
    required this.products,
  });

  Color _rowColor() {
    switch (tx.stockStatus) {
      case 'critical':
        return _kCritical;
      case 'warning':
        return _kWarning;
      default:
        return isEven ? Colors.white : const Color(0xFFF9FBF9);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _rowColor(),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Row(children: [
        Expanded(
            flex: 3,
            child: Text(tx.productName,
                style: const TextStyle(fontWeight: FontWeight.w500))),
        Expanded(
            flex: 2,
            child: Text(tx.qcCode ?? '—',
                style: TextStyle(color: Colors.grey[600]))),
        Expanded(
          flex: 1,
          child: Center(
            child: Text(
              tx.qtyIn > 0 ? '+${tx.qtyIn}' : '—',
              style: TextStyle(
                  color: tx.qtyIn > 0 ? Colors.green[700] : Colors.grey,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ),
        Expanded(
          flex: 1,
          child: Center(
            child: Text(
              tx.qtyOut > 0 ? '-${tx.qtyOut}' : '—',
              style: TextStyle(
                  color: tx.qtyOut > 0 ? _kCriticalText : Colors.grey,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ),
        Expanded(
          flex: 1,
          child: Center(
            child: Text(
              tx.runningTotal?.toString() ?? '—',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: tx.stockStatus == 'critical'
                    ? _kCriticalText
                    : tx.stockStatus == 'warning'
                        ? _kWarningText
                        : Colors.black87,
              ),
            ),
          ),
        ),
        Expanded(
            flex: 2,
            child: Text(tx.referenceNo ?? '—',
                style: TextStyle(color: Colors.grey[600]))),
        Expanded(
            flex: 2,
            child: Text(tx.remarks ?? '—',
                style: TextStyle(color: Colors.grey[600]))),
        Expanded(
          flex: 1,
          child: Center(
            child: Tooltip(
              message: tx.createdByName ?? '',
              child: CircleAvatar(
                radius: 12,
                backgroundColor: _kNavy.withOpacity(0.15),
                child: Text(
                  (tx.createdByName ?? '?').substring(0, 1).toUpperCase(),
                  style: const TextStyle(fontSize: 10, color: _kNavy),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          flex: 1,
          child: canEdit
              ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _IconBtn(
                    icon: Icons.edit_outlined,
                    color: _kNavy,
                    onTap: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) =>
                            _EditTransactionDialog(tx: tx, products: products),
                      );
                      if (ok == true) onRefresh();
                    },
                  ),
                  _IconBtn(
                    icon: Icons.delete_outline,
                    color: _kCriticalText,
                    onTap: () => _confirmDelete(context),
                  ),
                ])
              : const SizedBox.shrink(),
        ),
      ]),
    );
  }

  Future<void> _confirmDelete(BuildContext ctx) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: Text('Delete ${tx.productName} transaction '
            '(IN:${tx.qtyIn}, OUT:${tx.qtyOut})?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _kCriticalText, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(_, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ApiService.deleteInventoryTransaction(tx.id);
        onRefresh();
      } catch (e) {
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
              content: Text('Error: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }
}

// =============================================================================
// TAB 3: PRODUCT MASTER (Admin only)
// =============================================================================
class _ProductMasterTab extends StatefulWidget {
  const _ProductMasterTab();

  @override
  State<_ProductMasterTab> createState() => _ProductMasterTabState();
}

class _ProductMasterTabState extends State<_ProductMasterTab> {
  List<ProductMaster> _products = [];
  bool _loading = true;
  String? _error;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService.getInventoryProducts();
      final list = (res['products'] as List)
          .map((p) => ProductMaster.fromJson(p))
          .toList();
      setState(() {
        _products = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _kAccent, foregroundColor: Colors.white),
                icon: const Icon(Icons.add),
                label: const Text('Add Product'),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => const _ProductFormDialog(),
                  );
                  if (ok == true) _load();
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search…',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (v) => setState(() => _filter = v.toLowerCase()),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: _kNavy),
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: _load,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ]),
              ),
            )
          else
            Expanded(child: _buildTable()),
        ],
      ),
    );
  }

  Widget _buildTable() {
    final filtered = _products
        .where((p) =>
            _filter.isEmpty ||
            p.productName.toLowerCase().contains(_filter) ||
            (p.qcCode?.toLowerCase().contains(_filter) ?? false))
        .toList();

    if (filtered.isEmpty) {
      return const Center(child: Text('No products found.'));
    }

    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SingleChildScrollView(
          child: Column(
            children: [
              _TableHeader(const [
                _Col('Product Name', flex: 4),
                _Col('QC Code', flex: 2),
                _Col('Maintaining', flex: 2, align: TextAlign.center),
                _Col('Critical', flex: 2, align: TextAlign.center),
                _Col('Active', flex: 1, align: TextAlign.center),
                _Col('Actions', flex: 2, align: TextAlign.center),
              ]),
              const Divider(height: 1),
              ...filtered.asMap().entries.map((e) {
                final p = e.value;
                return Container(
                  color: e.key.isEven ? Colors.white : const Color(0xFFF9FBF9),
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  child: Row(children: [
                    Expanded(
                        flex: 4,
                        child: Text(p.productName,
                            style:
                                const TextStyle(fontWeight: FontWeight.w500))),
                    Expanded(
                        flex: 2,
                        child: Text(p.qcCode ?? '—',
                            style: TextStyle(color: Colors.grey[600]))),
                    Expanded(flex: 2, child: _CenterNum(p.maintainingQty)),
                    Expanded(flex: 2, child: _CenterNum(p.criticalQty)),
                    Expanded(
                      flex: 1,
                      child: Center(
                        child: Icon(
                          p.isActive
                              ? Icons.check_circle
                              : Icons.cancel_outlined,
                          color: p.isActive ? Colors.green[700] : Colors.grey,
                          size: 18,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _IconBtn(
                              icon: Icons.edit_outlined,
                              color: _kNavy,
                              onTap: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (_) =>
                                      _ProductFormDialog(product: p),
                                );
                                if (ok == true) _load();
                              },
                            ),
                            _IconBtn(
                              icon: p.isActive
                                  ? Icons.delete_outline
                                  : Icons.restore,
                              color: p.isActive
                                  ? _kCriticalText
                                  : Colors.green[700]!,
                              onTap: () => _toggleActive(p),
                            ),
                          ]),
                    ),
                  ]),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleActive(ProductMaster p) async {
    if (p.isActive) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Deactivate Product'),
          content: Text(
              'Deactivate "${p.productName}"? It will no longer appear in transaction dropdowns.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(_, false),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _kCriticalText,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(_, true),
              child: const Text('Deactivate'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await ApiService.deleteInventoryProduct(p.id);
    } else {
      await ApiService.updateInventoryProduct(p.id, {'is_active': true});
    }
    _load();
  }
}

// =============================================================================
// DIALOGS
// =============================================================================

// ─── Add Transaction ──────────────────────────────────────────────────────────
class _AddTransactionDialog extends StatefulWidget {
  final List<ProductMaster> products;
  const _AddTransactionDialog({required this.products});

  @override
  State<_AddTransactionDialog> createState() => _AddTransactionDialogState();
}

class _AddTransactionDialogState extends State<_AddTransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  ProductMaster? _selectedProduct;
  final _inCtrl = TextEditingController();
  final _outCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  final _remCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _inCtrl.dispose();
    _outCtrl.dispose();
    _refCtrl.dispose();
    _remCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProduct == null) {
      setState(() => _error = 'Please select a product.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiService.createInventoryTransaction(
        productId: _selectedProduct!.id,
        qtyIn: int.tryParse(_inCtrl.text) ?? 0,
        qtyOut: int.tryParse(_outCtrl.text) ?? 0,
        referenceNo: _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
        remarks: _remCtrl.text.trim().isEmpty ? null : _remCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Inventory Transaction'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: _kCritical,
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(_error!,
                      style: const TextStyle(color: _kCriticalText)),
                ),
              DropdownButtonFormField<ProductMaster>(
                decoration: _inputDeco('Product *'),
                value: _selectedProduct,
                hint: const Text('Select product…'),
                items: widget.products
                    .where((p) => p.isActive)
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(
                              '${p.productName}${p.qcCode != null ? ' [${p.qcCode}]' : ''}'),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedProduct = v),
                validator: (v) => v == null ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _inCtrl,
                    decoration: _inputDeco('IN Quantity'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _outCtrl,
                    decoration: _inputDeco('OUT Quantity'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextFormField(
                controller: _refCtrl,
                decoration: _inputDeco('Reference No. (PO, Job Order…)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _remCtrl,
                decoration: _inputDeco('Remarks (optional)'),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: _kAccent, foregroundColor: Colors.white),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }
}

// ─── Edit Transaction ─────────────────────────────────────────────────────────
class _EditTransactionDialog extends StatefulWidget {
  final InventoryTransaction tx;
  final List<ProductMaster> products;
  const _EditTransactionDialog({required this.tx, required this.products});

  @override
  State<_EditTransactionDialog> createState() => _EditTransactionDialogState();
}

class _EditTransactionDialogState extends State<_EditTransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _inCtrl;
  late final TextEditingController _outCtrl;
  late final TextEditingController _refCtrl;
  late final TextEditingController _remCtrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _inCtrl = TextEditingController(text: widget.tx.qtyIn.toString());
    _outCtrl = TextEditingController(text: widget.tx.qtyOut.toString());
    _refCtrl = TextEditingController(text: widget.tx.referenceNo ?? '');
    _remCtrl = TextEditingController(text: widget.tx.remarks ?? '');
  }

  @override
  void dispose() {
    _inCtrl.dispose();
    _outCtrl.dispose();
    _refCtrl.dispose();
    _remCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiService.updateInventoryTransaction(widget.tx.id, {
        'qty_in': int.tryParse(_inCtrl.text) ?? 0,
        'qty_out': int.tryParse(_outCtrl.text) ?? 0,
        'reference_no':
            _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
        'remarks': _remCtrl.text.trim().isEmpty ? null : _remCtrl.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit — ${widget.tx.productName}'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: _kCritical,
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(_error!,
                      style: const TextStyle(color: _kCriticalText)),
                ),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _inCtrl,
                    decoration: _inputDeco('IN Quantity'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _outCtrl,
                    decoration: _inputDeco('OUT Quantity'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextFormField(
                controller: _refCtrl,
                decoration: _inputDeco('Reference No.'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _remCtrl,
                decoration: _inputDeco('Remarks'),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: _kAccent, foregroundColor: Colors.white),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Update'),
        ),
      ],
    );
  }
}

// ─── Product Form Dialog ──────────────────────────────────────────────────────
class _ProductFormDialog extends StatefulWidget {
  final ProductMaster? product;
  const _ProductFormDialog({this.product});

  @override
  State<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<_ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _codeCtrl;
  late final TextEditingController _maintCtrl;
  late final TextEditingController _critCtrl;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameCtrl = TextEditingController(text: p?.productName ?? '');
    _codeCtrl = TextEditingController(text: p?.qcCode ?? '');
    _maintCtrl =
        TextEditingController(text: p?.maintainingQty.toString() ?? '0');
    _critCtrl = TextEditingController(text: p?.criticalQty.toString() ?? '0');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _maintCtrl.dispose();
    _critCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_isEdit) {
        await ApiService.updateInventoryProduct(widget.product!.id, {
          'product_name': _nameCtrl.text.trim(),
          'qc_code':
              _codeCtrl.text.trim().isEmpty ? null : _codeCtrl.text.trim(),
          'maintaining_qty': int.tryParse(_maintCtrl.text) ?? 0,
          'critical_qty': int.tryParse(_critCtrl.text) ?? 0,
        });
      } else {
        await ApiService.createInventoryProduct(
          productName: _nameCtrl.text.trim(),
          qcCode: _codeCtrl.text.trim().isEmpty ? null : _codeCtrl.text.trim(),
          maintainingQty: int.tryParse(_maintCtrl.text) ?? 0,
          criticalQty: int.tryParse(_critCtrl.text) ?? 0,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit Product' : 'Add Product'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: _kCritical,
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(_error!,
                      style: const TextStyle(color: _kCriticalText)),
                ),
              TextFormField(
                controller: _nameCtrl,
                decoration: _inputDeco('Product Name *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _codeCtrl,
                decoration: _inputDeco('QC Code (optional)'),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _maintCtrl,
                    decoration: _inputDeco('Maintaining Qty'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) => int.tryParse(v ?? '') == null
                        ? 'Number required'
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _critCtrl,
                    decoration: _inputDeco('Critical Qty'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) => int.tryParse(v ?? '') == null
                        ? 'Number required'
                        : null,
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                'Warning shows when stock ≤ Maintaining. Critical alert when stock ≤ Critical.',
                style: TextStyle(color: Colors.grey[600], fontSize: 11),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: _kAccent, foregroundColor: Colors.white),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(_isEdit ? 'Update' : 'Create'),
        ),
      ],
    );
  }
}

// =============================================================================
// SHARED HELPERS & SMALL WIDGETS
// =============================================================================

InputDecoration _inputDeco(String label) => InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );

class _Col {
  final String label;
  final int flex;
  final TextAlign align;
  const _Col(this.label, {this.flex = 1, this.align = TextAlign.left});
}

class _TableHeader extends StatelessWidget {
  final List<_Col> cols;
  const _TableHeader(this.cols);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kNavy,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: Row(
        children: cols.map((c) {
          return Expanded(
            flex: c.flex,
            child: Text(
              c.label,
              textAlign: c.align,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _CenterNum extends StatelessWidget {
  final int value;
  final Color? color;
  final bool dimmed;
  const _CenterNum(this.value, {this.color, this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        value.toString(),
        style: TextStyle(
          fontWeight: dimmed ? FontWeight.normal : FontWeight.w600,
          color: color ?? (dimmed ? Colors.grey[500] : Colors.black87),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
              color: color,
              border: Border.all(color: Colors.grey[400]!),
              borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 12)),
    ]);
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _IconBtn(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}
