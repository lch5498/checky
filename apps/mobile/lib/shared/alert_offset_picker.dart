import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../design_system/app_colors.dart';

const int maxAlertOffsetMinutes = 60 * 24 * 365;
const int _customAlertOffsetValue = -1;
const int _noAlertOffsetValue = -2;

String alertOffsetLabel(int? minutes) {
  if (minutes == null) {
    return '알림 없음';
  }

  if (minutes == 0) {
    return '정시';
  }

  if (minutes % (60 * 24) == 0) {
    return '${minutes ~/ (60 * 24)}일 전';
  }

  if (minutes % 60 == 0) {
    return '${minutes ~/ 60}시간 전';
  }

  return '$minutes분 전';
}

Future<int?> pickAlertOffset(
  BuildContext context, {
  required int? currentValue,
}) async {
  final selected = await showCupertinoModalPopup<int>(
    context: context,
    builder: (popupContext) => CupertinoActionSheet(
      title: const Text('알림 설정'),
      message: const Text('일정 시작 전에 받을 알림 시간을 선택해 주세요.'),
      actions: [
        CupertinoActionSheetAction(
          isDefaultAction: currentValue == null,
          onPressed: () => Navigator.of(popupContext).pop(_noAlertOffsetValue),
          child: const Text('알림 없음'),
        ),
        for (final minutes in const [0, 10, 30, 60, 360, 1440])
          CupertinoActionSheetAction(
            isDefaultAction: currentValue == minutes,
            onPressed: () => Navigator.of(popupContext).pop(minutes),
            child: Text(alertOffsetLabel(minutes)),
          ),
        CupertinoActionSheetAction(
          onPressed: () =>
              Navigator.of(popupContext).pop(_customAlertOffsetValue),
          child: const Text('직접 설정'),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.of(popupContext).pop(currentValue),
        child: const Text('취소'),
      ),
    ),
  );

  if (selected == _customAlertOffsetValue) {
    if (!context.mounted) {
      return currentValue;
    }

    final customValue = await showCupertinoModalPopup<int>(
      context: context,
      builder: (popupContext) => _AlertOffsetInputSheet(
        initialValue: currentValue,
        onCancel: () => Navigator.of(popupContext).pop(),
        onDone: (value) => Navigator.of(popupContext).pop(value),
      ),
    );

    return customValue ?? currentValue;
  }

  if (selected == _noAlertOffsetValue) {
    return null;
  }

  return selected ?? currentValue;
}

enum _AlertOffsetUnit { minute, hour, day }

class _AlertOffsetInputSheet extends StatefulWidget {
  const _AlertOffsetInputSheet({
    required this.initialValue,
    required this.onCancel,
    required this.onDone,
  });

  final int? initialValue;
  final VoidCallback onCancel;
  final ValueChanged<int> onDone;

  @override
  State<_AlertOffsetInputSheet> createState() => _AlertOffsetInputSheetState();
}

class _AlertOffsetInputSheetState extends State<_AlertOffsetInputSheet> {
  late final TextEditingController _amountController;
  late _AlertOffsetUnit _unit;
  String? _message;

  @override
  void initState() {
    super.initState();
    final initialValue =
        widget.initialValue == null || widget.initialValue! <= 0
        ? 10
        : widget.initialValue!;
    if (initialValue % (60 * 24) == 0) {
      _unit = _AlertOffsetUnit.day;
      _amountController = TextEditingController(
        text: '${initialValue ~/ (60 * 24)}',
      );
    } else if (initialValue % 60 == 0) {
      _unit = _AlertOffsetUnit.hour;
      _amountController = TextEditingController(text: '${initialValue ~/ 60}');
    } else {
      _unit = _AlertOffsetUnit.minute;
      _amountController = TextEditingController(text: '$initialValue');
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = int.tryParse(_amountController.text.trim());
    if (amount == null || amount < 1) {
      setState(() => _message = '1 이상의 숫자를 입력해 주세요.');
      return;
    }

    final minutes = switch (_unit) {
      _AlertOffsetUnit.minute => amount,
      _AlertOffsetUnit.hour => amount * 60,
      _AlertOffsetUnit.day => amount * 60 * 24,
    };

    if (minutes > maxAlertOffsetMinutes) {
      setState(() => _message = '최대 365일 전까지만 설정할 수 있습니다.');
      return;
    }

    widget.onDone(minutes);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        color: AppColors.darkSurface,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: widget.onCancel,
                      child: const Text('취소'),
                    ),
                    const Spacer(),
                    Text(
                      '직접 설정',
                      style: TextStyle(
                        color: AppColors.darkTextPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const Spacer(),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _submit,
                      child: const Text('완료'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: CupertinoTextField(
                        controller: _amountController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        placeholder: '숫자',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.darkTextPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: CupertinoSlidingSegmentedControl<_AlertOffsetUnit>(
                        groupValue: _unit,
                        children: const {
                          _AlertOffsetUnit.minute: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('분'),
                          ),
                          _AlertOffsetUnit.hour: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('시간'),
                          ),
                          _AlertOffsetUnit.day: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('일'),
                          ),
                        },
                        onValueChanged: (value) {
                          if (value != null) {
                            setState(() => _unit = value);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                if (_message != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _message!,
                    style: TextStyle(
                      color: AppColors.darkDanger,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
