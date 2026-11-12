import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:floating_clock/pages/about_page.dart';
import 'package:floating_clock/models/time_precision.dart';
import 'package:floating_clock/models/time_source.dart';
import 'package:floating_clock/widgets/clock_time_text.dart';
import 'package:floating_clock/repositories/time_source_repository.dart';
import 'package:floating_clock/services/time_sync_service.dart';

// Preset/source identifiers and defaults
const String _presetNtpAliyun = 'ntp.aliyun.com';
const String _presetNtpTencent = 'ntp.tencent.com';
const String _presetHttpMeituan =
    'https://cube.meituan.com/ipromotion/cube/toc/component/base/getServerCurrentTime';

const Map<String, String> _presetAliases = {
  _presetNtpAliyun: '阿里云',
  _presetNtpTencent: '腾讯',
  _presetHttpMeituan: '美团',
};

const Map<String, String> _meituanDefaultHeaders = {
  'User-Agent':
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Mobile Safari/537.36'
};

class _FractionColorOption {
  final String key;
  final String label;
  final Color color;
  const _FractionColorOption(this.key, this.label, this.color);
}

const List<_FractionColorOption> _fractionColorOptions = [
  _FractionColorOption('deep_red', '暗红', Color(0xFFC62828)),
  _FractionColorOption('amber', '琥珀', Color(0xFFEF6C00)),
  _FractionColorOption('teal', '青绿', Color(0xFF00796B)),
  _FractionColorOption('indigo', '靛蓝', Color(0xFF3949AB)),
  _FractionColorOption('purple', '紫罗兰', Color(0xFF8E24AA)),
];

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.timeSyncService = const TimeSyncService(),
  });

  /// Injectable so widget tests never start real network requests.
  final TimeSyncService timeSyncService;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const _channel = MethodChannel('floating_clock');
  final TimeSourceRepository _settingsRepository = TimeSourceRepository();

  Timer? _uiTimer;
  final ValueNotifier<int> _clockTick = ValueNotifier<int>(0);
  Timer? _syncTimer;
  bool _isSyncing = false;

  final List<TimeSource> _sources = [];
  int _selectedIndex = 0;
  // Tracks preset hosts that the user chose to hide/delete. Preset restore
  // will clear entries from this set.
  Set<String> _hiddenPresets = <String>{};
  bool _overlayRunning = false;
  bool _overlayOperationInProgress = false;
  bool _pipSupported = false;
  bool _isInPiP = false;
  TimePrecision _timePrecision = TimePrecision.centisecond;
  String _fractionColorKey = _fractionColorOptions.first.key;
  // Overlay entry used to show an inline tooltip above other widgets (doesn't
  // change layout height). Only one sync-tooltip is shown at a time.
  OverlayEntry? _syncOverlayEntry;
  int? _syncOverlayIndex;
  // LayerLinks for each list item so the overlay tooltip can follow the
  // item's position during scrolling.
  final Map<int, LayerLink> _layerLinks = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler(_handlePlatformCall);
    _initializePlatformState();
    _sources.add(TimeSource.system());

    // Load persisted NTP servers and hidden preset list; then ensure presets
    // are present unless the user explicitly hid them.
    _loadSavedServers().then((_) {
      if (!mounted) return;
      final presets = <TimeSource>[
        TimeSource.ntp(_presetNtpAliyun,
            alias: _presetAliases[_presetNtpAliyun] ?? ''),
        TimeSource.ntp(_presetNtpTencent,
            alias: _presetAliases[_presetNtpTencent] ?? ''),
        TimeSource.http(_presetHttpMeituan,
            alias: _presetAliases[_presetHttpMeituan] ?? '',
            headers: _meituanDefaultHeaders),
      ];

      for (final preset in presets) {
        if (_hiddenPresets.contains(preset.host)) continue;
        final exists =
            _sources.any((s) => s.host == preset.host && s.type == preset.type);
        if (!exists) {
          setState(() => _sources.add(preset));
        }
      }

      _restartUiTimer();
      _syncAllServers();
      _syncTimer =
          Timer.periodic(const Duration(seconds: 60), (_) => _syncAllServers());
    });
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _syncTimer?.cancel();
    _clockTick.dispose();
    // Ensure any overlay is removed
    _removeSyncOverlay();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshOverlayStatus();
      if (_uiTimer == null) {
        _restartUiTimer();
      }
    } else if (state == AppLifecycleState.paused) {
      // The main page is not visible while paused. Stop the high-frequency
      // Dart timer; the Android overlay service owns its independent clock.
      _uiTimer?.cancel();
      _uiTimer = null;
    }
  }

  void _restartUiTimer() {
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(_uiTickDuration, (_) {
      if (!mounted) return;
      _clockTick.value++;
    });
  }

  void _onPrecisionChanged(TimePrecision precision) {
    if (_timePrecision == precision) return;
    setState(() => _timePrecision = precision);
    _restartUiTimer();
    unawaited(_persistPrecision(precision));
    if (_overlayRunning) {
      _updateOverlayForSelected();
    }
  }

  Future<void> _persistPrecision(TimePrecision precision) async {
    try {
      await _settingsRepository.savePrecision(precision);
    } catch (error, stackTrace) {
      debugPrint('Failed to save time precision: $error\n$stackTrace');
    }
  }

  void _onFractionColorChanged(String key) {
    if (_fractionColorKey == key) return;
    setState(() => _fractionColorKey = key);
    unawaited(_persistFractionColor(key));
    if (_overlayRunning) {
      _updateOverlayForSelected();
    }
  }

  Future<void> _persistFractionColor(String key) async {
    try {
      await _settingsRepository.saveFractionColor(key);
    } catch (error, stackTrace) {
      debugPrint('Failed to save fraction color: $error\n$stackTrace');
    }
  }

  _FractionColorOption get _fractionColorOption =>
      _fractionColorOptions.firstWhere((opt) => opt.key == _fractionColorKey,
          orElse: () => _fractionColorOptions.first);

  Color get _fractionColor => _fractionColorOption.color;

  void _removeSyncOverlay() {
    try {
      _syncOverlayEntry?.remove();
    } catch (_) {}
    _syncOverlayEntry = null;
    _syncOverlayIndex = null;
  }

  void _showSyncOverlay(int index, LayerLink link, [Offset? tapGlobalPos]) {
    // Remove any existing overlay
    _removeSyncOverlay();

    final s = _sources[index];
    final text = _formatLastSync(s.lastSync);

    // Measure text to compute tooltip size
    final tp = TextPainter(
        text: TextSpan(text: text, style: const TextStyle(fontSize: 12)),
        textDirection: Directionality.of(context))
      ..layout(maxWidth: 260 - 16);
    final textWidth = tp.width;
    final textHeight = tp.height;

    const horizontalPadding = 8.0;
    const verticalPadding = 6.0;
    final tooltipWidth = textWidth + horizontalPadding * 2;
    final tooltipHeight = textHeight + verticalPadding * 2;

    final mq = MediaQuery.of(context);
    final screenWidth = mq.size.width;

    // Compute desired left so tooltip is centered on the tap (if provided),
    // and clamp to screen bounds.
    final centerX = tapGlobalPos?.dx ?? (screenWidth / 2);
    double left = centerX - tooltipWidth / 2;
    left = left.clamp(8.0, screenWidth - tooltipWidth - 8.0);
    const topOffset = 8.0;

    // Compute follower offset so the follower's top center will be placed at
    // target bottom center plus this offset; adjust horizontal offset so the
    // tooltip left aligns with `left`.
    final offsetX = left - (centerX - tooltipWidth / 2);

    // Tooltip bounding rect (in global coordinates) for hit-testing. We
    // approximate top by tap Y + topOffset if tap Y is available.
    final top = (tapGlobalPos?.dy ?? 0) + topOffset;
    final tooltipRect = Rect.fromLTWH(left, top, tooltipWidth, tooltipHeight);

    _syncOverlayEntry = OverlayEntry(builder: (ctx) {
      return Positioned.fill(
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (ev) {
            // If pointer is outside the tooltip rect, remove the overlay but
            // do not prevent the event from reaching underlying widgets.
            if (!tooltipRect.contains(ev.position)) {
              _removeSyncOverlay();
              setState(() {});
            }
          },
          child: Stack(children: [
            CompositedTransformFollower(
              link: link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomCenter,
              followerAnchor: Alignment.topCenter,
              offset: Offset(offsetX, topOffset),
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                  onTap: () {},
                  child: Container(
                    constraints:
                        const BoxConstraints(minWidth: 60, maxWidth: 260),
                    padding: const EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: verticalPadding),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: const [
                        BoxShadow(
                            color: Colors.black26,
                            blurRadius: 6,
                            offset: Offset(0, 2)),
                      ],
                    ),
                    child: Text(text,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      );
    });

    Overlay.of(context).insert(_syncOverlayEntry!);
    _syncOverlayIndex = index;
    setState(() {});
  }

  void _toggleSyncOverlay(int index, LayerLink link, [Offset? tapGlobalPos]) {
    if (_syncOverlayIndex == index) {
      _removeSyncOverlay();
      setState(() {});
      return;
    }
    _showSyncOverlay(index, link, tapGlobalPos);
  }

  Future<void> _initializePlatformState() async {
    if (!Platform.isAndroid) return;
    bool overlayRunning = _overlayRunning;
    bool pipSupported = _pipSupported;
    try {
      final running = await _channel.invokeMethod<bool>('isOverlayRunning');
      if (running != null) overlayRunning = running;
    } catch (_) {}
    try {
      final supported = await _channel.invokeMethod<bool>('isPiPSupported');
      if (supported != null) pipSupported = supported;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _overlayRunning = overlayRunning;
      _pipSupported = pipSupported;
    });
  }

  Future<void> _refreshOverlayStatus() async {
    if (!Platform.isAndroid) return;
    try {
      final running = await _channel.invokeMethod<bool>('isOverlayRunning');
      if (!mounted) return;
      if (running != null && running != _overlayRunning) {
        setState(() => _overlayRunning = running);
      }
    } catch (_) {}
  }

  Future<void> _handlePlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'onOverlayStopped':
        if (mounted && _overlayRunning) {
          setState(() => _overlayRunning = false);
        }
        break;
      case 'onPiPChanged':
        bool inPiP = false;
        final args = call.arguments;
        if (args is Map) {
          final value = args['isInPiP'];
          if (value is bool) inPiP = value;
        } else if (args is bool) {
          inPiP = args;
        }
        if (!mounted) return;
        setState(() => _isInPiP = inPiP);
        if (!inPiP) {
          // When leaving PiP, refresh overlay status in case service resumed.
          await _refreshOverlayStatus();
        }
        break;
    }
  }

  Future<void> _toggleOverlay() async {
    if (_overlayOperationInProgress) return;
    setState(() => _overlayOperationInProgress = true);
    final shouldRunAfterOperation = !_overlayRunning;
    try {
      final success = shouldRunAfterOperation
          ? await _startOverlayForSelected()
          : await _stopOverlay();
      if (!mounted) return;
      if (success) {
        setState(() => _overlayRunning = shouldRunAfterOperation);
      }
    } finally {
      if (mounted) {
        setState(() => _overlayOperationInProgress = false);
      }
    }
  }

  Future<void> _enterPictureInPicture() async {
    if (!_pipSupported) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前设备不支持画中画模式')));
      return;
    }
    if (_overlayRunning) {
      final stopped = await _stopOverlay();
      if (!mounted) return;
      if (stopped) {
        setState(() => _overlayRunning = false);
      }
    }
    try {
      final entered = await _channel.invokeMethod<bool>('enterPiP');
      if (entered != null && !entered) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法进入画中画模式，请检查系统设置')));
      }
    } on PlatformException catch (e) {
      debugPrint('enterPiP failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('进入画中画失败')));
    }
  }

  Future<void> _syncAllServers() async {
    // Prevent the initial sync, periodic sync and resume callback from
    // launching overlapping requests against the same time sources.
    if (!mounted || _isSyncing) return;
    _isSyncing = true;
    try {
      for (final source in List<TimeSource>.of(_sources)) {
        if (!mounted) return;
        if (source.isSystem || !_sources.contains(source)) continue;

        int? offset;
        if (source.type == TimeSourceType.ntp) {
          offset = await _queryNtpOffset(source.host);
        } else if (source.type == TimeSourceType.http) {
          offset = await _queryHttpOffset(source);
        }

        if (!mounted) return;
        if (offset != null && _sources.contains(source)) {
          setState(() {
            source.offsetMillis = offset!;
            source.lastSync = DateTime.now();
          });
        } else if (offset == null) {
          debugPrint(
              '${source.type == TimeSourceType.ntp ? 'NTP' : 'HTTP'}: sync failed for ${source.host}');
        }
      }
    } finally {
      _isSyncing = false;
    }
  }

  Future<int?> _queryNtpOffset(String host,
      {int port = 123,
      Duration timeout = const Duration(seconds: 2),
      int attempts = 5}) {
    return widget.timeSyncService.queryNtpOffset(
      host,
      port: port,
      timeout: timeout,
      attempts: attempts,
    );
  }

  Future<int?> _queryHttpOffset(TimeSource source,
      {Duration timeout = const Duration(seconds: 2)}) {
    return widget.timeSyncService.queryHttpOffset(source, timeout: timeout);
  }

  Future<bool> _startOverlayForSelected() async {
    try {
      final bool has =
          await _channel.invokeMethod<bool>('hasPermission') ?? false;
      if (!has) {
        await _channel.invokeMethod('requestPermission');
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('请在系统设置允许“悬浮窗/在其他应用上层显示”权限后再次点击开始'),
        ));
        return false;
      }
      final s = _sources[_selectedIndex];
      final offset = s.isSystem ? 0 : s.offsetMillis;
      final label = s.isSystem ? '' : (s.alias.isNotEmpty ? s.alias : s.host);
      await _channel.invokeMethod('startOverlay', {
        'offset': offset,
        'label': label,
        'precision': _timePrecision.storageValue,
        'fractionColor': _fractionColor.toARGB32(),
      });
      return true;
    } on PlatformException catch (e) {
      debugPrint('PlatformException: $e');
    } catch (e) {
      debugPrint('startOverlay error: $e');
    }
    return false;
  }

  Future<bool> _stopOverlay() async {
    try {
      await _channel.invokeMethod('stopOverlay');
      return true;
    } on PlatformException catch (e) {
      debugPrint('PlatformException: $e');
    } catch (e) {
      debugPrint('stopOverlay error: $e');
    }
    return false;
  }

  // Update running overlay to reflect the currently selected source.
  Future<void> _updateOverlayForSelected() async {
    if (!_overlayRunning) return;
    try {
      final s = _sources[_selectedIndex];
      final offset = s.isSystem ? 0 : s.offsetMillis;
      final label = s.isSystem ? '' : (s.alias.isNotEmpty ? s.alias : s.host);
      await _channel.invokeMethod('startOverlay', {
        'offset': offset,
        'label': label,
        'precision': _timePrecision.storageValue,
        'fractionColor': _fractionColor.toARGB32(),
      });
    } on PlatformException catch (e) {
      debugPrint('PlatformException: $e');
    }
  }

  void _addServerDialog() {
    final controllerHost = TextEditingController(text: 'ntp.aliyun.com');
    final controllerAlias = TextEditingController(text: '');
    showDialog<void>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('添加 NTP 服务器'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: controllerHost,
                  decoration: const InputDecoration(
                      hintText: 'ntp.example.com', labelText: '主机')),
              TextField(
                  controller: controllerAlias,
                  decoration:
                      const InputDecoration(hintText: '可选别名', labelText: '别名')),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('取消')),
              TextButton(
                  onPressed: () async {
                    final host = controllerHost.text.trim();
                    final alias = controllerAlias.text.trim();
                    if (host.isNotEmpty) {
                      // Show a small progress indicator while testing the server.
                      showDialog<void>(
                          context: ctx,
                          barrierDismissible: false,
                          builder: (_) {
                            return AlertDialog(
                                content: Row(children: const [
                              CircularProgressIndicator(),
                              SizedBox(width: 12),
                              Text('正在测试 NTP 服务器...')
                            ]));
                          });

                      // For quick UI tests use a short timeout and few attempts
                      final off = await _queryNtpOffset(host,
                          attempts: 2,
                          timeout: const Duration(milliseconds: 800));

                      // If the state was disposed while awaiting, bail out.
                      if (!mounted) return;

                      // close progress dialog
                      Navigator.of(context, rootNavigator: true).pop();

                      if (off == null) {
                        // Don't add silently if the server failed — inform the user and keep the dialog open.
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('无法从 $host 获取 NTP 时间，请检查主机或网络')));
                        return;
                      }

                      setState(() {
                        _sources.add(TimeSource.ntp(host, alias: alias));
                        _sources.last.offsetMillis = off;
                        _sources.last.lastSync = DateTime.now();
                      });
                      _saveServers();

                      // close the add dialog now that we've confirmed the server works
                      if (!mounted) return;
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('添加')),
            ],
          );
        });
  }

  void _editServerDialog(int index) {
    final s = _sources[index];
    final controllerHost = TextEditingController(text: s.host);
    final controllerAlias = TextEditingController(text: s.alias);
    showDialog<void>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('编辑 NTP 服务器'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: controllerHost,
                  decoration: const InputDecoration(
                      hintText: 'ntp.example.com', labelText: '主机')),
              TextField(
                  controller: controllerAlias,
                  decoration:
                      const InputDecoration(hintText: '可选别名', labelText: '别名')),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('取消')),
              TextButton(
                  onPressed: () async {
                    final host = controllerHost.text.trim();
                    final alias = controllerAlias.text.trim();
                    if (host.isNotEmpty) {
                      // Show progress while testing the edited server
                      showDialog<void>(
                          context: ctx,
                          barrierDismissible: false,
                          builder: (_) {
                            return AlertDialog(
                                content: Row(children: const [
                              CircularProgressIndicator(),
                              SizedBox(width: 12),
                              Text('正在测试 NTP 服务器...')
                            ]));
                          });

                      // For quick UI tests use a short timeout and few attempts
                      final off = await _queryNtpOffset(host,
                          attempts: 2,
                          timeout: const Duration(milliseconds: 800));

                      // If the state was disposed while awaiting, bail out.
                      if (!mounted) return;

                      // close progress dialog
                      Navigator.of(context, rootNavigator: true).pop();

                      if (off == null) {
                        // Keep the edit dialog open and report the failure
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('无法从 $host 获取 NTP 时间，请检查主机或网络')));
                        return;
                      }

                      setState(() {
                        _sources[index] = TimeSource.ntp(host, alias: alias);
                        _sources[index].offsetMillis = off;
                        _sources[index].lastSync = DateTime.now();
                        if (_selectedIndex == index) {
                          _selectedIndex = index; // keep selection
                        }
                      });
                      _saveServers();
                      if (!mounted) return;
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('保存')),
            ],
          );
        });
  }


  String _precisionLabel(TimePrecision precision) {
    switch (precision) {
      case TimePrecision.centisecond:
        return '0.01 秒';
      case TimePrecision.decisecond:
        return '0.1 秒';
    }
  }

  String _formatLastSync(DateTime? dt) {
    if (dt == null) return '';
    final d = dt.toLocal();
    return '最近同步: ${d.year}-${_twoDigits(d.month)}-${_twoDigits(d.day)} ${_twoDigits(d.hour)}:${_twoDigits(d.minute)}:${_twoDigits(d.second)}';
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  String _formatOffset(int ms) {
    if (ms.abs() < 1000) return '${ms >= 0 ? '+' : '-'}${ms.abs()} ms';
    final s = ms / 1000.0;
    return '${ms >= 0 ? '+' : '-'}${s.toStringAsFixed(2)} s';
  }

  Duration get _uiTickDuration => _timePrecision == TimePrecision.centisecond
      ? const Duration(milliseconds: 10)
      : const Duration(milliseconds: 100);

  Widget _buildColoredTimeText(TimeSource s,
      {TextStyle? style, TextAlign? textAlign}) {
    return ClockTimeText(
      tick: _clockTick,
      source: s,
      precision: _timePrecision,
      fractionColor: _fractionColor,
      style: style,
      textAlign: textAlign,
    );
  }

  // Persistence is delegated to TimeSourceRepository so storage migration
  // and malformed-data handling can be tested independently of the UI.
  Future<void> _loadSavedServers() async {
    try {
      final settings = await _settingsRepository.load(
        validFractionColorKeys:
            _fractionColorOptions.map((option) => option.key).toSet(),
      );
      if (!mounted) return;

      setState(() {
        _sources.addAll(settings.sources);
        _timePrecision = settings.precision;
        if (settings.fractionColorKey != null) {
          _fractionColorKey = settings.fractionColorKey!;
        }
        _hiddenPresets = settings.hiddenPresets;
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to load saved clock settings: $error\n$stackTrace');
    }
  }

  Future<void> _saveServers() async {
    try {
      await _settingsRepository.saveSources(_sources);
    } catch (error, stackTrace) {
      debugPrint('Failed to save time sources: $error\n$stackTrace');
    }
  }

  Future<void> _saveHiddenPresets() async {
    try {
      await _settingsRepository.saveHiddenPresets(_hiddenPresets);
    } catch (error, stackTrace) {
      debugPrint('Failed to save hidden presets: $error\n$stackTrace');
    }
  }

  bool _isPresetHost(String host) {
    return host == _presetNtpAliyun ||
        host == _presetNtpTencent ||
        host == _presetHttpMeituan;
  }

  void _restorePresetsDialog() {
    final missing = <String>[];
    if (!_sources.any((s) => s.host == _presetNtpAliyun)) {
      missing.add(_presetNtpAliyun);
    }
    if (!_sources.any((s) => s.host == _presetNtpTencent)) {
      missing.add(_presetNtpTencent);
    }
    if (!_sources.any((s) => s.host == _presetHttpMeituan)) {
      missing.add(_presetHttpMeituan);
    }

    if (missing.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('没有缺失的预设需要恢复')));
      return;
    }

    showDialog<void>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('恢复预设源'),
            content: Text(
                '将恢复以下预设: ${missing.map((h) => _presetAliases[h] ?? h).join(', ')}'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('取消')),
              TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _restorePresets();
                  },
                  child: const Text('恢复')),
            ],
          );
        });
  }

  Future<void> _restorePresets() async {
    final toAdd = <TimeSource>[];
    if (!_sources.any((s) => s.host == _presetNtpAliyun)) {
      toAdd.add(TimeSource.ntp(_presetNtpAliyun,
          alias: _presetAliases[_presetNtpAliyun] ?? ''));
    }
    if (!_sources.any((s) => s.host == _presetNtpTencent)) {
      toAdd.add(TimeSource.ntp(_presetNtpTencent,
          alias: _presetAliases[_presetNtpTencent] ?? ''));
    }
    if (!_sources.any((s) => s.host == _presetHttpMeituan)) {
      toAdd.add(TimeSource.http(_presetHttpMeituan,
          alias: _presetAliases[_presetHttpMeituan] ?? '',
          headers: _meituanDefaultHeaders));
    }

    if (toAdd.isEmpty) return;

    setState(() {
      _sources.addAll(toAdd);
    });

    // Clear these hosts from hidden presets (if user previously hid them)
    for (final s in toAdd) {
      _hiddenPresets.remove(s.host);
    }
    await _saveHiddenPresets();

    // Persist NTP additions and run an immediate sync for added presets.
    await _saveServers();
    for (final s in toAdd) {
      if (s.type == TimeSourceType.ntp) {
        final off = await _queryNtpOffset(s.host);
        if (off != null) {
          setState(() {
            final ts = _sources.firstWhere((x) => x.host == s.host);
            ts.offsetMillis = off;
            ts.lastSync = DateTime.now();
          });
        }
      } else if (s.type == TimeSourceType.http) {
        final off = await _queryHttpOffset(s);
        if (off != null) {
          setState(() {
            final ts = _sources.firstWhere((x) => x.host == s.host);
            ts.offsetMillis = off;
            ts.lastSync = DateTime.now();
          });
        }
      }
    }
  }

  // Simple container for a single NTP measurement sample
  // (declared at top-level below)

  @override
  Widget build(BuildContext context) {
    if (_isInPiP) {
      final TimeSource source;
      if (_sources.isEmpty) {
        source = TimeSource.system();
      } else {
        var idx = _selectedIndex;
        if (idx < 0) idx = 0;
        if (idx >= _sources.length) idx = _sources.length - 1;
        source = _sources[idx];
      }
      final label = source.isSystem
          ? '系统时间'
          : (source.alias.isNotEmpty ? source.alias : source.host);
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (!source.isSystem)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Text(
                        label,
                        style: const TextStyle(
                            color: Colors.black54, fontSize: 14),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  _buildColoredTimeText(
                    source,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 32,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('悬浮时间'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'about') {
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const AboutPage()));
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'about', child: Text('关于')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Expanded(
                child: Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('时间源'),
                        trailing:
                            Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                              icon: const Icon(Icons.add),
                              onPressed: _addServerDialog),
                          IconButton(
                              icon: const Icon(Icons.restore),
                              tooltip: '恢复预设源',
                              onPressed: _restorePresetsDialog),
                        ]),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 4.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Text('显示精度'),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: RadioGroup<TimePrecision>(
                                      groupValue: _timePrecision,
                                      onChanged: (value) {
                                        if (value != null) {
                                          _onPrecisionChanged(value);
                                        }
                                      },
                                      child: Wrap(
                                        alignment: WrapAlignment.end,
                                        spacing: 12,
                                        runSpacing: 4,
                                        children: TimePrecision.values.map((p) {
                                          return InkWell(
                                            borderRadius:
                                                BorderRadius.circular(24),
                                            onTap: () => _onPrecisionChanged(p),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Radio<TimePrecision>(
                                                  value: p,
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  materialTapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                ),
                                                Text(_precisionLabel(p)),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Text('小数颜色'),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: _fractionColorKey,
                                        isDense: true,
                                        alignment: Alignment.centerRight,
                                        items: _fractionColorOptions
                                            .map((option) => DropdownMenuItem(
                                                  value: option.key,
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Container(
                                                        width: 12,
                                                        height: 12,
                                                        margin: const EdgeInsets
                                                            .only(right: 6),
                                                        decoration:
                                                            BoxDecoration(
                                                                color: option
                                                                    .color,
                                                                shape: BoxShape
                                                                    .circle),
                                                      ),
                                                      Text(option.label),
                                                    ],
                                                  ),
                                                ))
                                            .toList(),
                                        onChanged: (value) {
                                          if (value != null) {
                                            _onFractionColorChanged(value);
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: RadioGroup<int>(
                          groupValue: _selectedIndex,
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _selectedIndex = value);
                              if (_overlayRunning) {
                                _updateOverlayForSelected();
                              }
                            }
                          },
                          child: ListView.separated(
                            itemCount: _sources.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final s = _sources[index];
                              // Get text scale factor for responsive adjustments
                              final textScale =
                                  MediaQuery.textScalerOf(context).scale(1.0);
                              // Scale down spacing when text is enlarged
                              final scaleFactor = textScale > 1.2
                                  ? 0.7
                                  : (textScale > 1.0 ? 0.85 : 1.0);
                              final iconSize = 20.0 * scaleFactor;
                              final buttonPadding = 8.0 * scaleFactor;

                              return ListTile(
                                leading: SizedBox(
                                  width: 28.0,
                                  child: Radio<int>(
                                    value: index,
                                  ),
                                ),
                                title: Text(
                                  s.isSystem
                                      ? '系统'
                                      : (s.alias.isNotEmpty ? s.alias : s.host),
                                  style: const TextStyle(
                                    fontFeatures: [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildColoredTimeText(
                                        s,
                                        style: const TextStyle(
                                          fontFeatures: [
                                            FontFeature.tabularFigures()
                                          ],
                                        ),
                                      ),
                                      // 偏移值移到第二行
                                      if (!s.isSystem)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 2.0),
                                          child: Text(
                                            _formatOffset(s.offsetMillis),
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ),
                                    ]),
                                trailing: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // 使用更紧凑的按钮设计
                                          if (s.type == TimeSourceType.ntp)
                                            Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                onTap: () =>
                                                    _editServerDialog(index),
                                                child: Padding(
                                                  padding: EdgeInsets.all(
                                                      buttonPadding),
                                                  child: Icon(Icons.edit,
                                                      size: iconSize),
                                                ),
                                              ),
                                            )
                                          else if (!s.isSystem)
                                            SizedBox(
                                                width: iconSize +
                                                    buttonPadding * 2),
                                          if (!s.isSystem)
                                            Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                onTap: () async {
                                                  final removed =
                                                      _sources[index];
                                                  final removedHost =
                                                      removed.host;
                                                  setState(() {
                                                    if (_selectedIndex ==
                                                        index) {
                                                      _selectedIndex = 0;
                                                    } else if (_selectedIndex >
                                                        index) {
                                                      _selectedIndex -= 1;
                                                    }
                                                    _sources.removeAt(index);
                                                  });
                                                  // If any tooltip overlay was showing, remove it
                                                  // to avoid dangling overlays after list changes.
                                                  if (_syncOverlayIndex !=
                                                      null) {
                                                    _removeSyncOverlay();
                                                  }

                                                  // Persist the updated server list (now includes HTTP/NTP).
                                                  await _saveServers();

                                                  // If the removed host is a preset, mark it hidden
                                                  // so it won't be re-added on next startup.
                                                  if (_isPresetHost(
                                                      removedHost)) {
                                                    _hiddenPresets
                                                        .add(removedHost);
                                                    await _saveHiddenPresets();
                                                  }
                                                },
                                                child: Padding(
                                                  padding: EdgeInsets.all(
                                                      buttonPadding),
                                                  child: Icon(Icons.delete,
                                                      size: iconSize),
                                                ),
                                              ),
                                            ),
                                          // 同步时间图标
                                          if (!s.isSystem && s.lastSync != null)
                                            () {
                                              final link =
                                                  _layerLinks.putIfAbsent(
                                                      index, () => LayerLink());
                                              return CompositedTransformTarget(
                                                link: link,
                                                child: Material(
                                                  color: Colors.transparent,
                                                  child: InkResponse(
                                                    radius: iconSize * 0.9,
                                                    onTapDown: (details) =>
                                                        _toggleSyncOverlay(
                                                            index,
                                                            link,
                                                            details
                                                                .globalPosition),
                                                    child: SizedBox(
                                                      width: iconSize +
                                                          buttonPadding * 2,
                                                      height: iconSize +
                                                          buttonPadding * 2,
                                                      child: Icon(
                                                          Icons.error_outline,
                                                          size: iconSize * 0.9),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }()
                                          else if (!s.isSystem)
                                            SizedBox(
                                                width: iconSize +
                                                    buttonPadding * 2),
                                          // 类型标签
                                          Container(
                                              margin: EdgeInsets.only(
                                                  left: 4.0 * scaleFactor),
                                              padding: EdgeInsets.symmetric(
                                                  horizontal: 4 * scaleFactor,
                                                  vertical: 1 * scaleFactor),
                                              decoration: BoxDecoration(
                                                  color: s.type ==
                                                          TimeSourceType.ntp
                                                      ? Colors.blue.shade50
                                                      : (s.type == TimeSourceType.http
                                                          ? Colors.green.shade50
                                                          : Colors
                                                              .grey.shade200),
                                                  borderRadius:
                                                      BorderRadius.circular(4)),
                                              child: Text(
                                                  s.type == TimeSourceType.ntp
                                                      ? 'ntp'
                                                      : (s.type == TimeSourceType.http
                                                          ? 'http'
                                                          : 'sys'),
                                                  style: TextStyle(
                                                      fontSize:
                                                          9 * scaleFactor))),
                                        ])),
                                onTap: () {
                                  setState(() => _selectedIndex = index);
                                  if (_overlayRunning) {
                                    _updateOverlayForSelected();
                                  }
                                },
                              );
                            },
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            ElevatedButton(
                                onPressed: _overlayOperationInProgress
                                    ? null
                                    : _toggleOverlay,
                                child: Text(_overlayOperationInProgress
                                    ? '处理中…'
                                    : (_overlayRunning ? '停止悬浮' : '开始悬浮'))),
                            ElevatedButton(
                                onPressed: _pipSupported
                                    ? _enterPictureInPicture
                                    : null,
                                child: const Text('画中画')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
