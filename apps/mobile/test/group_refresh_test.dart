import 'dart:async';

import 'package:favis_mobile/core/group_refresh.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('newer loads invalidate older responses and disposed views', (
    tester,
  ) async {
    final key = GlobalKey<_RefreshViewState>();
    await tester.pumpWidget(
      CupertinoApp(home: _RefreshView(key: key, onRefresh: () async {})),
    );
    final state = key.currentState!;
    final first = state.beginGroupLoad();
    final second = state.beginGroupLoad();
    expect(state.isCurrentGroupLoad(first), isFalse);
    expect(state.isCurrentGroupLoad(second), isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(state.isCurrentGroupLoad(second), isFalse);
  });

  testWidgets('refresh is family scoped and preserves editing state', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      CupertinoApp(
        home: _RefreshView(
          onRefresh: () async {
            calls++;
          },
        ),
      ),
    );
    await tester.enterText(find.byType(CupertinoTextField), '작성 중인 내용');
    GroupRefresh.notify('another-family');
    await tester.pump();
    expect(calls, 0);
    GroupRefresh.notify('family');
    await tester.pump();
    expect(calls, 1);
    expect(find.text('작성 중인 내용'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    GroupRefresh.notify('family');
    await tester.pump();
    expect(calls, 1);
  });

  testWidgets(
    'messages during a fetch trigger one follow-up, not parallel fetches',
    (tester) async {
      final firstFetch = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        CupertinoApp(
          home: _RefreshView(
            onRefresh: () async {
              calls++;
              if (calls == 1) await firstFetch.future;
            },
          ),
        ),
      );
      GroupRefresh.notify('family');
      await tester.pump();
      for (var index = 0; index < 5; index++) {
        GroupRefresh.notify('family');
      }
      await tester.pump();
      expect(calls, 1);
      firstFetch.complete();
      await tester.pump();
      expect(calls, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _RefreshView extends StatefulWidget {
  const _RefreshView({super.key, required this.onRefresh});
  final Future<void> Function() onRefresh;
  @override
  State<_RefreshView> createState() => _RefreshViewState();
}

class _RefreshViewState extends State<_RefreshView>
    with GroupRefreshListener<_RefreshView> {
  final controller = TextEditingController();
  @override
  String get refreshFamilyId => 'family';
  @override
  Future<void> refreshGroupContent() async {
    await widget.onRefresh();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    child: Center(child: CupertinoTextField(controller: controller)),
  );
}
