import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0xFF000080),
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const FarManagerApp());
}

const kBgColor = Color(0xFF000080);
const kActivePanelBorder = Color(0xFF00AAAA);
const kInactivePanelBorder = Color(0xFF555555);
const kCursorBg = Color(0xFF00AAAA);
const kCursorText = Color(0xFF000000);
const kSelectedText = Color(0xFFFFFF00);
const kDirText = Color(0xFFFFFFFF);
const kFileText = Color(0xFFC0C0C0);
const kHeaderText = Color(0xFFFFFF00);
const kPathBg = Color(0xFF00AAAA);
const kPathText = Color(0xFF000000);
const kInactiveText = Color(0xFF555555);
const kInfoText = Color(0xFF00AAAA);
const kBtnBg = Color(0xFF1a1a4a);
const kBtnText = Color(0xFFFFFFFF);
const kBtnKey = Color(0xFFFFFF00);
const kFont = 'monospace';

class FileItem {
  final String name;
  final String fullPath;
  final bool isDir;
  final bool isParent;
  final int size;
  final DateTime? modified;

  FileItem({
    required this.name,
    required this.fullPath,
    required this.isDir,
    this.isParent = false,
    this.size = 0,
    this.modified,
  });
}

class PanelState {
  String path;
  int cursor;
  Set<String> selected;
  String sortBy;
  bool sortAsc;
  List<FileItem> items;

  PanelState({
    required this.path,
    this.cursor = 0,
    Set<String>? selected,
    this.sortBy = 'name',
    this.sortAsc = true,
    List<FileItem>? items,
  })  : selected = selected ?? {},
        items = items ?? [];
}

class FarManagerApp extends StatelessWidget {
  const FarManagerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FAR Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(primary: kActivePanelBorder, surface: kBgColor),
        scaffoldBackgroundColor: Colors.black,
        fontFamily: kFont,
      ),
      home: const FarManagerHome(),
    );
  }
}

class FarManagerHome extends StatefulWidget {
  const FarManagerHome({super.key});
  @override
  State<FarManagerHome> createState() => _FarManagerHomeState();
}

class _FarManagerHomeState extends State<FarManagerHome> {
  int activePanel = 0;
  late List<PanelState> panels;
  bool _loading = true;
  String? _toast;

  @override
  void initState() {
    super.initState();
    panels = [
      PanelState(path: '/storage/emulated/0'),
      PanelState(path: '/storage/emulated/0/Download'),
    ];
    _init();
  }

  Future<void> _init() async {
    await _requestPermissions();
    await _refreshBoth();
    setState(() => _loading = false);
  }

  Future<void> _requestPermissions() async {
    await Permission.manageExternalStorage.request();
    await Permission.storage.request();
    await Permission.photos.request();
    await Permission.videos.request();
    await Permission.audio.request();
  }

  Future<void> _refreshPanel(int idx) async {
    final panel = panels[idx];
    try {
      final dir = Directory(panel.path);
      if (!await dir.exists()) { panel.items = []; return; }
      final entries = await dir.list(followLinks: false).toList();
      final items = <FileItem>[];
      for (final e in entries) {
        try {
          final stat = await e.stat();
          items.add(FileItem(
            name: e.path.split('/').last,
            fullPath: e.path,
            isDir: e is Directory,
            size: stat.size,
            modified: stat.modified,
          ));
        } catch (_) {}
      }
      final dirs = items.where((i) => i.isDir).toList();
      final files = items.where((i) => !i.isDir).toList();
      int cmp(FileItem a, FileItem b) {
        int r;
        switch (panel.sortBy) {
          case 'size': r = a.size.compareTo(b.size); break;
          case 'date': r = (a.modified ?? DateTime(0)).compareTo(b.modified ?? DateTime(0)); break;
          default: r = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        }
        return panel.sortAsc ? r : -r;
      }
      dirs.sort(cmp);
      files.sort(cmp);
      final all = <FileItem>[];
      if (panel.path != '/') {
        final parts = panel.path.split('/').where((s) => s.isNotEmpty).toList();
        parts.removeLast();
        final parentPath = '/' + parts.join('/');
        all.add(FileItem(name: '..', fullPath: parentPath.isEmpty ? '/' : parentPath, isDir: true, isParent: true));
      }
      all.addAll(dirs);
      all.addAll(files);
      panel.items = all;
      if (panel.cursor >= all.length) panel.cursor = all.isNotEmpty ? all.length - 1 : 0;
    } catch (_) { panel.items = []; }
  }

  Future<void> _refreshBoth() async {
    await Future.wait([_refreshPanel(0), _refreshPanel(1)]);
    if (mounted) setState(() {});
  }

  Future<void> _refreshActive() async {
    await _refreshPanel(activePanel);
    if (mounted) setState(() {});
  }

  void _showToast(String msg) {
    setState(() => _toast = msg);
    Future.delayed(const Duration(seconds: 2), () { if (mounted) setState(() => _toast = null); });
  }

  FileItem? get _currentItem {
    final p = panels[activePanel];
    if (p.items.isEmpty || p.cursor >= p.items.length) return null;
    return p.items[p.cursor];
  }

  Future<void> _navigate(int idx, FileItem item) async {
    if (item.isDir) {
      panels[idx].path = item.fullPath;
      panels[idx].cursor = 0;
      panels[idx].selected.clear();
      await _refreshPanel(idx);
      setState(() {});
    } else {
      await OpenFilex.open(item.fullPath);
    }
  }

  List<FileItem> _getTargets() {
    final p = panels[activePanel];
    if (p.selected.isNotEmpty) return p.items.where((i) => p.selected.contains(i.name)).toList();
    final cur = _currentItem;
    if (cur != null && !cur.isParent) return [cur];
    return [];
  }

  Future<void> _copyItem(String src, String dst) async {
    if (await FileSystemEntity.isDirectory(src)) {
      await Directory(dst).create(recursive: true);
      await for (final e in Directory(src).list()) {
        await _copyItem(e.path, p.join(dst, e.path.split('/').last));
      }
    } else {
      await File(src).copy(dst);
    }
  }

  void _confirmDialog({required String title, required String msg, required IconData icon, Color iconColor = kActivePanelBorder, required VoidCallback onOk}) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: kBgColor,
      shape: RoundedRectangleBorder(side: const BorderSide(color: kActivePanelBorder, width: 2), borderRadius: BorderRadius.circular(4)),
      title: Row(children: [Icon(icon, color: iconColor, size: 20), const SizedBox(width: 8), Text(title, style: const TextStyle(color: kHeaderText, fontFamily: kFont, fontSize: 15))]),
      content: Text(msg, style: const TextStyle(color: kFileText, fontFamily: kFont, fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена', style: TextStyle(color: kFileText))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kActivePanelBorder),
          onPressed: () { Navigator.pop(context); onOk(); },
          child: Text(title, style: const TextStyle(color: kCursorText, fontFamily: kFont, fontWeight: FontWeight.bold)),
        ),
      ],
    ));
  }

  void _inputDialog({required String title, required String hint, String? initial, required IconData icon, required Function(String) onOk}) {
    final ctrl = TextEditingController(text: initial ?? '');
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: kBgColor,
      shape: RoundedRectangleBorder(side: const BorderSide(color: kActivePanelBorder, width: 2), borderRadius: BorderRadius.circular(4)),
      title: Row(children: [Icon(icon, color: kHeaderText, size: 20), const SizedBox(width: 8), Text(title, style: const TextStyle(color: kHeaderText, fontFamily: kFont, fontSize: 15))]),
      content: TextField(
        controller: ctrl, autofocus: true,
        style: const TextStyle(color: kSelectedText, fontFamily: kFont),
        decoration: InputDecoration(
          hintText: hint, hintStyle: const TextStyle(color: kInactivePanelBorder),
          enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: kActivePanelBorder)),
          focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: kSelectedText, width: 2)),
        ),
        onSubmitted: (v) { Navigator.pop(context); onOk(v); },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена', style: TextStyle(color: kFileText))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kActivePanelBorder),
          onPressed: () { Navigator.pop(context); onOk(ctrl.text); },
          child: Text(title, style: const TextStyle(color: kCursorText, fontFamily: kFont, fontWeight: FontWeight.bold)),
        ),
      ],
    ));
  }

  void _doCopy() {
    final targets = _getTargets();
    if (targets.isEmpty) return _showToast('Нечего копировать');
    final dst = panels[1 - activePanel].path;
    _confirmDialog(title: 'Копировать', msg: 'Копировать ${targets.length} объект(ов)\nв $dst?', icon: Icons.copy, onOk: () async {
      for (final item in targets) {
        try { await _copyItem(item.fullPath, p.join(dst, item.name)); } catch (_) {}
      }
      await _refreshBoth();
      _showToast('Скопировано: ${targets.length}');
    });
  }

  void _doMove() {
    final targets = _getTargets();
    if (targets.isEmpty) return _showToast('Нечего перемещать');
    final dst = panels[1 - activePanel].path;
    _confirmDialog(title: 'Переместить', msg: 'Переместить ${targets.length} объект(ов)\nв $dst?', icon: Icons.drive_file_move, onOk: () async {
      for (final item in targets) {
        try {
          if (item.isDir) await Directory(item.fullPath).rename(p.join(dst, item.name));
          else await File(item.fullPath).rename(p.join(dst, item.name));
        } catch (_) {
          await _copyItem(item.fullPath, p.join(dst, item.name));
          if (item.isDir) await Directory(item.fullPath).delete(recursive: true);
          else await File(item.fullPath).delete();
        }
      }
      panels[activePanel].selected.clear();
      await _refreshBoth();
      _showToast('Перемещено: ${targets.length}');
    });
  }

  void _doDelete() {
    final targets = _getTargets();
    if (targets.isEmpty) return _showToast('Нечего удалять');
    _confirmDialog(title: 'Удалить', msg: 'Удалить ${targets.length} объект(ов)?', icon: Icons.delete, iconColor: Colors.red, onOk: () async {
      for (final item in targets) {
        try {
          if (item.isDir) await Directory(item.fullPath).delete(recursive: true);
          else await File(item.fullPath).delete();
        } catch (_) {}
      }
      panels[activePanel].selected.clear();
      panels[activePanel].cursor = 0;
      await _refreshActive();
      _showToast('Удалено: ${targets.length}');
    });
  }

  void _doMkDir() {
    _inputDialog(title: 'Новая папка', hint: 'Имя папки', icon: Icons.create_new_folder, onOk: (name) async {
      if (name.trim().isEmpty) return;
      await Directory(p.join(panels[activePanel].path, name.trim())).create();
      await _refreshActive();
      _showToast('Создана: $name');
    });
  }

  void _doNewFile() {
    _inputDialog(title: 'Новый файл', hint: 'Имя файла', icon: Icons.note_add, onOk: (name) async {
      if (name.trim().isEmpty) return;
      await File(p.join(panels[activePanel].path, name.trim())).create();
      await _refreshActive();
      _showToast('Создан: $name');
    });
  }

  void _doRename() {
    final item = _currentItem;
    if (item == null || item.isParent) return;
    _inputDialog(title: 'Переименовать', hint: 'Новое имя', initial: item.name, icon: Icons.edit, onOk: (name) async {
      if (name.trim().isEmpty || name == item.name) return;
      final newPath = p.join(panels[activePanel].path, name.trim());
      try {
        if (item.isDir) await Directory(item.fullPath).rename(newPath);
        else await File(item.fullPath).rename(newPath);
        await _refreshActive();
        _showToast('${item.name} → $name');
      } catch (_) { _showToast('Ошибка!'); }
    });
  }

  void _doProperties() {
    final item = _currentItem;
    if (item == null || item.isParent) return;
    showDialog(context: context, builder: (_) => _PropertiesDialog(item: item));
  }

  @override
  Widget build(BuildContext context) {
    final landscape = MediaQuery.of(context).orientation == Orientation.landscape;
    if (_loading) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(color: kActivePanelBorder),
        SizedBox(height: 16),
        Text('FAR Manager', style: TextStyle(color: kActivePanelBorder, fontFamily: kFont, fontSize: 18)),
      ])));
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: Column(children: [
        _buildTitleBar(),
        Expanded(child: landscape
          ? Row(children: [Expanded(child: _buildPanel(0)), const SizedBox(width: 1), Expanded(child: _buildPanel(1))])
          : Column(children: [Expanded(child: _buildPanel(0)), const SizedBox(height: 1), Expanded(child: _buildPanel(1))])),
        _buildInfoBar(),
        _buildToolbar(),
        _buildFnBar(),
      ])),
      floatingActionButton: _toast != null ? Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: kActivePanelBorder, borderRadius: BorderRadius.circular(4)),
        child: Text(_toast!, style: const TextStyle(color: kCursorText, fontFamily: kFont, fontWeight: FontWeight.bold)),
      ) : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildTitleBar() {
    return Container(
      color: kBgColor,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(children: [
        const Text('◈ FAR Manager', style: TextStyle(color: kActivePanelBorder, fontFamily: kFont, fontSize: 13, fontWeight: FontWeight.bold)),
        const Spacer(),
        GestureDetector(onTap: _refreshBoth, child: const Icon(Icons.refresh, color: kActivePanelBorder, size: 18)),
      ]),
    );
  }

  Widget _buildPanel(int idx) {
    final isActive = idx == activePanel;
    final panel = panels[idx];
    return GestureDetector(
      onTap: () => setState(() => activePanel = idx),
      child: Container(
        decoration: BoxDecoration(
          color: kBgColor,
          border: Border.all(color: isActive ? kActivePanelBorder : kInactivePanelBorder, width: isActive ? 2 : 1),
        ),
        child: Column(children: [
          Container(
            width: double.infinity,
            color: isActive ? kPathBg : kInactivePanelBorder,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(panel.path, style: TextStyle(color: isActive ? kPathText : Colors.white70, fontFamily: kFont, fontSize: 11, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kInactivePanelBorder))),
            child: Row(children: [
              Expanded(child: Text('Имя', style: _hdr)),
              SizedBox(width: 56, child: Text('Размер', style: _hdr, textAlign: TextAlign.right)),
              SizedBox(width: 72, child: Text('Дата', style: _hdr, textAlign: TextAlign.right)),
            ]),
          ),
          Expanded(child: _FileList(
            panel: panel, isActive: isActive,
            onTap: (i) => setState(() { activePanel = idx; panel.cursor = i; }),
            onDoubleTap: (i) { activePanel = idx; _navigate(idx, panel.items[i]); },
            onLongPress: (i) {
              setState(() { activePanel = idx; panel.cursor = i; });
              final item = panel.items[i];
              if (!item.isParent) {
                setState(() {
                  if (panel.selected.contains(item.name)) panel.selected.remove(item.name);
                  else panel.selected.add(item.name);
                });
              }
            },
          )),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: kInactivePanelBorder))),
            child: Row(children: [
              Text('${panel.items.where((i) => i.isDir && !i.isParent).length} папок  ${panel.items.where((i) => !i.isDir).length} файлов',
                style: const TextStyle(color: kInfoText, fontFamily: kFont, fontSize: 10)),
              const Spacer(),
              if (panel.selected.isNotEmpty) Text('Выбрано: ${panel.selected.length}',
                style: const TextStyle(color: kSelectedText, fontFamily: kFont, fontSize: 10)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildInfoBar() {
    final item = _currentItem;
    final panel = panels[activePanel];
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(children: [
        if (item != null && !item.isParent) ...[
          Expanded(child: Text(item.name, style: const TextStyle(color: kActivePanelBorder, fontFamily: kFont, fontSize: 11), overflow: TextOverflow.ellipsis)),
          if (!item.isDir) Text(_fmtSize(item.size), style: const TextStyle(color: kFileText, fontFamily: kFont, fontSize: 10)),
          if (item.modified != null) ...[const SizedBox(width: 8), Text(_fmtDate(item.modified!), style: const TextStyle(color: kInactivePanelBorder, fontFamily: kFont, fontSize: 9))],
        ],
        const Spacer(),
        Text('${panel.sortBy} ${panel.sortAsc ? '↑' : '↓'}', style: const TextStyle(color: kInactivePanelBorder, fontFamily: kFont, fontSize: 9)),
      ]),
    );
  }

  Widget _buildToolbar() {
    final item = _currentItem;
    final panel = panels[activePanel];
    return Container(
      color: const Color(0xFF000022),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Row(children: [
        _tb('Всё', () { setState(() { panel.selected = panel.items.where((i) => !i.isParent).map((i) => i.name).toSet(); }); }),
        const SizedBox(width: 4),
        _tb('Снять', () { setState(() => panel.selected.clear()); }),
        const SizedBox(width: 4),
        if (item != null && !item.isParent)
          _tb(panel.selected.contains(item.name) ? '✓Снять' : '✓Выбр.', () {
            setState(() {
              if (panel.selected.contains(item.name)) panel.selected.remove(item.name);
              else panel.selected.add(item.name);
            });
          }, color: kSelectedText),
        const SizedBox(width: 4),
        _tb('Открыть ↵', () { if (item != null) _navigate(activePanel, item); }, color: kActivePanelBorder),
        const Spacer(),
        _tb('Сорт: ${panel.sortBy}', () {
          const sorts = ['name', 'size', 'date'];
          final i = sorts.indexOf(panel.sortBy);
          panel.sortBy = sorts[(i + 1) % sorts.length];
          _refreshActive();
        }),
      ]),
    );
  }

  Widget _tb(String label, VoidCallback fn, {Color color = kBtnText}) {
    return GestureDetector(
      onTap: fn,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: kBtnBg, border: Border.all(color: kInactivePanelBorder), borderRadius: BorderRadius.circular(2)),
        child: Text(label, style: TextStyle(color: color, fontFamily: kFont, fontSize: 11)),
      ),
    );
  }

  Widget _buildFnBar() {
    final btns = [
      ('F3', 'Просм.', () {
        final item = _currentItem;
        if (item != null && !item.isDir && !item.isParent) showDialog(context: context, builder: (_) => _ViewerDialog(item: item));
      }),
      ('F5', 'Копия', _doCopy),
      ('F6', 'Перем.', _doMove),
      ('F7', 'МкДир', _doMkDir),
      ('F8', 'Удал.', _doDelete),
      ('F9', 'Переим.', _doRename),
      ('+', 'Файл', _doNewFile),
      ('TAB', 'Панель', () => setState(() => activePanel = 1 - activePanel)),
      ('ℹ', 'Свойства', _doProperties),
    ];
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
      child: Wrap(spacing: 3, runSpacing: 3, children: btns.map((b) => GestureDetector(
        onTap: b.$3,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(color: kBtnBg, border: Border.all(color: kInactivePanelBorder), borderRadius: BorderRadius.circular(2)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(b.$1, style: const TextStyle(color: kBtnKey, fontFamily: kFont, fontSize: 9)),
            Text(b.$2, style: const TextStyle(color: kBtnText, fontFamily: kFont, fontSize: 10)),
          ]),
        ),
      )).toList()),
    );
  }

  static const _hdr = TextStyle(color: kHeaderText, fontFamily: kFont, fontSize: 10);
}

class _FileList extends StatefulWidget {
  final PanelState panel;
  final bool isActive;
  final Function(int) onTap;
  final Function(int) onDoubleTap;
  final Function(int) onLongPress;
  const _FileList({required this.panel, required this.isActive, required this.onTap, required this.onDoubleTap, required this.onLongPress});
  @override
  State<_FileList> createState() => _FileListState();
}

class _FileListState extends State<_FileList> {
  final _scroll = ScrollController();
  @override
  void didUpdateWidget(covariant _FileList old) {
    super.didUpdateWidget(old);
    if (widget.isActive && widget.panel.cursor != old.panel.cursor) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          const h = 24.0;
          final target = widget.panel.cursor * h;
          final vp = _scroll.position.viewportDimension;
          final off = _scroll.offset;
          if (target < off || target + h > off + vp) {
            _scroll.animateTo((target - vp / 2).clamp(0, _scroll.position.maxScrollExtent), duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
          }
        }
      });
    }
  }
  @override
  Widget build(BuildContext context) {
    final items = widget.panel.items;
    return ListView.builder(
      controller: _scroll,
      itemCount: items.length,
      itemExtent: 24,
      itemBuilder: (_, i) {
        final item = items[i];
        final isCursor = widget.isActive && i == widget.panel.cursor;
        final isSel = widget.panel.selected.contains(item.name);
        final textColor = isCursor ? kCursorText : isSel ? kSelectedText : item.isDir ? kDirText : kFileText;
        return GestureDetector(
          onTap: () => widget.onTap(i),
          onDoubleTap: () => widget.onDoubleTap(i),
          onLongPress: () => widget.onLongPress(i),
          child: Container(
            color: isCursor ? (widget.isActive ? kCursorBg : kInactivePanelBorder) : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.centerLeft,
            child: Row(children: [
              Text(item.isParent ? '⬆' : item.isDir ? '▶' : ' ', style: TextStyle(color: textColor, fontSize: 10)),
              const SizedBox(width: 3),
              Expanded(child: Text(item.name, style: TextStyle(color: textColor, fontFamily: kFont, fontSize: 12, fontWeight: item.isDir ? FontWeight.bold : FontWeight.normal), overflow: TextOverflow.ellipsis)),
              SizedBox(width: 56, child: Text(
                item.isParent ? '' : item.isDir ? '<DIR>' : _fmtSize(item.size),
                style: TextStyle(color: isCursor ? kCursorText : item.isDir ? const Color(0xFF00AAAA) : kFileText, fontFamily: kFont, fontSize: 10),
                textAlign: TextAlign.right, overflow: TextOverflow.ellipsis,
              )),
              SizedBox(width: 72, child: Text(
                item.isParent || item.modified == null ? '' : _fmtDate(item.modified!),
                style: TextStyle(color: isCursor ? kCursorText : kInactivePanelBorder, fontFamily: kFont, fontSize: 9),
                textAlign: TextAlign.right,
              )),
            ]),
          ),
        );
      },
    );
  }
}

class _ViewerDialog extends StatefulWidget {
  final FileItem item;
  const _ViewerDialog({required this.item});
  @override
  State<_ViewerDialog> createState() => _ViewerDialogState();
}

class _ViewerDialogState extends State<_ViewerDialog> {
  String _content = 'Загрузка...';
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final f = File(widget.item.fullPath);
      final size = await f.length();
      if (size > 512 * 1024) { setState(() => _content = '[Файл слишком большой: ${_fmtSize(size)}]'); return; }
      final bytes = await f.readAsBytes();
      try { setState(() => _content = String.fromCharCodes(bytes)); }
      catch (_) { setState(() => _content = '[Бинарный файл: ${_fmtSize(size)}]'); }
    } catch (e) { setState(() => _content = 'Ошибка: $e'); }
  }
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(8),
      child: Column(children: [
        Container(color: kActivePanelBorder, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            Expanded(child: Text('👁 ${widget.item.name}', style: const TextStyle(color: kCursorText, fontFamily: kFont, fontWeight: FontWeight.bold, fontSize: 13))),
            GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(Icons.close, color: Colors.black, size: 20)),
          ])),
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(8), child: SelectableText(_content, style: const TextStyle(color: kFileText, fontFamily: kFont, fontSize: 12)))),
        Container(color: kBgColor, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            Text(_fmtSize(widget.item.size), style: const TextStyle(color: kInfoText, fontFamily: kFont, fontSize: 10)),
            const Spacer(),
            TextButton(onPressed: () => OpenFilex.open(widget.item.fullPath), child: const Text('Открыть в приложении', style: TextStyle(color: kActivePanelBorder, fontSize: 11))),
          ])),
      ]),
    );
  }
}

class _PropertiesDialog extends StatefulWidget {
  final FileItem item;
  const _PropertiesDialog({required this.item});
  @override
  State<_PropertiesDialog> createState() => _PropertiesDialogState();
}

class _PropertiesDialogState extends State<_PropertiesDialog> {
  Map<String, String> _props = {};
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final props = <String, String>{};
    props['Имя'] = widget.item.name;
    props['Путь'] = widget.item.fullPath;
    props['Тип'] = widget.item.isDir ? 'Папка' : widget.item.name.contains('.') ? '${widget.item.name.split('.').last.toUpperCase()} файл' : 'Файл';
    props['Размер'] = _fmtSize(widget.item.size);
    if (widget.item.modified != null) props['Изменён'] = DateFormat('dd.MM.yyyy HH:mm').format(widget.item.modified!);
    if (widget.item.isDir) {
      try {
        int count = 0, size = 0;
        await for (final e in Directory(widget.item.fullPath).list(recursive: true, followLinks: false)) {
          count++;
          if (e is File) size += await e.length();
        }
        props['Содержит'] = '$count объектов';
        props['Всего'] = _fmtSize(size);
      } catch (_) {}
    }
    setState(() => _props = props);
  }
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kBgColor,
      shape: RoundedRectangleBorder(side: const BorderSide(color: kActivePanelBorder, width: 2), borderRadius: BorderRadius.circular(4)),
      title: const Text('Свойства', style: TextStyle(color: kHeaderText, fontFamily: kFont)),
      content: Column(mainAxisSize: MainAxisSize.min, children: _props.entries.map((e) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 90, child: Text('${e.key}:', style: const TextStyle(color: kInfoText, fontFamily: kFont, fontSize: 12))),
          Expanded(child: Text(e.value, style: const TextStyle(color: kFileText, fontFamily: kFont, fontSize: 12))),
        ]),
      )).toList()),
      actions: [ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kActivePanelBorder), onPressed: () => Navigator.pop(context), child: const Text('OK', style: TextStyle(color: kCursorText, fontFamily: kFont, fontWeight: FontWeight.bold)))],
    );
  }
}

String _fmtSize(int size) {
  if (size < 1024) return '${size}B';
  if (size < 1048576) return '${(size / 1024).toStringAsFixed(1)}K';
  if (size < 1073741824) return '${(size / 1048576).toStringAsFixed(1)}M';
  return '${(size / 1073741824).toStringAsFixed(2)}G';
}

String _fmtDate(DateTime d) => DateFormat('dd.MM.yy HH:mm').format(d);
