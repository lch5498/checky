import 'package:flutter/cupertino.dart';

import '../design_system/app_colors.dart';

class CupertinoPickerSheet extends StatelessWidget {
  const CupertinoPickerSheet({
    super.key,
    required this.onCancel,
    required this.onDone,
    required this.child,
    this.doneLabel = '선택',
    this.height = 320,
  });

  final VoidCallback onCancel;
  final VoidCallback onDone;
  final Widget child;
  final String doneLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.darkSurface,
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    minimumSize: const Size(44, 48),
                    onPressed: onCancel,
                    child: const Text('취소'),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    minimumSize: const Size(44, 48),
                    onPressed: onDone,
                    child: Text(doneLabel),
                  ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
