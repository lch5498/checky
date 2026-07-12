import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show ReorderCallback, ReorderableDragStartListener, ReorderableListView;
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../design_system/app_colors.dart';
import '../../shared/refreshable_scroll_view.dart';
import 'scrap_read_state.dart';

class ScrapScreen extends StatefulWidget {
  const ScrapScreen({
    super.key,
    required this.family,
    required this.families,
    required this.sessionToken,
    required this.onSelectFamily,
  });

  final AppFamily family;
  final List<AppFamily> families;
  final String sessionToken;
  final Future<void> Function(AppFamily family) onSelectFamily;

  @override
  State<ScrapScreen> createState() => _ScrapScreenState();
}

class _ScrapScreenState extends State<ScrapScreen> {
  final _apiClient = ApiClient();

  late AppFamily _family;
  ScrapDashboard? _dashboard;
  String? _message;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _family = widget.family;
    _loadScraps();
  }

  @override
  void didUpdateWidget(covariant ScrapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.family.id != widget.family.id) {
      _family = widget.family;
      _dashboard = null;
      _loadScraps();
    }
  }

  Future<void> _loadScraps() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final dashboard = await _apiClient.getScrapDashboard(
        widget.sessionToken,
        familyId: _family.id,
      );
      final channels = await Future.wait(
        dashboard.channels.map((channel) async {
          final latestPostCreatedAt = channel.latestPostCreatedAt;

          if (!channel.hasRecentPosts || latestPostCreatedAt == null) {
            return channel.copyWith(hasRecentPosts: false);
          }

          final readAt = await ScrapReadState.readAt(
            familyId: _family.id,
            channelId: channel.id,
          );

          return channel.copyWith(
            hasRecentPosts:
                readAt == null || latestPostCreatedAt.isAfter(readAt),
          );
        }),
      );

      if (mounted) {
        setState(() {
          _dashboard = ScrapDashboard(channels: channels);
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _switchFamily() async {
    final selected = await showCupertinoModalPopup<AppFamily>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('스크랩을 볼 그룹을 선택해 주세요'),
        actions: widget.families
            .map(
              (family) => CupertinoActionSheetAction(
                onPressed: () => Navigator.of(context).pop(family),
                child: Text(family.name),
              ),
            )
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
      ),
    );

    if (selected == null) {
      return;
    }

    setState(() {
      _family = selected;
    });
    await widget.onSelectFamily(selected);
  }

  Future<void> _createChannel() async {
    final name = await _showTextSheet(
      context,
      title: '새 채널 만들기',
      placeholder: '예: 주말 맛집, 가고 싶은 곳',
      actionLabel: '만들기',
      maxLines: 1,
      heightFactor: 0.46,
      minHeightFactor: 0.34,
    );

    if (name == null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final channel = await _apiClient.createScrapChannel(
        widget.sessionToken,
        familyId: _family.id,
        name: name,
      );
      await _loadScraps();

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        CupertinoPageRoute(
          builder: (_) => ScrapChannelScreen(
            family: _family,
            sessionToken: widget.sessionToken,
            channel: channel,
          ),
        ),
      );
      await _loadScraps();
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _openChannel(ScrapChannel channel) {
    Navigator.of(context)
        .push(
          CupertinoPageRoute(
            builder: (_) => ScrapChannelScreen(
              family: _family,
              sessionToken: widget.sessionToken,
              channel: channel,
            ),
          ),
        )
        .then((_) => _loadScraps());
  }

  Future<void> _reorderChannels(int oldIndex, int newIndex) async {
    final dashboard = _dashboard;

    if (dashboard == null) {
      return;
    }

    final channels = [...dashboard.channels];
    final movedChannel = channels.removeAt(oldIndex);
    channels.insert(newIndex, movedChannel);

    setState(() {
      _dashboard = ScrapDashboard(channels: channels);
      _message = null;
    });

    try {
      final updatedDashboard = await _apiClient.reorderScrapChannels(
        widget.sessionToken,
        familyId: _family.id,
        channelIds: channels.map((channel) => channel.id).toList(),
      );

      if (mounted) {
        setState(() {
          _dashboard = updatedDashboard;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _dashboard = dashboard;
          _message = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = _dashboard;

    return CupertinoPageScaffold(
      backgroundColor: AppColors.darkBackground,
      navigationBar: CupertinoNavigationBar(
        middle: _FeatureFamilyTitle(
          family: _family,
          featureName: '스크랩',
          canSwitch: widget.families.length > 1,
          onPressed: _switchFamily,
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(32, 32),
          onPressed: _isLoading ? null : _createChannel,
          child: const Icon(CupertinoIcons.plus),
        ),
      ),
      child: SafeArea(
        child: RefreshableScrollView(
          onRefresh: _loadScraps,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            if (_message != null) ...[
              _InlineMessage(message: _message!),
              const SizedBox(height: 16),
            ],
            if (_isLoading && dashboard == null)
              const Padding(
                padding: EdgeInsets.only(top: 72),
                child: Center(child: CupertinoActivityIndicator()),
              )
            else if (dashboard == null)
              _EmptyState(
                icon: CupertinoIcons.exclamationmark_circle,
                title: '스크랩을 불러오지 못했습니다.',
                subtitle: '잠시 후 다시 시도해 주세요.',
                actionLabel: '다시 불러오기',
                onPressed: _loadScraps,
              )
            else if (dashboard.channels.isEmpty)
              _EmptyState(
                icon: CupertinoIcons.bookmark,
                title: '함께 보고 싶은 링크를 모아두세요.',
                subtitle: '맛집, 장소, 읽을거리처럼 나중에 다시 볼 내용을 채널별로 정리할 수 있어요.',
                actionLabel: '새 채널 만들기',
                onPressed: _createChannel,
              )
            else
              _ChannelReorderList(
                channels: dashboard.channels,
                onOpen: _openChannel,
                onReorder: _reorderChannels,
              ),
          ],
        ),
      ),
    );
  }
}

class ScrapChannelScreen extends StatefulWidget {
  const ScrapChannelScreen({
    super.key,
    required this.family,
    required this.sessionToken,
    required this.channel,
    this.initialPostId,
  });

  final AppFamily family;
  final String sessionToken;
  final ScrapChannel channel;
  final String? initialPostId;

  @override
  State<ScrapChannelScreen> createState() => _ScrapChannelScreenState();
}

class _ScrapChannelScreenState extends State<ScrapChannelScreen> {
  final _apiClient = ApiClient();

  ScrapChannelDetail? _detail;
  String? _message;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_markReadAndLoadChannel());
  }

  Future<void> _markReadAndLoadChannel() async {
    await ScrapReadState.markRead(
      familyId: widget.family.id,
      channelId: widget.channel.id,
    );
    await _loadChannel();
  }

  Future<void> _loadChannel() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final detail = await _apiClient.getScrapChannel(
        widget.sessionToken,
        familyId: widget.family.id,
        channelId: widget.channel.id,
      );

      if (mounted) {
        setState(() {
          _detail = detail;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _createPost() async {
    final content = await _showPostComposerSheet(
      context,
      apiClient: _apiClient,
      sessionToken: widget.sessionToken,
      familyId: widget.family.id,
      title: '글 등록',
      placeholder: '링크나 메모를 남겨 주세요',
      actionLabel: '등록',
    );

    if (content == null) {
      return;
    }

    await _runTask(() async {
      await _apiClient.createScrapPost(
        widget.sessionToken,
        familyId: widget.family.id,
        channelId: widget.channel.id,
        content: content,
      );
      await _loadChannel();
    });
  }

  Future<void> _createComment(ScrapPost post) async {
    final content = await _showTextSheet(
      context,
      title: '댓글',
      placeholder: '댓글을 입력해 주세요',
      actionLabel: '등록',
      maxLines: 4,
      heightFactor: 0.5,
      minHeightFactor: 0.38,
    );

    if (content == null) {
      return;
    }

    await _runTask(() async {
      await _apiClient.createScrapComment(
        widget.sessionToken,
        familyId: widget.family.id,
        channelId: widget.channel.id,
        postId: post.id,
        content: content,
      );
      await _loadChannel();
    });
  }

  Future<void> _renameChannel() async {
    final channel = _detail?.channel ?? widget.channel;
    final name = await _showTextSheet(
      context,
      title: '채널명 수정',
      placeholder: '채널명을 입력해 주세요',
      actionLabel: '저장',
      maxLines: 1,
      initialValue: channel.name,
      heightFactor: 0.46,
      minHeightFactor: 0.34,
    );

    if (name == null) {
      return;
    }

    await _runTask(() async {
      await _apiClient.updateScrapChannel(
        widget.sessionToken,
        familyId: widget.family.id,
        channelId: widget.channel.id,
        name: name,
      );
      await _loadChannel();
    });
  }

  Future<void> _deleteChannel() async {
    final confirmed = await _confirmDelete(
      '채널을 삭제할까요?',
      '채널 안의 글과 댓글이 모두 삭제됩니다.',
    );

    if (!confirmed) {
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      await _apiClient.deleteScrapChannel(
        widget.sessionToken,
        familyId: widget.family.id,
        channelId: widget.channel.id,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showChannelActions() async {
    final channel = _detail?.channel ?? widget.channel;
    final action = await showCupertinoModalPopup<_ScrapChannelAction>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: Text(channel.name),
        actions: [
          if (channel.canEdit)
            CupertinoActionSheetAction(
              onPressed: () =>
                  Navigator.of(popupContext).pop(_ScrapChannelAction.rename),
              child: const Text('채널명 수정'),
            ),
          if (channel.canDelete)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () =>
                  Navigator.of(popupContext).pop(_ScrapChannelAction.delete),
              child: const Text('채널 삭제'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popupContext).pop(),
          child: const Text('취소'),
        ),
      ),
    );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _ScrapChannelAction.rename:
        await _renameChannel();
      case _ScrapChannelAction.delete:
        await _deleteChannel();
    }
  }

  Future<void> _editPost(ScrapPost post) async {
    final content = await _showPostComposerSheet(
      context,
      apiClient: _apiClient,
      sessionToken: widget.sessionToken,
      familyId: widget.family.id,
      title: '글 수정',
      placeholder: '링크나 메모를 남겨 주세요',
      actionLabel: '저장',
      initialContent: post.content,
    );

    if (content == null) {
      return;
    }

    await _runTask(() async {
      await _apiClient.updateScrapPost(
        widget.sessionToken,
        familyId: widget.family.id,
        channelId: widget.channel.id,
        postId: post.id,
        content: content,
      );
      await _loadChannel();
    });
  }

  Future<void> _deletePost(ScrapPost post) async {
    final confirmed = await _confirmDelete('글을 삭제할까요?', '댓글도 함께 삭제됩니다.');

    if (!confirmed) {
      return;
    }

    await _runTask(() async {
      await _apiClient.deleteScrapPost(
        widget.sessionToken,
        familyId: widget.family.id,
        channelId: widget.channel.id,
        postId: post.id,
      );
      await _loadChannel();
    });
  }

  Future<void> _deleteComment(ScrapPost post, ScrapComment comment) async {
    final confirmed = await _confirmDelete('댓글을 삭제할까요?', '삭제한 댓글은 복구할 수 없습니다.');

    if (!confirmed) {
      return;
    }

    await _runTask(() async {
      await _apiClient.deleteScrapComment(
        widget.sessionToken,
        familyId: widget.family.id,
        channelId: widget.channel.id,
        postId: post.id,
        commentId: comment.id,
      );
      await _loadChannel();
    });
  }

  Future<void> _togglePostLike(ScrapPost post) async {
    final previousDetail = _detail;
    final optimisticLikeState = !post.isLikedByMe;
    final optimisticLikeCount = post.likeCount + (optimisticLikeState ? 1 : -1);

    _updatePostLike(
      post.id,
      likeCount: optimisticLikeCount < 0 ? 0 : optimisticLikeCount,
      isLikedByMe: optimisticLikeState,
    );

    try {
      final result = await _apiClient.toggleScrapPostLike(
        widget.sessionToken,
        familyId: widget.family.id,
        channelId: widget.channel.id,
        postId: post.id,
      );
      _updatePostLike(
        post.id,
        likeCount: result.likeCount,
        isLikedByMe: result.isLikedByMe,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _detail = previousDetail;
          _message = error.toString();
        });
      }
    }
  }

  Future<void> _toggleCommentLike(ScrapPost post, ScrapComment comment) async {
    final previousDetail = _detail;
    final optimisticLikeState = !comment.isLikedByMe;
    final optimisticLikeCount =
        comment.likeCount + (optimisticLikeState ? 1 : -1);

    _updateCommentLike(
      post.id,
      comment.id,
      likeCount: optimisticLikeCount < 0 ? 0 : optimisticLikeCount,
      isLikedByMe: optimisticLikeState,
    );

    try {
      final result = await _apiClient.toggleScrapCommentLike(
        widget.sessionToken,
        familyId: widget.family.id,
        channelId: widget.channel.id,
        postId: post.id,
        commentId: comment.id,
      );
      _updateCommentLike(
        post.id,
        comment.id,
        likeCount: result.likeCount,
        isLikedByMe: result.isLikedByMe,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _detail = previousDetail;
          _message = error.toString();
        });
      }
    }
  }

  void _updatePostLike(
    String postId, {
    required int likeCount,
    required bool isLikedByMe,
  }) {
    final detail = _detail;

    if (detail == null || !mounted) {
      return;
    }

    setState(() {
      _message = null;
      _detail = ScrapChannelDetail(
        channel: detail.channel,
        posts: detail.posts
            .map(
              (post) => post.id == postId
                  ? post.copyWith(
                      likeCount: likeCount,
                      isLikedByMe: isLikedByMe,
                    )
                  : post,
            )
            .toList(),
      );
    });
  }

  void _updateCommentLike(
    String postId,
    String commentId, {
    required int likeCount,
    required bool isLikedByMe,
  }) {
    final detail = _detail;

    if (detail == null || !mounted) {
      return;
    }

    setState(() {
      _message = null;
      _detail = ScrapChannelDetail(
        channel: detail.channel,
        posts: detail.posts
            .map(
              (post) => post.id == postId
                  ? post.copyWith(
                      comments: post.comments
                          .map(
                            (comment) => comment.id == commentId
                                ? comment.copyWith(
                                    likeCount: likeCount,
                                    isLikedByMe: isLikedByMe,
                                  )
                                : comment,
                          )
                          .toList(),
                    )
                  : post,
            )
            .toList(),
      );
    });
  }

  Future<void> _editComment(ScrapPost post, ScrapComment comment) async {
    final content = await _showTextSheet(
      context,
      title: '댓글 수정',
      placeholder: '댓글을 입력해 주세요',
      actionLabel: '저장',
      maxLines: 4,
      initialValue: comment.content,
      heightFactor: 0.5,
      minHeightFactor: 0.38,
    );

    if (content == null) {
      return;
    }

    await _runTask(() async {
      await _apiClient.updateScrapComment(
        widget.sessionToken,
        familyId: widget.family.id,
        channelId: widget.channel.id,
        postId: post.id,
        commentId: comment.id,
        content: content,
      );
      await _loadChannel();
    });
  }

  Future<bool> _confirmDelete(String title, String content) async {
    final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(content),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    return result == true;
  }

  Future<void> _runTask(Future<void> Function() task) async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      await task();
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final channel = detail?.channel ?? widget.channel;
    final canManageChannel = channel.canEdit || channel.canDelete;

    return CupertinoPageScaffold(
      backgroundColor: AppColors.darkBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          channel.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            inherit: false,
            color: AppColors.darkTextPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(32, 32),
              onPressed: _isLoading ? null : _createPost,
              child: const Icon(CupertinoIcons.plus),
            ),
            if (canManageChannel)
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(32, 32),
                onPressed: _isLoading ? null : _showChannelActions,
                child: const Icon(CupertinoIcons.ellipsis),
              ),
          ],
        ),
      ),
      child: SafeArea(
        child: RefreshableScrollView(
          onRefresh: _loadChannel,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            if (_message != null) ...[
              _InlineMessage(message: _message!),
              const SizedBox(height: 16),
            ],
            if (_isLoading && detail == null)
              const Padding(
                padding: EdgeInsets.only(top: 72),
                child: Center(child: CupertinoActivityIndicator()),
              )
            else if (detail == null)
              _EmptyState(
                icon: CupertinoIcons.exclamationmark_circle,
                title: '채널을 불러오지 못했습니다.',
                subtitle: '잠시 후 다시 시도해 주세요.',
                actionLabel: '다시 불러오기',
                onPressed: _loadChannel,
              )
            else if (detail.posts.isEmpty)
              _EmptyState(
                icon: CupertinoIcons.doc_text,
                title: '아직 등록된 글이 없습니다.',
                subtitle: '+ 버튼으로 링크나 메모를 남겨 보세요.',
                actionLabel: '글 등록',
                onPressed: _createPost,
              )
            else if (widget.initialPostId != null &&
                !detail.posts.any((post) => post.id == widget.initialPostId))
              const _InlineMessage(message: '요청한 글을 찾을 수 없습니다.')
            else
              for (final post in detail.posts.where(
                (post) =>
                    widget.initialPostId == null ||
                    post.id == widget.initialPostId,
              ))
                _PostThread(
                  post: post,
                  onComment: () => _createComment(post),
                  onEditPost: post.canEdit ? () => _editPost(post) : null,
                  onDeletePost: post.canDelete ? () => _deletePost(post) : null,
                  onLikePost: () => _togglePostLike(post),
                  onEditComment: (comment) => _editComment(post, comment),
                  onLikeComment: (comment) => _toggleCommentLike(post, comment),
                  onDeleteComment: (comment) => _deleteComment(post, comment),
                ),
          ],
        ),
      ),
    );
  }
}

enum _ScrapChannelAction { rename, delete }

class _FeatureFamilyTitle extends StatelessWidget {
  const _FeatureFamilyTitle({
    required this.family,
    required this.featureName,
    required this.canSwitch,
    required this.onPressed,
  });

  final AppFamily family;
  final String featureName;
  final bool canSwitch;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final title = '${family.name} $featureName';

    if (!canSwitch) {
      return Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          inherit: false,
          color: AppColors.darkTextPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      );
    }

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 32),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                inherit: false,
                color: AppColors.darkTextPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(CupertinoIcons.chevron_down, size: 15),
        ],
      ),
    );
  }
}

class _ChannelReorderList extends StatelessWidget {
  const _ChannelReorderList({
    required this.channels,
    required this.onOpen,
    required this.onReorder,
  });

  final List<ScrapChannel> channels;
  final void Function(ScrapChannel channel) onOpen;
  final ReorderCallback onReorder;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: channels.length,
      onReorderItem: onReorder,
      itemBuilder: (context, index) {
        final channel = channels[index];

        return _ChannelRow(
          key: ValueKey(channel.id),
          channel: channel,
          dragIndex: index,
          onPressed: () => onOpen(channel),
        );
      },
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    super.key,
    required this.channel,
    required this.dragIndex,
    required this.onPressed,
  });

  final ScrapChannel channel;
  final int dragIndex;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: AppColors.darkBorder.withValues(alpha: 0.8),
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.darkPrimarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                CupertinoIcons.bookmark_fill,
                size: 19,
                color: AppColors.darkPrimary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.darkTextPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      if (channel.hasRecentPosts) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 18,
                          height: 18,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.darkDanger,
                            shape: BoxShape.circle,
                          ),
                          child: const Text(
                            'N',
                            style: TextStyle(
                              color: CupertinoColors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${channel.authorNickname} · ${_formatDateTime(channel.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.darkTextMuted,
                      fontSize: 12,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_forward,
              color: AppColors.darkTextMuted,
              size: 18,
            ),
            const SizedBox(width: 8),
            ReorderableDragStartListener(
              index: dragIndex,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Icon(
                  CupertinoIcons.line_horizontal_3,
                  color: AppColors.darkTextMuted,
                  size: 19,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostThread extends StatelessWidget {
  const _PostThread({
    required this.post,
    required this.onComment,
    required this.onEditPost,
    required this.onDeletePost,
    required this.onLikePost,
    required this.onEditComment,
    required this.onLikeComment,
    required this.onDeleteComment,
  });

  final ScrapPost post;
  final VoidCallback onComment;
  final VoidCallback? onEditPost;
  final VoidCallback? onDeletePost;
  final VoidCallback onLikePost;
  final void Function(ScrapComment comment) onEditComment;
  final void Function(ScrapComment comment) onLikeComment;
  final void Function(ScrapComment comment) onDeleteComment;

  @override
  Widget build(BuildContext context) {
    final postContent = post.linkPreview == null
        ? post.content
        : _contentWithoutFirstLink(post.content);

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.darkBorder.withValues(alpha: 0.8),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MessageBlock(
            authorNickname: post.authorNickname,
            createdAt: post.createdAt,
            content: postContent,
            onEdit: onEditPost,
            onDelete: onDeletePost,
          ),
          if (post.linkPreview != null) ...[
            const SizedBox(height: 12),
            _LinkPreviewCard(preview: post.linkPreview!),
          ],
          const SizedBox(height: 10),
          _PostActionsRow(
            likeCount: post.likeCount,
            isLikedByMe: post.isLikedByMe,
            onLike: onLikePost,
            onComment: onComment,
          ),
          if (post.comments.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final comment in post.comments)
              Padding(
                padding: const EdgeInsets.only(left: 14, top: 12),
                child: _MessageBlock(
                  authorNickname: comment.authorNickname,
                  createdAt: comment.createdAt,
                  content: comment.content,
                  onEdit: comment.canEdit ? () => onEditComment(comment) : null,
                  onDelete: comment.canDelete
                      ? () => onDeleteComment(comment)
                      : null,
                  bottom: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _LikeButton(
                      likeCount: comment.likeCount,
                      isLikedByMe: comment.isLikedByMe,
                      onPressed: () => onLikeComment(comment),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _MessageBlock extends StatelessWidget {
  const _MessageBlock({
    required this.authorNickname,
    required this.createdAt,
    required this.content,
    this.bottom,
    this.onEdit,
    this.onDelete,
  });

  final String authorNickname;
  final DateTime createdAt;
  final String content;
  final Widget? bottom;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: authorNickname,
                      style: TextStyle(
                        color: AppColors.darkTextPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    TextSpan(
                      text: '  ${_formatDateTime(createdAt)}',
                      style: TextStyle(
                        color: AppColors.darkTextMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 13, letterSpacing: 0),
              ),
            ),
            if (onEdit != null || onDelete != null) ...[
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onEdit != null)
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(32, 24),
                      onPressed: onEdit,
                      child: Text(
                        '수정',
                        style: TextStyle(
                          color: AppColors.darkPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  if (onDelete != null)
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(32, 24),
                      onPressed: onDelete,
                      child: Text(
                        '삭제',
                        style: TextStyle(
                          color: AppColors.darkDanger,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
        if (content.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            content,
            style: TextStyle(
              color: AppColors.darkTextPrimary,
              fontSize: 15,
              height: 1.45,
              letterSpacing: 0,
            ),
          ),
        ],
        ?bottom,
      ],
    );
  }
}

class _PostActionsRow extends StatelessWidget {
  const _PostActionsRow({
    required this.likeCount,
    required this.isLikedByMe,
    required this.onLike,
    required this.onComment,
  });

  final int likeCount;
  final bool isLikedByMe;
  final VoidCallback onLike;
  final VoidCallback onComment;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _LikeButton(
          likeCount: likeCount,
          isLikedByMe: isLikedByMe,
          onPressed: onLike,
        ),
        const SizedBox(width: 14),
        CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(38, 26),
          onPressed: onComment,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.chat_bubble,
                color: AppColors.darkTextMuted,
                size: 15,
              ),
              const SizedBox(width: 4),
              Text(
                '댓글',
                style: TextStyle(
                  color: AppColors.darkTextMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LikeButton extends StatelessWidget {
  const _LikeButton({
    required this.likeCount,
    required this.isLikedByMe,
    required this.onPressed,
  });

  final int likeCount;
  final bool isLikedByMe;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = isLikedByMe ? AppColors.darkDanger : AppColors.darkTextMuted;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(38, 26),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Icon(
              isLikedByMe ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
              key: ValueKey(isLikedByMe),
              size: 15,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            likeCount > 0 ? '$likeCount' : '좋아요',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkPreviewCard extends StatelessWidget {
  const _LinkPreviewCard({required this.preview, this.compact = false});

  final ScrapLinkPreview preview;
  final bool compact;

  Future<void> _openLink() async {
    final uri = Uri.tryParse(preview.url);

    if (uri == null) {
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final title = preview.title ?? preview.siteName ?? preview.url;
    final siteName = preview.siteName ?? Uri.tryParse(preview.url)?.host;

    if (compact) {
      return CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: _openLink,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.darkSurfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppColors.darkPrimarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: preview.imageUrl == null
                    ? Icon(
                        CupertinoIcons.link,
                        color: AppColors.darkPrimary,
                        size: 22,
                      )
                    : Image.network(
                        preview.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(
                          CupertinoIcons.link,
                          color: AppColors.darkPrimary,
                          size: 22,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (siteName != null) ...[
                      Text(
                        siteName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.darkPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 3),
                    ],
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.darkTextPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: _openLink,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.darkSurfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.darkBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (preview.imageUrl != null)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  preview.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: AppColors.darkPrimarySoft,
                    alignment: Alignment.center,
                    child: Icon(
                      CupertinoIcons.link,
                      color: AppColors.darkPrimary,
                      size: 24,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (siteName != null) ...[
                    Text(
                      siteName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.darkPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 5),
                  ],
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.darkTextPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  if (preview.description != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      preview.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.darkTextSecondary,
                        fontSize: 13,
                        height: 1.35,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.arrow_up_right_square,
                        size: 14,
                        color: AppColors.darkTextMuted,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          preview.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.darkTextMuted,
                            fontSize: 12,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 42),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.darkPrimarySoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: AppColors.darkPrimary, size: 24),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: TextStyle(
              color: AppColors.darkTextPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              color: AppColors.darkTextSecondary,
              fontSize: 14,
              height: 1.45,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton.filled(
              minimumSize: const Size(double.infinity, 48),
              borderRadius: BorderRadius.circular(14),
              onPressed: onPressed,
              child: Text(
                actionLabel,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.darkDanger.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkDanger.withValues(alpha: 0.3)),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: AppColors.darkDanger,
          fontSize: 13,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

Future<String?> _showTextSheet(
  BuildContext context, {
  required String title,
  required String placeholder,
  required String actionLabel,
  required int maxLines,
  String? initialValue,
  double heightFactor = 0.88,
  double minHeightFactor = 0.52,
}) {
  return showCupertinoModalPopup<String>(
    context: context,
    builder: (_) => _BottomSheetFrame(
      heightFactor: heightFactor,
      minHeightFactor: minHeightFactor,
      child: _TextInputSheet(
        title: title,
        placeholder: placeholder,
        actionLabel: actionLabel,
        maxLines: maxLines,
        initialValue: initialValue,
      ),
    ),
  );
}

Future<String?> _showPostComposerSheet(
  BuildContext context, {
  required ApiClient apiClient,
  required String sessionToken,
  required String familyId,
  required String title,
  required String placeholder,
  required String actionLabel,
  String? initialContent,
}) {
  return showCupertinoModalPopup<String>(
    context: context,
    builder: (_) => _BottomSheetFrame(
      child: _PostComposerSheet(
        apiClient: apiClient,
        sessionToken: sessionToken,
        familyId: familyId,
        title: title,
        placeholder: placeholder,
        actionLabel: actionLabel,
        initialContent: initialContent,
      ),
    ),
  );
}

class _BottomSheetFrame extends StatelessWidget {
  const _BottomSheetFrame({
    required this.child,
    this.heightFactor = 0.88,
    this.minHeightFactor = 0.52,
  });

  final Widget child;
  final double heightFactor;
  final double minHeightFactor;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    final sheetHeight = (screenHeight * heightFactor - keyboardHeight).clamp(
      screenHeight * minHeightFactor,
      screenHeight * heightFactor,
    );

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            height: sheetHeight,
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border(top: BorderSide(color: AppColors.darkBorder)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _TextInputSheet extends StatefulWidget {
  const _TextInputSheet({
    required this.title,
    required this.placeholder,
    required this.actionLabel,
    required this.maxLines,
    required this.initialValue,
  });

  final String title;
  final String placeholder;
  final String actionLabel;
  final int maxLines;
  final String? initialValue;

  @override
  State<_TextInputSheet> createState() => _TextInputSheetState();
}

class _TextInputSheetState extends State<_TextInputSheet> {
  late final TextEditingController _controller;
  bool _canSubmit = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue)
      ..addListener(_handleChanged);
    _canSubmit = _controller.text.trim().isNotEmpty;
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleChanged)
      ..dispose();
    super.dispose();
  }

  void _handleChanged() {
    final canSubmit = _controller.text.trim().isNotEmpty;
    if (canSubmit != _canSubmit) {
      setState(() {
        _canSubmit = canSubmit;
      });
    }
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final isCompactInput = widget.maxLines == 1;
    final minLines = isCompactInput
        ? 2
        : widget.maxLines < 5
        ? widget.maxLines
        : 5;
    final maxLines = isCompactInput ? 2 : widget.maxLines;

    return _ComposerScaffold(
      title: widget.title,
      actionLabel: widget.actionLabel,
      canSubmit: _canSubmit,
      onCancel: () => Navigator.of(context).pop(),
      onSubmit: _submit,
      child: CupertinoTextField(
        controller: _controller,
        autofocus: true,
        minLines: minLines,
        maxLines: maxLines,
        placeholder: widget.placeholder,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.darkBorder)),
        ),
        style: TextStyle(
          color: AppColors.darkTextPrimary,
          fontSize: 20,
          height: 1.35,
          letterSpacing: 0,
        ),
        placeholderStyle: TextStyle(
          color: AppColors.darkTextMuted,
          fontSize: 20,
          height: 1.35,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _PostComposerSheet extends StatefulWidget {
  const _PostComposerSheet({
    required this.apiClient,
    required this.sessionToken,
    required this.familyId,
    required this.title,
    required this.placeholder,
    required this.actionLabel,
    required this.initialContent,
  });

  final ApiClient apiClient;
  final String sessionToken;
  final String familyId;
  final String title;
  final String placeholder;
  final String actionLabel;
  final String? initialContent;

  @override
  State<_PostComposerSheet> createState() => _PostComposerSheetState();
}

class _PostComposerSheetState extends State<_PostComposerSheet> {
  late final TextEditingController _controller;
  Timer? _previewDebounce;
  ScrapLinkPreview? _preview;
  String? _previewUrl;
  String? _previewMessage;
  bool _isPreviewLoading = false;
  bool _canSubmit = false;
  int _previewRequestId = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent)
      ..addListener(_handleChanged);
    _canSubmit = _controller.text.trim().isNotEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleChanged());
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _controller
      ..removeListener(_handleChanged)
      ..dispose();
    super.dispose();
  }

  void _handleChanged() {
    final content = _controller.text.trim();
    final canSubmit = content.isNotEmpty;
    final url = _extractFirstUrl(content);

    if (canSubmit != _canSubmit) {
      setState(() {
        _canSubmit = canSubmit;
      });
    }

    if (url == null) {
      _previewDebounce?.cancel();
      if (_preview != null ||
          _previewUrl != null ||
          _previewMessage != null ||
          _isPreviewLoading) {
        setState(() {
          _preview = null;
          _previewUrl = null;
          _previewMessage = null;
          _isPreviewLoading = false;
        });
      }
      return;
    }

    if (url == _previewUrl && (_preview != null || _isPreviewLoading)) {
      return;
    }

    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 650), () {
      _loadPreview(content, url);
    });
  }

  Future<void> _loadPreview(String content, String url) async {
    final requestId = ++_previewRequestId;
    setState(() {
      _previewUrl = url;
      _preview = null;
      _previewMessage = null;
      _isPreviewLoading = true;
    });

    try {
      final preview = await widget.apiClient.previewScrapLink(
        widget.sessionToken,
        familyId: widget.familyId,
        content: content,
      );

      if (!mounted || requestId != _previewRequestId) {
        return;
      }

      setState(() {
        _preview = preview;
        _previewMessage = preview == null ? '링크 미리보기를 찾지 못했습니다.' : null;
      });
    } catch (_) {
      if (!mounted || requestId != _previewRequestId) {
        return;
      }

      setState(() {
        _previewMessage = '링크 미리보기를 불러오지 못했습니다.';
      });
    } finally {
      if (mounted && requestId == _previewRequestId) {
        setState(() {
          _isPreviewLoading = false;
        });
      }
    }
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return _ComposerScaffold(
      title: widget.title,
      actionLabel: widget.actionLabel,
      canSubmit: _canSubmit,
      onCancel: () => Navigator.of(context).pop(),
      onSubmit: _submit,
      child: Expanded(
        child: Column(
          children: [
            Expanded(
              child: CupertinoTextField(
                controller: _controller,
                autofocus: true,
                minLines: null,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                placeholder: widget.placeholder,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppColors.darkBorder),
                  ),
                ),
                style: TextStyle(
                  color: AppColors.darkTextPrimary,
                  fontSize: 18,
                  height: 1.42,
                  letterSpacing: 0,
                ),
                placeholderStyle: TextStyle(
                  color: AppColors.darkTextMuted,
                  fontSize: 18,
                  height: 1.42,
                  letterSpacing: 0,
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (_isPreviewLoading)
              _PreviewLoading(url: _previewUrl)
            else if (_preview != null)
              _LinkPreviewCard(preview: _preview!, compact: true)
            else if (_previewMessage != null)
              _PreviewMessage(message: _previewMessage!),
          ],
        ),
      ),
    );
  }
}

class _ComposerScaffold extends StatelessWidget {
  const _ComposerScaffold({
    required this.title,
    required this.actionLabel,
    required this.canSubmit,
    required this.onCancel,
    required this.onSubmit,
    required this.child,
  });

  final String title;
  final String actionLabel;
  final bool canSubmit;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          Container(
            width: 36,
            height: 5,
            decoration: BoxDecoration(
              color: AppColors.darkTextMuted.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 36),
                onPressed: onCancel,
                child: Text(
                  '취소',
                  style: TextStyle(
                    color: AppColors.darkTextMuted,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.darkTextPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 36),
                onPressed: canSubmit ? onSubmit : null,
                child: Text(
                  actionLabel,
                  style: TextStyle(
                    color: canSubmit
                        ? AppColors.darkPrimary
                        : AppColors.darkTextMuted.withValues(alpha: 0.45),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _PreviewLoading extends StatelessWidget {
  const _PreviewLoading({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkSurfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        children: [
          const CupertinoActivityIndicator(),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              url == null ? '링크 미리보기를 불러오는 중입니다.' : '$url 미리보기 분석 중',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.darkTextSecondary,
                fontSize: 13,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewMessage extends StatelessWidget {
  const _PreviewMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.darkPrimarySoft.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: AppColors.darkTextSecondary,
          fontSize: 13,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

String _formatDateTime(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');

  return '$year.$month.$day $hour:$minute';
}

String _contentWithoutFirstLink(String content) {
  return content
      .replaceFirst(
        RegExp(r"""https?:\/\/[^\s<>"']+""", caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

String? _extractFirstUrl(String content) {
  final match = RegExp(
    r"""https?:\/\/[^\s<>"']+""",
    caseSensitive: false,
  ).firstMatch(content);

  if (match == null) {
    return null;
  }

  return match.group(0)?.replaceFirst(RegExp(r'[)\].,!?]+$'), '');
}
