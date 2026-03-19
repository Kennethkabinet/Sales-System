import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../config/constants.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'sheet_screen.dart';
import 'settings_screen.dart';

/// Editor Module - For users with editor role
/// Editors can ONLY access Excel sheets and settings (NO dashboard)
class EditorDashboard extends StatefulWidget {
  const EditorDashboard({super.key});

  @override
  State<EditorDashboard> createState() => _EditorDashboardState();
}

class _EditorDashboardState extends State<EditorDashboard> {
  int _selectedIndex = 0; // 0 = Sheets, 1 = Settings

  final TextEditingController _headerSearchCtrl = TextEditingController();
  final FocusNode _headerSearchFocus = FocusNode();

  bool _isSearchIndexLoading = false;
  List<_HeaderSearchItem> _searchItems = const <_HeaderSearchItem>[];
  Map<int, _FolderMeta> _folderMetaById = const <int, _FolderMeta>{};

  List<int>? _pendingFolderPath;
  int? _pendingSheetId;
  String? _pendingSheetName;
  bool? _pendingSheetHasPassword;

  static const Color _kGray = Color(0xFF6B7280);
  static const Color _kBg = Color(0xFFF9FAFB);
  static const Color _kBorder = Color(0xFFE5E7EB);
  static const Color _kBlue = Color(0xFF4285F4);

  String _getInitials(String? fullName, String? username) {
    if (fullName != null && fullName.trim().isNotEmpty) {
      final parts = fullName.trim().split(' ');
      if (parts.length >= 2) {
        return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
      } else if (parts.isNotEmpty) {
        return parts.first[0].toUpperCase();
      }
    }
    if (username != null && username.isNotEmpty) {
      return username[0].toUpperCase();
    }
    return 'E';
  }

  @override
  void initState() {
    super.initState();
    _buildSearchIndex();
  }

  @override
  void dispose() {
    _headerSearchCtrl.dispose();
    _headerSearchFocus.dispose();
    super.dispose();
  }

  void _focusHeaderSearch() {
    _headerSearchFocus.requestFocus();
    _headerSearchCtrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _headerSearchCtrl.text.length,
    );
  }

  List<int> _buildFolderPath(int? folderId) {
    if (folderId == null) return const <int>[];
    final path = <int>[];
    int? current = folderId;
    var guard = 0;
    while (current != null && guard < 64) {
      path.add(current);
      current = _folderMetaById[current]?.parentId;
      guard++;
    }
    return path.reversed.toList(growable: false);
  }

  Future<void> _buildSearchIndex() async {
    if (!mounted) return;
    setState(() {
      _isSearchIndexLoading = true;
    });

    try {
      final items = <_HeaderSearchItem>[
        const _HeaderSearchItem.settings(),
      ];
      final folderMetaById = <int, _FolderMeta>{};
      final addedFolderIds = <int>{};
      final addedSheetIds = <int>{};
      final visited = <int>{};
      final queue = <int>[];

      Future<void> ingestFolders(List<dynamic>? folders) async {
        for (final f in folders ?? const <dynamic>[]) {
          if (f is! Map) continue;
          final id = (f['id'] as num?)?.toInt();
          if (id == null) continue;
          final name = (f['name'] as String?)?.trim() ?? 'Folder';
          final parentId = (f['parent_id'] as num?)?.toInt();
          folderMetaById[id] =
              _FolderMeta(id: id, name: name, parentId: parentId);
          if (addedFolderIds.add(id)) {
            items.add(_HeaderSearchItem.folder(id: id, name: name));
          }
          if (!visited.contains(id)) {
            queue.add(id);
          }
        }
      }

      void ingestSheets(List<dynamic>? sheets) {
        for (final s in sheets ?? const <dynamic>[]) {
          if (s is! Map) continue;
          final id = (s['id'] as num?)?.toInt();
          if (id == null) continue;
          if (!addedSheetIds.add(id)) continue;
          final name = (s['name'] as String?)?.trim() ?? 'Untitled';
          final folderId = (s['folder_id'] as num?)?.toInt();
          final folderName = (s['folder_name'] as String?)?.trim();
          final hasPassword = s['has_password'] == true;
          items.add(
            _HeaderSearchItem.sheet(
              id: id,
              name: name,
              folderId: folderId,
              folderName: folderName,
              hasPassword: hasPassword,
            ),
          );
        }
      }

      // Root: folders + paged sheets.
      final rootResp =
          await ApiService.getSheets(page: 1, limit: 200, rootOnly: true);
      await ingestFolders(rootResp['folders'] as List?);
      ingestSheets(rootResp['sheets'] as List?);
      final rootPages =
          ((rootResp['pagination'] as Map?)?['pages'] as num?)?.toInt() ?? 1;
      for (var p = 2; p <= rootPages; p++) {
        final pageResp =
            await ApiService.getSheets(page: p, limit: 200, rootOnly: true);
        ingestSheets(pageResp['sheets'] as List?);
      }

      // BFS: discover all visible folders and their sheets.
      while (queue.isNotEmpty) {
        final folderId = queue.removeAt(0);
        if (visited.contains(folderId)) continue;
        visited.add(folderId);

        final first =
            await ApiService.getSheets(folderId: folderId, page: 1, limit: 200);
        await ingestFolders(first['folders'] as List?);
        ingestSheets(first['sheets'] as List?);

        final pages =
            ((first['pagination'] as Map?)?['pages'] as num?)?.toInt() ?? 1;
        for (var p = 2; p <= pages; p++) {
          final pageResp = await ApiService.getSheets(
              folderId: folderId, page: p, limit: 200);
          ingestSheets(pageResp['sheets'] as List?);
        }
      }

      if (!mounted) return;
      setState(() {
        _searchItems = items;
        _folderMetaById = folderMetaById;
        _isSearchIndexLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearchIndexLoading = false;
        _searchItems = const <_HeaderSearchItem>[_HeaderSearchItem.settings()];
        _folderMetaById = const <int, _FolderMeta>{};
      });
    }
  }

  void _handleSearchSelected(_HeaderSearchItem item) {
    _headerSearchCtrl.clear();
    FocusManager.instance.primaryFocus?.unfocus();

    if (item.kind == _HeaderSearchKind.settings) {
      setState(() => _selectedIndex = 1);
      return;
    }

    final folderId =
        item.kind == _HeaderSearchKind.folder ? item.id : item.folderId;
    setState(() {
      _selectedIndex = 0;
      _pendingFolderPath = _buildFolderPath(folderId);
      if (item.kind == _HeaderSearchKind.sheet) {
        _pendingSheetId = item.id;
        _pendingSheetName = item.title;
        _pendingSheetHasPassword = item.sheetHasPassword;
      } else {
        _pendingSheetId = null;
        _pendingSheetName = null;
        _pendingSheetHasPassword = null;
      }
    });
  }

  Widget _buildHeaderSearchBar({
    required Color surfaceBg,
    required Color borderColor,
    required Color searchBg,
    required Color textMuted,
    required Color textPrimary,
  }) {
    return RawAutocomplete<_HeaderSearchItem>(
      textEditingController: _headerSearchCtrl,
      focusNode: _headerSearchFocus,
      optionsBuilder: (TextEditingValue textEditingValue) {
        final q = textEditingValue.text.trim().toLowerCase();
        if (q.isEmpty) return const Iterable<_HeaderSearchItem>.empty();

        final matches = _searchItems.where((item) {
          return item.searchKey.contains(q);
        });
        return matches.take(20);
      },
      onSelected: _handleSearchSelected,
      fieldViewBuilder: (context, textCtrl, focusNode, onFieldSubmitted) {
        return Container(
          width: 300,
          height: 38,
          decoration: BoxDecoration(
            color: searchBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              Icon(Icons.search, size: 18, color: textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: textCtrl,
                  focusNode: focusNode,
                  style: TextStyle(fontSize: 13, color: textPrimary),
                  decoration: InputDecoration.collapsed(
                    hintText: 'Search',
                    hintStyle: TextStyle(fontSize: 13, color: textMuted),
                  ),
                ),
              ),
              if (_isSearchIndexLoading)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(textMuted),
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: surfaceBg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: borderColor),
                ),
                child: Text(
                  'Ctrl+K',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: textMuted,
                  ),
                ),
              ),
            ],
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 300,
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                color: surfaceBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
              ),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final opt = options.elementAt(index);
                  late final IconData icon;
                  switch (opt.kind) {
                    case _HeaderSearchKind.settings:
                      icon = Icons.settings_outlined;
                      break;
                    case _HeaderSearchKind.folder:
                      icon = Icons.folder_outlined;
                      break;
                    case _HeaderSearchKind.sheet:
                      icon = Icons.table_chart_outlined;
                      break;
                  }
                  final subtitle = opt.subtitle;
                  return InkWell(
                    onTap: () => onSelected(opt),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Icon(icon, size: 18, color: textMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  opt.title,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (subtitle != null && subtitle.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      subtitle,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: textMuted,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageBg = isDark ? const Color(0xFF111827) : _kBg;
    final surfaceBg = isDark ? const Color(0xFF1F2937) : Colors.white;
    final borderColor = isDark ? const Color(0xFF374151) : _kBorder;
    final textPrimary =
        isDark ? const Color(0xFFF3F4F6) : const Color(0xFF1F2937);
    final textMuted =
        isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final searchBg = isDark ? const Color(0xFF111827) : const Color(0xFFF9FAFB);
    final user = auth.user;
    final initials = _getInitials(user?.fullName, user?.username);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _focusHeaderSearch,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: pageBg,
          body: Row(
            children: [
              // ── Sidebar ──
              Container(
                width: 220,
                decoration: BoxDecoration(
                  color: surfaceBg,
                  border: Border(right: BorderSide(color: borderColor)),
                ),
                child: Column(
                  children: [
                    // Header
                    Container(
                      height: 64,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 46,
                              child: Image.asset(
                                isDark
                                    ? 'assets/images/logo_combined_dark.png'
                                    : 'assets/images/logo_combined.png',
                                fit: BoxFit.contain,
                                alignment: Alignment.center,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.diamond,
                                  size: 18,
                                  color: AppColors.primaryOrange,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // User profile card
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: searchBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: _kBlue,
                            child: Text(
                              initials,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user?.fullName ?? user?.username ?? 'Editor',
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'Editor',
                                  style: TextStyle(
                                    color: textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Nav items
                    _buildNavItem(Icons.apps, 'Work Sheets', 0),
                    _buildNavItem(Icons.settings_outlined, 'Settings', 1),

                    const Spacer(),

                    // Logout
                    _buildLogoutButton(auth),
                    const SizedBox(height: 12),
                  ],
                ),
              ),

              // ── Main content ──
              Expanded(
                child: Column(
                  children: [
                    // Top bar - HireGround style
                    Container(
                      height: 60,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      decoration: BoxDecoration(
                        color: surfaceBg,
                        border: Border(
                            bottom: BorderSide(
                                color: borderColor.withValues(alpha: 0.8))),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _selectedIndex == 0 ? 'Work Sheets' : 'Settings',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                          const Spacer(),
                          // Search bar
                          _buildHeaderSearchBar(
                            surfaceBg: surfaceBg,
                            borderColor: borderColor,
                            searchBg: searchBg,
                            textMuted: textMuted,
                            textPrimary: textPrimary,
                          ),
                          const SizedBox(width: 20),
                          _HeaderIconButton(
                            icon: themeProvider.isDarkMode
                                ? Icons.dark_mode_outlined
                                : Icons.light_mode_outlined,
                            onTap: () =>
                                context.read<ThemeProvider>().toggleTheme(),
                          ),
                          const SizedBox(width: 16),
                          // User profile in header
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: _kBlue,
                                child: Text(initials,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white)),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      user?.fullName ??
                                          user?.username ??
                                          'Editor',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: textPrimary)),
                                  Text('Editor',
                                      style: TextStyle(
                                          fontSize: 11, color: textMuted)),
                                ],
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.keyboard_arrow_down,
                                  size: 18, color: textMuted),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Page content
                    Expanded(
                      child: _selectedIndex == 0
                          ? SheetScreen(
                              initialFolderPath: _pendingFolderPath,
                              initialSheetId: _pendingSheetId,
                              initialSheetName: _pendingSheetName,
                              initialSheetHasPassword: _pendingSheetHasPassword,
                            )
                          : const SettingsScreen(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hoverColor =
        isDark ? const Color(0xFF374151) : const Color(0xFFF3F4F6);
    final selectedBg =
        isDark ? const Color(0xFF1E3A8A) : const Color(0xFFE8F0FE);
    final inactive = isDark ? const Color(0xFFD1D5DB) : _kGray;
    final selected = _selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected ? selectedBg : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: hoverColor,
          onTap: () => setState(() => _selectedIndex = index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: selected ? _kBlue : inactive, size: 20),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? _kBlue : inactive,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton(AuthProvider auth) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hoverColor =
        isDark ? const Color(0xFF374151) : const Color(0xFFF3F4F6);
    final textColor =
        isDark ? const Color(0xFFD1D5DB) : const Color(0xFF6B7280);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: hoverColor,
          onTap: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Logout'),
                content: const Text('Are you sure you want to logout?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryRed,
                        foregroundColor: Colors.white),
                    child: const Text('Logout'),
                  ),
                ],
              ),
            );
            if (confirmed == true) {
              await auth.logout();
              if (mounted) {
                Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const LoginScreen()));
              }
            }
          },
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.logout, color: textColor, size: 20),
                const SizedBox(width: 12),
                Text('Logout',
                    style: TextStyle(color: textColor, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _HeaderSearchKind { settings, folder, sheet }

class _FolderMeta {
  final int id;
  final String name;
  final int? parentId;

  const _FolderMeta({
    required this.id,
    required this.name,
    required this.parentId,
  });
}

class _HeaderSearchItem {
  final _HeaderSearchKind kind;
  final int? id;
  final int? folderId;
  final String title;
  final String? subtitle;
  final bool? sheetHasPassword;
  final String searchKey;

  const _HeaderSearchItem._({
    required this.kind,
    required this.title,
    required this.searchKey,
    this.id,
    this.folderId,
    this.subtitle,
    this.sheetHasPassword,
  });

  const _HeaderSearchItem.settings()
      : this._(
          kind: _HeaderSearchKind.settings,
          title: 'Settings',
          subtitle: 'Settings',
          searchKey: 'settings',
        );

  factory _HeaderSearchItem.folder({required int id, required String name}) {
    return _HeaderSearchItem._(
      kind: _HeaderSearchKind.folder,
      id: id,
      title: name,
      subtitle: 'Folder',
      searchKey: '${name.toLowerCase()} folder',
    );
  }

  factory _HeaderSearchItem.sheet({
    required int id,
    required String name,
    required int? folderId,
    required String? folderName,
    required bool hasPassword,
  }) {
    final subtitle = (folderName != null && folderName.isNotEmpty)
        ? 'Sheet • $folderName'
        : 'Sheet';
    return _HeaderSearchItem._(
      kind: _HeaderSearchKind.sheet,
      id: id,
      folderId: folderId,
      title: name,
      subtitle: subtitle,
      sheetHasPassword: hasPassword,
      searchKey:
          '${name.toLowerCase()} ${folderName?.toLowerCase() ?? ''} sheet',
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111827) : const Color(0xFFF9FAFB);
    final border = isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB);
    final iconColor =
        isDark ? const Color(0xFFD1D5DB) : const Color(0xFF6B7280);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Icon(icon, size: 18, color: iconColor),
      ),
    );
  }
}
