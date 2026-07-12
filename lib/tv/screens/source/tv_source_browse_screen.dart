import '../../../core/widgets/app_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/server_providers.dart';
import '../../../core/sources/media_source_backend.dart';
import '../../../core/sources/source_browse_controller.dart';
import '../../../core/sources/source_playback.dart';
import '../../../ui/widgets/common/media_widgets.dart';
import '../../theme/tv_design_tokens.dart';
import '../../theme/tv_metrics.dart';
import '../../widgets/tv_button.dart';
import '../../widgets/tv_focusable.dart';
import '../../widgets/tv_panel.dart';

/// TV 端网盘/聚合源浏览视图（嵌入 TV 首页，保留侧边栏）。
///
/// 观感对齐移动端 [SourceBrowseScreen]：可聚焦面包屑 + 排序/网格切换/刷新动作 +
/// 列表/封面网格两种视图，D-pad 焦点导航。
class TvSourceBrowseView extends ConsumerStatefulWidget {
  final ServerConfig server;

  const TvSourceBrowseView({super.key, required this.server});

  @override
  ConsumerState<TvSourceBrowseView> createState() =>
      _TvSourceBrowseViewState();
}

class _TvSourceBrowseViewState extends ConsumerState<TvSourceBrowseView> {
  late SourceBrowseController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SourceBrowseController(widget.server);
    _controller.addListener(_onChanged);
    _controller.openRoot();
  }

  @override
  void didUpdateWidget(covariant TvSourceBrowseView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.server.id != widget.server.id) {
      _controller.removeListener(_onChanged);
      _controller = SourceBrowseController(widget.server);
      _controller.addListener(_onChanged);
      _controller.openRoot();
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onSelectEntry(SourceEntry e) {
    if (e.isDir) {
      _controller.enterDir(e);
    } else if (e.isVideo) {
      context.push('/tv/source-player',
          extra: SourcePlayback(server: _controller.server, entry: e));
    }
  }

  void _openSortPanel(TvMetrics m) {
    final current = ref.read(sourceBrowseSortProvider);
    showDialog<void>(
      context: context,
      builder: (ctx) => TvPanel(
        title: '排序方式',
        onClose: () => Navigator.pop(ctx),
        children: [
          for (final mode in SourceSortMode.values)
            TvPanelOption(
              title: mode.label,
              isSelected: mode == current,
              onTap: () {
                ref.read(sourceBrowseSortProvider.notifier).state = mode;
                Navigator.pop(ctx);
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = context.tv;
    final c = _controller;
    return Scaffold(
      backgroundColor: TvDesignTokens.background,
      body: Padding(
        padding: EdgeInsets.fromLTRB(
            m.spacingXxl, m.spacingXl, m.spacingXxl, m.spacingLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(m, c),
            SizedBox(height: m.spacingLg),
            Expanded(child: _buildBody(m, c)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(TvMetrics m, SourceBrowseController c) {
    final grid = ref.watch(sourceBrowseGridProvider);
    return Row(
      children: [
        Icon(Icons.cloud_outlined,
            color: TvDesignTokens.brand, size: m.s(30)),
        SizedBox(width: m.spacingMd),
        Expanded(child: _breadcrumb(m, c)),
        SizedBox(width: m.spacingMd),
        _actionBtn(m, Icons.sort_rounded, () => _openSortPanel(m)),
        SizedBox(width: m.spacingSm),
        _actionBtn(
          m,
          grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
          () => ref.read(sourceBrowseGridProvider.notifier).state = !grid,
        ),
        SizedBox(width: m.spacingSm),
        _actionBtn(m, Icons.refresh_rounded, () => c.refresh()),
        if (c.canGoUp) ...[
          SizedBox(width: m.spacingSm),
          _actionBtn(m, Icons.arrow_upward_rounded, () => c.goUp()),
        ],
      ],
    );
  }

  /// 可聚焦面包屑：每层一枚 chip（末层为当前目录，不可跳转）。
  Widget _breadcrumb(TvMetrics m, SourceBrowseController c) {
    final crumbs = c.breadcrumb;
    return SizedBox(
      height: m.s(52),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: crumbs.length,
        itemBuilder: (context, i) {
          final isLast = i == crumbs.length - 1;
          return Row(
            children: [
              if (i > 0)
                Icon(Icons.chevron_right,
                    size: m.s(24), color: TvDesignTokens.textSecondary),
              if (isLast)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: m.spacingMd),
                  child: Text(
                    crumbs[i].name,
                    style: TextStyle(
                      fontSize: m.fontSizeMd,
                      color: TvDesignTokens.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                TvFocusable(
                  padding: EdgeInsets.all(m.s(4)),
                  onSelect: () => c.goToCrumb(i),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: m.spacingMd, vertical: m.spacingXs),
                    decoration: BoxDecoration(
                      color: TvDesignTokens.surface,
                      borderRadius: BorderRadius.circular(m.posterRadius),
                    ),
                    child: Text(
                      crumbs[i].name,
                      style: TextStyle(
                        fontSize: m.fontSizeSm,
                        color: TvDesignTokens.brand,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _actionBtn(TvMetrics m, IconData icon, VoidCallback onSelect) {
    return TvFocusable(
      padding: EdgeInsets.all(m.s(4)),
      onSelect: onSelect,
      child: Container(
        padding: EdgeInsets.all(m.spacingSm),
        decoration: BoxDecoration(
          color: TvDesignTokens.surface,
          borderRadius: BorderRadius.circular(m.posterRadius),
        ),
        child: Icon(icon, color: TvDesignTokens.textPrimary, size: m.s(26)),
      ),
    );
  }

  Widget _buildBody(TvMetrics m, SourceBrowseController c) {
    if (c.loading && c.entries.isEmpty) {
      return const Center(
          child: AppLoadingIndicator(size: 48, color: TvDesignTokens.brand));
    }
    if (c.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: m.s(48), color: TvDesignTokens.textSecondary),
            SizedBox(height: m.spacingMd),
            Text(c.error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: m.fontSizeMd, color: TvDesignTokens.error)),
            SizedBox(height: m.spacingLg),
            TvButton(
              text: '重试',
              icon: Icons.refresh,
              autofocus: true,
              onPressed: () => c.refresh(),
            ),
          ],
        ),
      );
    }
    if (c.entries.isEmpty) {
      return Center(
        child: Text('此目录为空',
            style: TextStyle(
                fontSize: m.fontSizeMd, color: TvDesignTokens.textSecondary)),
      );
    }
    final entries =
        sortSourceEntries(c.entries, ref.watch(sourceBrowseSortProvider));
    final grid = ref.watch(sourceBrowseGridProvider);
    return grid ? _buildGrid(m, entries) : _buildList(m, entries);
  }

  Widget _buildList(TvMetrics m, List<SourceEntry> entries) {
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        return Padding(
          padding: EdgeInsets.only(bottom: m.spacingMd),
          child: TvFocusable(
            autofocus: i == 0,
            padding: EdgeInsets.all(m.s(4)),
            onSelect: () => _onSelectEntry(e),
            child: _row(m, e),
          ),
        );
      },
    );
  }

  Widget _buildGrid(TvMetrics m, List<SourceEntry> entries) {
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: m.s(320),
        childAspectRatio: 0.82,
        crossAxisSpacing: m.spacingMd,
        mainAxisSpacing: m.spacingMd,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        return TvFocusable(
          autofocus: i == 0,
          padding: EdgeInsets.all(m.s(4)),
          onSelect: () => _onSelectEntry(e),
          child: _gridCard(m, e),
        );
      },
    );
  }

  ({IconData icon, Color color}) _iconFor(SourceEntry e) {
    if (e.isDir) return (icon: Icons.folder_rounded, color: const Color(0xFFF6B73C));
    if (e.isVideo) return (icon: Icons.movie_rounded, color: TvDesignTokens.brand);
    return (
      icon: Icons.insert_drive_file_outlined,
      color: TvDesignTokens.textSecondary
    );
  }

  Widget _row(TvMetrics m, SourceEntry e) {
    final deco = _iconFor(e);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: m.spacingLg, vertical: m.spacingMd),
      decoration: BoxDecoration(
        color: TvDesignTokens.surface,
        borderRadius: BorderRadius.circular(m.posterRadius),
      ),
      child: Row(
        children: [
          if (e.thumbUrl != null && e.thumbUrl!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(m.s(4)),
              child: MediaImage(
                imageUrl: e.thumbUrl,
                width: m.s(72),
                height: m.s(44),
                fit: BoxFit.cover,
                useDefaultUserAgent: true,
              ),
            )
          else
            Icon(deco.icon, color: deco.color, size: m.s(30)),
          SizedBox(width: m.spacingLg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  e.name,
                  // 文件名完整显示：放宽到 2 行。
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: m.fontSizeMd,
                      color: TvDesignTokens.textPrimary),
                ),
                if (e.size != null && !e.isDir)
                  Text(
                    formatSourceFileSize(e.size!),
                    style: TextStyle(
                        fontSize: m.fontSizeSm,
                        color: TvDesignTokens.textSecondary),
                  ),
              ],
            ),
          ),
          if (e.isDir)
            Icon(Icons.chevron_right,
                color: TvDesignTokens.textSecondary, size: m.s(26)),
        ],
      ),
    );
  }

  /// 封面网格卡：视频有缩略图则展示封面，否则大图标。对齐移动端 _EntryCard。
  Widget _gridCard(TvMetrics m, SourceEntry e) {
    final deco = _iconFor(e);
    final hasThumb = e.thumbUrl != null && e.thumbUrl!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(m.posterRadius),
            child: Container(
              width: double.infinity,
              color: TvDesignTokens.surface,
              child: hasThumb
                  ? MediaImage(
                      imageUrl: e.thumbUrl,
                      fit: BoxFit.cover,
                      useDefaultUserAgent: true,
                    )
                  : Center(
                      child: Icon(deco.icon, color: deco.color, size: m.s(44))),
            ),
          ),
        ),
        SizedBox(height: m.spacingXs),
        Text(
          e.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: m.fontSizeSm, color: TvDesignTokens.textPrimary),
        ),
        if (e.size != null && !e.isDir)
          Text(
            formatSourceFileSize(e.size!),
            style: TextStyle(
                fontSize: m.fontSizeXs, color: TvDesignTokens.textSecondary),
          ),
      ],
    );
  }
}
