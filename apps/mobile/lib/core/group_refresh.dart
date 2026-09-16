import 'dart:async';

import 'package:flutter/widgets.dart';

/// A family-scoped invalidation signal, not a replacement for server data.
class GroupRefresh {
  static final _events = StreamController<String>.broadcast();
  static Stream<String> get events => _events.stream;
  static void notify(String familyId) => _events.add(familyId);
}

/// Refresh read-only views in place, preserving routes, scroll and edit forms.
mixin GroupRefreshListener<T extends StatefulWidget> on State<T> {
  String get refreshFamilyId;
  Future<void> refreshGroupContent();
  StreamSubscription<String>? _groupSubscription;
  bool _refreshingGroup = false;
  bool _pendingGroupRefresh = false;
  int _groupLoadVersion = 0;

  // Also use for manual loads so an older push response cannot overwrite them.
  int beginGroupLoad() => ++_groupLoadVersion;
  bool isCurrentGroupLoad(int version) =>
      mounted && version == _groupLoadVersion;

  @override
  void initState() {
    super.initState();
    _groupSubscription = GroupRefresh.events.listen((familyId) {
      if (mounted && familyId == refreshFamilyId) {
        _pendingGroupRefresh = true;
        unawaited(_drainGroupRefresh());
      }
    });
  }

  Future<void> _drainGroupRefresh() async {
    if (_refreshingGroup) return;
    _refreshingGroup = true;
    try {
      while (mounted && _pendingGroupRefresh) {
        _pendingGroupRefresh = false;
        try {
          await refreshGroupContent();
        } catch (_) {
          // Preserve the current screen on transient network failures.
        }
      }
    } finally {
      _refreshingGroup = false;
    }
  }

  @override
  void dispose() {
    _groupSubscription?.cancel();
    super.dispose();
  }
}
