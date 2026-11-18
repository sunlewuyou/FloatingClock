import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SavedCoordinate {
  const _SavedCoordinate({required this.name, required this.x, required this.y, required this.screenWidth, required this.screenHeight, required this.densityDpi, required this.rotation});
  final String name;
  final int x;
  final int y;
  final int screenWidth;
  final int screenHeight;
  final int densityDpi;
  final int rotation;

  Map<String, Object> toJson() => {'name': name, 'x': x, 'y': y, 'screenWidth': screenWidth, 'screenHeight': screenHeight, 'densityDpi': densityDpi, 'rotation': rotation};

  static _SavedCoordinate? fromJson(Object? value) {
    if (value is! Map) return null;
    final name = value['name'];
    final x = value['x'];
    final y = value['y'];
    final width = value['screenWidth'];
    final height = value['screenHeight'];
    final density = value['densityDpi'];
    final rotation = value['rotation'];
    if (name is! String || name.trim().isEmpty || x is! num || y is! num || width is! num || height is! num || density is! num || rotation is! num || x < 0 || y < 0 || width <= 0 || height <= 0 || density <= 0) return null;
    return _SavedCoordinate(name: name, x: x.toInt(), y: y.toInt(), screenWidth: width.toInt(), screenHeight: height.toInt(), densityDpi: density.toInt(), rotation: rotation.toInt());
  }
}

class ScheduledTaskPage extends StatefulWidget {
  const ScheduledTaskPage({super.key, required this.sourceLabel, required this.offsetMillis, required this.refreshOffset});
  final String sourceLabel;
  final int offsetMillis;
  final Future<int?> Function() refreshOffset;

  @override
  State<ScheduledTaskPage> createState() => _ScheduledTaskPageState();
}

class _ScheduledTaskPageState extends State<ScheduledTaskPage> with WidgetsBindingObserver {
  static const MethodChannel _channel = MethodChannel('floating_clock');
  static const String _coordinatesKey = 'scheduled_click_coordinates_v1';
  static const String _lastCoordinateKey = 'scheduled_click_last_coordinate_v1';

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _secondController = TextEditingController(text: '00');
  final TextEditingController _millisecondController = TextEditingController(text: '000');
  final List<_SavedCoordinate> _coordinates = [];
  Timer? _refreshTimer;
  _SavedCoordinate? _selectedCoordinate;
  DateTime _targetDate = DateTime.now();
  TimeOfDay _targetTime = TimeOfDay.now();
  bool _gestureApiSupported = true;
  bool _accessibilityEnabled = false;
  bool _overlayAllowed = false;
  bool _exactAlarmAllowed = true;
  bool _taskActive = false;
  int _effectiveOffsetMillis = 0;
  bool _busy = false;
  String _taskStatus = '尚未创建任务';
  String _taskTargetLabel = '';
  String _taskSourceLabel = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _effectiveOffsetMillis = widget.offsetMillis;
    _taskSourceLabel = widget.sourceLabel;
    final now = DateTime.now().add(const Duration(minutes: 1));
    _targetDate = DateTime(now.year, now.month, now.day);
    _targetTime = TimeOfDay(hour: now.hour, minute: now.minute);
    _loadSavedState();
    _refreshPermissions();
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted && _taskActive) setState(() {});
    });
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _nameController.dispose();
    _secondController.dispose();
    _millisecondController.dispose();
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermissions();
      _refreshTaskState();
    }
  }

  Future<void> _refreshTaskState() async {
    try {
      final state = await _channel.invokeMapMethod<Object?, Object?>('getScheduledTaskState');
      if (!mounted || state == null) return;
      setState(() {
        _taskActive = state['active'] == true;
        _taskStatus = state['status']?.toString() ?? _taskStatus;
        _taskTargetLabel = state['targetLabel']?.toString() ?? _taskTargetLabel;
        _effectiveOffsetMillis = (state['sourceOffsetMillis'] as num?)?.toInt() ?? _effectiveOffsetMillis;
        _taskSourceLabel = state['sourceLabel']?.toString() ?? _taskSourceLabel;
      });
    } on PlatformException catch (error) {
      debugPrint('Unable to refresh scheduled task state: $error');
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (!mounted) return;
    if (call.method == 'onCoordinatePicked' && call.arguments is Map) {
      final args = Map<Object?, Object?>.from(call.arguments as Map);
      final x = (args['x'] as num?)?.toInt();
      final y = (args['y'] as num?)?.toInt();
      final width = (args['screenWidth'] as num?)?.toInt();
      final height = (args['screenHeight'] as num?)?.toInt();
      final density = (args['densityDpi'] as num?)?.toInt();
      final rotation = (args['rotation'] as num?)?.toInt();
      if (x != null && y != null && width != null && height != null && density != null && rotation != null) {
        setState(() {
          _nameController.text = _nameController.text.trim().isEmpty ? '坐标 ${_coordinates.length + 1}' : _nameController.text;
          _selectedCoordinate = _SavedCoordinate(name: _nameController.text.trim(), x: x, y: y, screenWidth: width, screenHeight: height, densityDpi: density, rotation: rotation);
        });
      }
    } else if (call.method == 'onScheduledTaskFinished') {
      final args = call.arguments is Map ? Map<Object?, Object?>.from(call.arguments as Map) : <Object?, Object?>{};
      setState(() {
        _taskActive = false;
        _busy = false;
        _taskStatus = args['status']?.toString() ?? '任务已结束';
      });
    }
  }

  Future<void> _loadSavedState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_coordinatesKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _coordinates.addAll(decoded.map(_SavedCoordinate.fromJson).whereType<_SavedCoordinate>());
        }
      } catch (_) { /* Ignore corrupt user preference data and keep the UI usable. */ }
    }
    final lastName = prefs.getString(_lastCoordinateKey);
    if (_coordinates.isNotEmpty) {
      final matches = _coordinates.where((c) => c.name == lastName);
      _selectedCoordinate = matches.isNotEmpty ? matches.first : _coordinates.first;
      _nameController.text = _selectedCoordinate!.name;
    }
    try {
      final state = await _channel.invokeMapMethod<Object?, Object?>('getScheduledTaskState');
      if (mounted && state != null) {
        setState(() {
          _taskActive = state['active'] == true;
          _effectiveOffsetMillis = (state['sourceOffsetMillis'] as num?)?.toInt() ?? widget.offsetMillis;
          final savedTarget = (state['targetSystemEpochMs'] as num?)?.toInt();
          if (savedTarget != null && savedTarget > 0) {
            final sourceTarget = DateTime.fromMillisecondsSinceEpoch(savedTarget + _effectiveOffsetMillis);
            _targetDate = DateTime(sourceTarget.year, sourceTarget.month, sourceTarget.day);
            _targetTime = TimeOfDay(hour: sourceTarget.hour, minute: sourceTarget.minute);
            _secondController.text = sourceTarget.second.toString().padLeft(2, '0');
            _millisecondController.text = sourceTarget.millisecond.toString().padLeft(3, '0');
          }
          _taskStatus = state['status']?.toString() ?? _taskStatus;
          _taskTargetLabel = state['targetLabel']?.toString() ?? '';
          _taskSourceLabel = state['sourceLabel']?.toString() ?? widget.sourceLabel;
        });
      }
    } on PlatformException catch (error) {
      debugPrint('Unable to restore scheduled task state: $error');
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveCoordinates() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_coordinatesKey, jsonEncode(_coordinates.map((c) => c.toJson()).toList()));
    if (_selectedCoordinate != null) await prefs.setString(_lastCoordinateKey, _selectedCoordinate!.name);
  }

  Future<void> _refreshPermissions() async {
    try {
      final results = await Future.wait<bool>([
        _channel.invokeMethod<bool>('isGestureApiSupported').then((v) => v ?? false),
        _channel.invokeMethod<bool>('isAccessibilityEnabled').then((v) => v ?? false),
        _channel.invokeMethod<bool>('isExactAlarmAllowed').then((v) => v ?? false),
        _channel.invokeMethod<bool>('hasPermission').then((v) => v ?? false),
      ]);
      if (mounted) setState(() { _gestureApiSupported = results[0]; _accessibilityEnabled = results[1]; _exactAlarmAllowed = results[2]; _overlayAllowed = results[3]; });
    } on PlatformException catch (error) {
      debugPrint('Permission check failed: $error');
    }
  }

  Future<void> _pickCoordinate() async {
    try {
      final allowed = await _channel.invokeMethod<bool>('hasPermission') ?? false;
      if (!allowed) {
        await _channel.invokeMethod('requestPermission');
        return;
      }
      await _channel.invokeMethod('pickCoordinate');
    } on PlatformException catch (error) {
      _showMessage(error.message ?? '无法打开坐标选择层');
    }
  }

  Future<void> _saveCurrentCoordinate() async {
    final coordinate = _selectedCoordinate;
    if (coordinate == null) {
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showMessage('请先填写坐标名称');
      return;
    }
    final saved = _SavedCoordinate(name: name, x: coordinate.x, y: coordinate.y, screenWidth: coordinate.screenWidth, screenHeight: coordinate.screenHeight, densityDpi: coordinate.densityDpi, rotation: coordinate.rotation);
    setState(() {
      final index = _coordinates.indexWhere((c) => c.name == name);
      if (index >= 0) {
        _coordinates[index] = saved;
      } else {
        _coordinates.add(saved);
      }
      _selectedCoordinate = saved;
    });
    await _saveCoordinates();
    _showMessage('坐标已保存');
  }

  DateTime get _targetSourceDateTime {
    final ms = int.tryParse(_millisecondController.text) ?? 0;
    final second = int.tryParse(_secondController.text) ?? 0;
    return DateTime(_targetDate.year, _targetDate.month, _targetDate.day,
        _targetTime.hour, _targetTime.minute, second.clamp(0, 59).toInt(), ms.clamp(0, 999).toInt());
  }

  String _formatDateTime(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:${value.second.toString().padLeft(2, '0')}.${value.millisecond.toString().padLeft(3, '0')}';

  Future<void> _toggleTask() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_taskActive) {
        await _channel.invokeMethod<bool>('cancelScheduledClick');
        if (mounted) setState(() { _taskActive = false; _taskStatus = '已停止'; });
        return;
      }
      await _refreshPermissions();
      if (!_gestureApiSupported) {
        _showMessage('当前 Android 版本不支持无障碍手势派发，需要 Android 7.0 或更高版本');
        return;
      }
      if (!_accessibilityEnabled) {
        _showMessage('请先启用定时点击无障碍服务');
        await _channel.invokeMethod('openAccessibilitySettings');
        return;
      }
      final secondText = _secondController.text.trim();
      final millisecondText = _millisecondController.text.trim();
      final secondValue = int.tryParse(secondText);
      final millisecondValue = int.tryParse(millisecondText);
      if (secondValue == null || secondText.length != 2 || secondValue < 0 || secondValue > 59 ||
          millisecondValue == null || millisecondValue < 0 || millisecondValue > 999 || millisecondText.length != 3) {
        _showMessage('请填写有效的秒（00–59）和三位毫秒（000–999）');
        return;
      }
      if (!_exactAlarmAllowed) {
        _showMessage('Android 需要精确闹钟权限才能安排定时任务');
        await _channel.invokeMethod('requestExactAlarmPermission');
        return;
      }
      final coordinate = _selectedCoordinate;
      if (coordinate == null || !_coordinates.contains(coordinate)) { _showMessage('请先点选坐标，填写名称并保存后再开始任务'); return; }
      if (_nameController.text.trim() != coordinate.name) { _showMessage('坐标名称已修改，请先保存名称变更'); return; }
      final freshOffset = await widget.refreshOffset();
      if (freshOffset == null) {
        _showMessage('当前时间源校时失败，未创建任务。请检查网络或切换时间源后重试。');
        return;
      }
      final target = _targetSourceDateTime;
      final targetSourceEpoch = target.millisecondsSinceEpoch;
      final targetSystemEpoch = targetSourceEpoch - freshOffset;
      if (targetSystemEpoch <= DateTime.now().millisecondsSinceEpoch + 250) {
        _showMessage('目标时间必须至少在当前时间 250 毫秒之后');
        return;
      }
      final label = _formatDateTime(target);
      await _saveCoordinates();
      await _channel.invokeMethod<bool>('scheduleClick', {
        'targetSystemEpochMs': targetSystemEpoch,
        'x': coordinate.x,
        'y': coordinate.y,
        'coordinateName': coordinate.name,
        'screenWidth': coordinate.screenWidth,
        'screenHeight': coordinate.screenHeight,
        'densityDpi': coordinate.densityDpi,
        'rotation': coordinate.rotation,
        'targetLabel': label,
        'sourceOffsetMillis': freshOffset,
        'sourceLabel': widget.sourceLabel,
      });
      if (mounted) setState(() { _taskActive = true; _effectiveOffsetMillis = freshOffset; _taskStatus = '等待执行'; _taskTargetLabel = label; _taskSourceLabel = widget.sourceLabel; });
    } on PlatformException catch (error) {
      _showMessage(error.message ?? '任务操作失败');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final target = _targetSourceDateTime;
    final remaining = target.millisecondsSinceEpoch - _effectiveOffsetMillis - DateTime.now().millisecondsSinceEpoch;
    return Scaffold(
      appBar: AppBar(title: const Text('定时点击任务')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('点击坐标', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('屏幕点选后保存多个位置，并可随时切换。上次使用的位置会自动加载。', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: DropdownButtonFormField<_SavedCoordinate>(
            initialValue: _coordinates.contains(_selectedCoordinate) ? _selectedCoordinate : null,
            decoration: const InputDecoration(labelText: '已保存坐标'),
            items: _coordinates.map((c) => DropdownMenuItem(value: c, child: Text('${c.name}  (${c.x}, ${c.y})'))).toList(),
            onChanged: _taskActive ? null : (value) async { setState(() { _selectedCoordinate = value; if (value != null) _nameController.text = value.name; }); await _saveCoordinates(); },
          )), IconButton(tooltip: '删除坐标', onPressed: _taskActive || _selectedCoordinate == null ? null : () async {
            setState(() { _coordinates.removeWhere((c) => c.name == _selectedCoordinate!.name); _selectedCoordinate = _coordinates.isEmpty ? null : _coordinates.first; });
            await _saveCoordinates();
          }, icon: const Icon(Icons.delete_outline))]),
          const SizedBox(height: 8),
          TextField(controller: _nameController, enabled: !_taskActive, decoration: const InputDecoration(labelText: '坐标名称', hintText: '例如：确认按钮')),
          const SizedBox(height: 8),
          if (_selectedCoordinate != null) Text('当前坐标：X ${_selectedCoordinate!.x}，Y ${_selectedCoordinate!.y}（${_selectedCoordinate!.screenWidth}×${_selectedCoordinate!.screenHeight}）'),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: _taskActive ? null : _pickCoordinate, icon: const Icon(Icons.my_location), label: const Text('屏幕点选坐标')),
            OutlinedButton.icon(onPressed: _taskActive || _selectedCoordinate == null ? null : _saveCurrentCoordinate, icon: const Icon(Icons.save_outlined), label: const Text('保存坐标')),
          ]),
        ]))),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('点击时间', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('时间基准：${_taskActive ? _taskSourceLabel : widget.sourceLabel}（创建任务前重新校时）'),
          ListTile(contentPadding: EdgeInsets.zero, title: const Text('日期'), subtitle: Text('${_targetDate.year}-${_targetDate.month.toString().padLeft(2, '0')}-${_targetDate.day.toString().padLeft(2, '0')}'), trailing: const Icon(Icons.calendar_month), onTap: _taskActive ? null : () async {
            final picked = await showDatePicker(context: context, initialDate: _targetDate, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 365 * 3)));
            if (picked != null) setState(() => _targetDate = picked);
          }),
          ListTile(contentPadding: EdgeInsets.zero, title: const Text('时分'), subtitle: Text(_targetTime.format(context)), trailing: const Icon(Icons.schedule), onTap: _taskActive ? null : () async {
            final picked = await showTimePicker(context: context, initialTime: _targetTime);
            if (picked != null) setState(() => _targetTime = picked);
          }),
          Row(children: [
            Expanded(child: TextField(controller: _secondController, enabled: !_taskActive, keyboardType: TextInputType.number, maxLength: 2, decoration: const InputDecoration(labelText: '秒（00–59）', counterText: '', hintText: '00'), onChanged: (_) => setState(() {}))),
            const SizedBox(width: 16),
            Expanded(child: TextField(controller: _millisecondController, enabled: !_taskActive, keyboardType: TextInputType.number, maxLength: 3, decoration: const InputDecoration(labelText: '毫秒（000–999）', counterText: '', hintText: '985'), onChanged: (_) => setState(() {}))),
          ]),
          const SizedBox(height: 8),
          Text('目标时间：${_formatDateTime(target)}', style: const TextStyle(fontWeight: FontWeight.w600)),
        ]))),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('权限与任务状态', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _PermissionRow(label: '悬浮窗权限（屏幕点选）', enabled: _overlayAllowed, actionLabel: '去授权', onTap: () async { await _channel.invokeMethod('requestPermission'); }),
          _PermissionRow(
            label: '无障碍点击服务',
            enabled: _accessibilityEnabled,
            supported: _gestureApiSupported,
            actionLabel: '去开启',
            onTap: () async {
              if (_gestureApiSupported) {
                await _channel.invokeMethod('openAccessibilitySettings');
              }
            },
          ),
          if (!_gestureApiSupported)
            const Padding(
              padding: EdgeInsets.only(left: 32, top: 4),
              child: Text('无障碍手势派发需要 Android 7.0 或更高版本。'),
            ),
          _PermissionRow(label: '精确闹钟权限', enabled: _exactAlarmAllowed, actionLabel: '去授权', onTap: () async { await _channel.invokeMethod('requestExactAlarmPermission'); }),
          const Divider(),
          Text('状态：$_taskStatus'),
          if (_taskActive) const Text('任务已创建，坐标和目标时间已固定；如需修改，请先停止当前任务。'),
          if (_taskActive) ...[
            Text('目标：$_taskTargetLabel'),
            Text(remaining >= 0 ? '剩余约 ${remaining ~/ 3600000}小时 ${(remaining % 3600000) ~/ 60000}分 ${(remaining % 60000) ~/ 1000}.${(remaining % 1000).toString().padLeft(3, '0')}秒' : '等待系统触发'),
          ],
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: _busy ? null : _toggleTask,
            icon: Icon(_taskActive ? Icons.stop : Icons.play_arrow),
            label: Text(_busy ? '处理中…' : (_taskActive ? '停止任务' : '开始任务')),
          )),
          const SizedBox(height: 8),
          Text('兼容性：无障碍手势派发需要 Android 7.0（API 24）及以上；Android 6.x 及更低版本不具备此系统接口。', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text('说明：Android 系统闹钟、设备负载和无障碍手势派发均可能产生延迟。应用会记录手势派发时刻相对目标时刻的偏差，不承诺硬件级零误差。', style: Theme.of(context).textTheme.bodySmall),
        ]))),
      ])),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.label,
    required this.enabled,
    required this.actionLabel,
    required this.onTap,
    this.supported = true,
  });

  final String label;
  final bool enabled;
  final String actionLabel;
  final VoidCallback onTap;
  final bool supported;

  @override
  Widget build(BuildContext context) {
    final status = !supported ? '系统不支持' : enabled ? '已授权' : '未授权';
    final color = !supported
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : enabled
            ? Colors.green
            : Colors.orange;
    return Row(children: [
      Icon(
        !supported
            ? Icons.info_outline
            : enabled
                ? Icons.check_circle
                : Icons.warning_amber_rounded,
        color: color,
      ),
      const SizedBox(width: 8),
      Expanded(child: Text('$label：$status')),
      if (supported && !enabled)
        TextButton(onPressed: onTap, child: Text(actionLabel)),
    ]);
  }
}
