import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/home_widget_background_refresh.dart';
import '../../core/widget_refresh_diagnostics.dart';
import '../../design_system/app_colors.dart';

class WidgetSettingsScreen extends StatefulWidget {
  const WidgetSettingsScreen({super.key});

  @override
  State<WidgetSettingsScreen> createState() => _WidgetSettingsScreenState();
}

class _WidgetSettingsScreenState extends State<WidgetSettingsScreen> {
  Map<String, dynamic> _scheduler = {};
  Map<String, Map<String, dynamic>> _records = {};
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final records = await WidgetRefreshDiagnostics.read();
      if (mounted) setState(() => _records = records);
      final scheduler = await HomeWidgetBackgroundRefresh.schedulingStatus();
      if (mounted) {
        setState(() {
          _records = records;
          _scheduler = scheduler;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _message = '이 기기에서 갱신 상태를 확인하지 못했습니다.');
    }
  }

  Future<void> _refreshNow() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await HomeWidgetBackgroundRefresh.initialize();
      await HomeWidgetBackgroundRefresh.refresh(source: 'manual');
      await _load();
      if (mounted) {
        setState(() {
          _message = widgetRefreshStageLabel(
            _records['manual']?['stage'] as String?,
          );
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _time(Object? value) {
    final date = value is String ? DateTime.tryParse(value)?.toLocal() : null;
    if (date == null) return '기록 없음';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.month}/${date.day} ${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, color: AppColors.darkTextSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontSize: 15, color: AppColors.darkTextPrimary),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final periodic = _records['periodic'] ?? {};
    return CupertinoPageScaffold(
      backgroundColor: AppColors.darkBackground,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('위젯 갱신'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _busy ? null : _load,
          child: const Icon(CupertinoIcons.refresh, size: 22),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '자동 갱신은 15분 이후 실행을 요청하며, 실제 시각은 기기에서 결정해요.',
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.darkTextSecondary,
              ),
            ),
            const SizedBox(height: 16),
            CupertinoButton.filled(
              onPressed: _busy ? null : _refreshNow,
              child: _busy
                  ? const CupertinoActivityIndicator()
                  : const Text('지금 갱신'),
            ),
            if (_message != null) _row('갱신 결과', _message!),
            _row('자동 갱신 예약', switch (_scheduler['pending']) {
              true => '예약됨 · 시스템 실행 대기',
              false => '대기 중인 예약 없음',
              _ => '확인하지 못함',
            }),
            if (_scheduler.containsKey('backgroundRefresh'))
              _row('백그라운드 앱 새로 고침', switch (_scheduler['backgroundRefresh']) {
                'available' => '허용됨',
                'denied' => '꺼져 있음 · iPhone 설정에서 켜 주세요',
                'restricted' => '기기 정책으로 제한됨',
                _ => '확인하지 못함',
              }),
            if (_scheduler.containsKey('lowPowerMode'))
              _row(
                '저전력 모드',
                _scheduler['lowPowerMode'] == true
                    ? '켜짐 · 자동 갱신이 제한될 수 있어요'
                    : '꺼짐',
              ),
            if (_scheduler['earliestBeginAt'] != null)
              _row(
                '가장 이른 실행 가능 시각 (보장 아님)',
                _time(_scheduler['earliestBeginAt']),
              ),
            if (_scheduler['scheduleError'] != null)
              _row('예약 오류', '${_scheduler['scheduleError']}'),
            if (_scheduler['nativeStage'] != null)
              _row(
                'iOS 작업 실행',
                '${_time(_scheduler['nativeStartedAt'])}\n${widgetNativeStageLabel(_scheduler['nativeStage'] as String)}',
              ),
            _row('주기 작업 마지막 시작', _time(periodic['startedAt'])),
            _row(
              '주기 작업 상태',
              widgetRefreshStageLabel(periodic['stage'] as String?),
            ),
            _row('주기 작업 마지막 갱신 성공', _time(periodic['successAt'])),
            _row(
              '푸시 갱신',
              '${_time(_records['push']?['at'])}\n${widgetRefreshStageLabel(_records['push']?['stage'] as String?)}',
            ),
            const SizedBox(height: 12),
            Text(
              '지금 갱신은 서버 조회와 위젯 전달을 바로 실행해요. 성공하면 위젯 표시가 갱신되기까지 잠시 걸릴 수 있어요.',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppColors.darkTextSecondary,
              ),
            ),
            CupertinoButton(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(
                    text: const JsonEncoder.withIndent(
                      '  ',
                    ).convert({'scheduler': _scheduler, 'refresh': _records}),
                  ),
                );
                if (mounted) setState(() => _message = '진단 정보를 복사했습니다.');
              },
              child: const Text('진단 정보 복사'),
            ),
          ],
        ),
      ),
    );
  }
}

String widgetRefreshStageLabel(String? stage) => switch (stage) {
  'success' => '갱신 완료 · 위젯 표시 요청 전달됨',
  'started' => '작업 시작 · 서버 조회 전',
  'fetching' => '서버 조회 중',
  'publishing' => '위젯 데이터 전달 중',
  'login_required' || 'api_error_401' => '로그인이 필요해요. 다시 로그인해 주세요.',
  'group_required' => '앱 홈에서 그룹 데이터를 먼저 불러와 주세요.',
  'other_group' => '다른 그룹의 변경이라 건너뛰었어요.',
  'session_changed' => '로그인 또는 그룹이 변경되어 이전 응답을 버렸어요.',
  'publish_failed' => '서버 조회 성공 · 위젯 전달 실패',
  'schedule_failed' => '자동 갱신 예약 실패',
  'refresh_failed' => '갱신 실패 · 네트워크와 앱 상태를 확인해 주세요.',
  null => '아직 실행 기록이 없어요.',
  _ =>
    stage.startsWith('api_error_')
        ? '서버 요청 실패 (${stage.substring(10)})'
        : stage,
};

String widgetNativeStageLabel(String stage) => switch (stage) {
  'started' => 'iOS가 작업을 시작했어요.',
  'dart_ready' => '갱신 엔진 준비 완료 · 데이터 갱신 중',
  'completed' => '작업 종료 · 아래 주기 작업 결과를 확인해 주세요.',
  'callback_missing' => '실행 정보가 없어요. 지금 갱신을 눌러 복구해 주세요.',
  'engine_failed' => '갱신 엔진 실행 실패',
  'expired' => 'iOS가 허용한 실행 시간이 끝났어요.',
  'timeout' => '갱신 엔진이 제한 시간 내 완료되지 않았어요.',
  'refresh_failed' => '작업 실패 · 아래 주기 작업 결과를 확인해 주세요.',
  _ => stage,
};
