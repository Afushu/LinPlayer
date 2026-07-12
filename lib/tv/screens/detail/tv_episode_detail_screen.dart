import '../../../core/widgets/app_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_interfaces.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/media_providers.dart';
import '../../../core/providers/episode_aggregation_provider.dart';
import '../../../core/providers/download_providers.dart';
import '../../../core/services/download/download_helper.dart';
import '../../../core/services/preload_service.dart';
import '../../../core/utils/color_extractor.dart';
import '../../../ui/utils/media_helpers.dart';
import '../../../ui/widgets/common/dynamic_background.dart';
import '../../../ui/widgets/common/media_widgets.dart';
import '../../theme/tv_design_tokens.dart';
import '../../theme/tv_metrics.dart';
import '../../widgets/tv_button.dart';
import '../../widgets/tv_focusable.dart';
import '../../widgets/tv_panel.dart';
import '../../widgets/tv_toast.dart';

/// TV 集详情（单集中间页）—— 从剧详情选集 / 首页继续观看进入。
/// 影院大图 + 「继续观看(带时间轴)」+ 上一集/下一集 + 左(剧情+演员)右(版本+其他服务器版本)双栏。
class TvEpisodeDetailScreen extends ConsumerStatefulWidget {
  final String? mediaId;

  const TvEpisodeDetailScreen({super.key, this.mediaId});

  @override
  ConsumerState<TvEpisodeDetailScreen> createState() =>
      _TvEpisodeDetailScreenState();
}

class _TvEpisodeDetailScreenState
    extends ConsumerState<TvEpisodeDetailScreen> {
  bool? _favoriteOverride;
  bool _downloading = false;

  Color _bgColor = const Color(0xFF121212);
  String? _colorFor;

  @override
  void initState() {
    super.initState();
    _triggerPreload();
  }

  void _triggerPreload() {
    final id = widget.mediaId;
    if (id == null || id.isEmpty) return;
    if (!ref.read(preloadEnabledProvider)) return;
    final ApiClientFactory api;
    try {
      api = ref.read(apiClientProvider);
    } catch (_) {
      return;
    }
    PreloadService.instance.preloadItem(
      api: api,
      itemId: id,
      enabled: true,
      preferredMediaSourceId: ref.read(selectedMediaSourceProvider),
      versionRegex: ref.read(preferredVersionRegexProvider),
      strmDirectPlay: ref.read(strmDirectPlayProvider),
    );
  }

  void _ensureColor(ApiClientFactory api, MediaItem item) {
    if (_colorFor == item.id) return;
    _colorFor = item.id;
    final urls = resolveMediaItemBannerImageUrls(api, item,
        maxWidth: 640, allowPosterFallback: true);
    if (urls.isEmpty) return;
    ColorExtractor.extractFromUrl(urls.first, brightness: Brightness.dark)
        .then((c) {
      if (mounted && c.background != _bgColor) {
        setState(() => _bgColor = c.background);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = context.tv;
    final id = widget.mediaId;
    if (id == null || id.isEmpty) return _errorScaffold('无效的媒体 ID', m);
    final itemAsync = ref.watch(mediaItemProvider(id));
    return DynamicBackground(
      backgroundColor: _bgColor,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: itemAsync.when(
          data: (item) => _buildContent(item, m),
          loading: () => const Center(
            child: AppLoadingIndicator(size: 48, color: TvDesignTokens.brand),
          ),
          error: (e, _) => _errorBody('加载失败：$e', m),
        ),
      ),
    );
  }

  Widget _buildContent(MediaItem item, TvMetrics m) {
    final api = ref.read(apiClientProvider);
    _ensureColor(api, item);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHero(api, item, m),
          Padding(
            padding: EdgeInsets.fromLTRB(
                m.spacingXl, m.spacingLg, m.spacingXl, m.spacingXxl),
            child: _buildBody(api, item, m),
          ),
        ],
      ),
    );
  }

  // ============ Hero ============

  Widget _buildHero(ApiClientFactory api, MediaItem item, TvMetrics m) {
    final banner = resolveMediaItemBannerImageUrls(api, item,
        maxWidth: 1600, allowPosterFallback: true);
    final fg = readableTextColorForBackground(_bgColor);
    final favorited = _favoriteOverride ?? (item.userData?.isFavorite ?? false);
    final heroHeight =
        (MediaQuery.sizeOf(context).height * 0.54).clamp(340.0, 700.0);

    return SizedBox(
      height: heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (banner.isNotEmpty)
            MediaImage(
              imageUrl: banner.first,
              imageUrls: banner.length > 1 ? banner.sublist(1) : null,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
            )
          else
            const ColoredBox(color: TvDesignTokens.surfaceElevated),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  _bgColor,
                  _bgColor.withValues(alpha: 0.6),
                  Colors.transparent,
                ],
                stops: const [0.02, 0.4, 0.75],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, _bgColor.withValues(alpha: 0.7), _bgColor],
                stops: const [0.45, 0.85, 1.0],
              ),
            ),
          ),
          // 返回
          Positioned(
            top: m.spacingMd,
            left: m.spacingMd,
            child: _circleButton(
              icon: Icons.arrow_back,
              onSelect: () =>
                  context.canPop() ? context.pop() : context.go('/tv'),
              m: m,
            ),
          ),
          // 收藏
          Positioned(
            top: m.spacingMd,
            right: m.spacingMd,
            child: _circleButton(
              icon: favorited ? Icons.favorite : Icons.favorite_border,
              iconColor: favorited ? const Color(0xFFFF6B6B) : Colors.white,
              onSelect: () => _toggleFavorite(item, favorited),
              m: m,
            ),
          ),
          // 文案 + 操作
          Positioned(
            left: m.spacingXl,
            right: m.spacingXl,
            bottom: m.spacingLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _kicker(item),
                  style: TextStyle(
                    fontSize: m.fontSizeSm,
                    color: TvDesignTokens.brandLight,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                SizedBox(height: m.spacingXs),
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: m.fontSizeXxl,
                    color: fg,
                    fontWeight: FontWeight.w800,
                    shadows: [
                      Shadow(blurRadius: 8, color: Colors.black.withValues(alpha: 0.5)),
                    ],
                  ),
                ),
                SizedBox(height: m.spacingSm),
                _buildMeta(item, m, fg),
                SizedBox(height: m.spacingLg),
                _buildActions(api, item, m),
              ],
            ).animate().fadeIn(duration: TvDesignTokens.contentFadeDuration),
          ),
        ],
      ),
    );
  }

  Widget _buildMeta(MediaItem item, TvMetrics m, Color fg) {
    final runtimeMin = (item.runTimeTicks != null && item.runTimeTicks! > 0)
        ? (item.runTimeTicks! ~/ 600000000)
        : null;
    return Row(
      children: [
        if (item.communityRating != null) ...[
          RatingBadge(rating: item.communityRating, size: m.fs(16)),
          SizedBox(width: m.spacingMd),
        ],
        if (runtimeMin != null) ...[
          Text('$runtimeMin 分钟',
              style: TextStyle(
                  fontSize: m.fontSizeSm, color: fg.withValues(alpha: 0.85))),
          SizedBox(width: m.spacingMd),
        ],
        if (item.productionYear != null)
          Text('${item.productionYear}',
              style: TextStyle(
                  fontSize: m.fontSizeSm, color: fg.withValues(alpha: 0.85))),
      ],
    );
  }

  String _kicker(MediaItem item) {
    final parts = <String>[];
    final s = item.seriesName?.trim();
    if (s != null && s.isNotEmpty) parts.add(s);
    final se = <String>[];
    if (item.parentIndexNumber != null) se.add('第${item.parentIndexNumber}季');
    if (item.indexNumber != null) se.add('第${item.indexNumber}集');
    if (se.isNotEmpty) parts.add(se.join(' '));
    return parts.join(' · ');
  }

  Widget _buildActions(ApiClientFactory api, MediaItem item, TvMetrics m) {
    final resumeTicks = item.userData?.playbackPositionTicks ?? 0;
    final played = item.userData?.played ?? false;
    final hasResume = !played && resumeTicks > 0;
    final progress = watchedFraction(resumeTicks, item.runTimeTicks);
    final timeText = formatWatchedOverTotalLabel(resumeTicks, item.runTimeTicks);
    final showProgress = hasResume && progress != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TvButton(
                text: hasResume && timeText != null
                    ? '继续观看  $timeText'
                    : (hasResume ? '继续观看' : '播放'),
                icon: Icons.play_arrow,
                autofocus: true,
                onPressed: () =>
                    context.push('/tv/player?mediaId=${item.id}'),
              ),
              if (showProgress) ...[
                SizedBox(height: m.spacingXs),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: m.spacingSm),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: m.s(4),
                      backgroundColor: TvDesignTokens.surfaceElevated,
                      valueColor:
                          const AlwaysStoppedAnimation(TvDesignTokens.brand),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(width: m.spacingMd),
        _buildSiblingButtons(item, m),
        TvButton(
          text: '更多',
          icon: Icons.more_horiz,
          outlined: true,
          onPressed: () => _showMoreMenu(item),
        ),
      ],
    );
  }

  /// 上一集 / 下一集：按同季集表定位当前集，前后各取一。无相邻集则隐藏对应键。
  Widget _buildSiblingButtons(MediaItem item, TvMetrics m) {
    final seriesId = item.seriesId;
    if (seriesId == null || seriesId.isEmpty) return const SizedBox.shrink();
    final eps = ref
        .watch(episodesProvider((seriesId: seriesId, seasonId: item.seasonId)))
        .valueOrNull;
    if (eps == null || eps.isEmpty) return const SizedBox.shrink();
    final idx = eps.indexWhere((e) => e.id == item.id);
    if (idx < 0) return const SizedBox.shrink();
    final prev = idx > 0 ? eps[idx - 1] : null;
    final next = idx < eps.length - 1 ? eps[idx + 1] : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (prev != null) ...[
          TvButton(
            text: '上一集',
            icon: Icons.skip_previous,
            outlined: true,
            onPressed: () => context.pushReplacement('/tv/episode/${prev.id}'),
          ),
          SizedBox(width: m.spacingMd),
        ],
        if (next != null) ...[
          TvButton(
            text: '下一集',
            icon: Icons.skip_next,
            outlined: true,
            onPressed: () => context.pushReplacement('/tv/episode/${next.id}'),
          ),
          SizedBox(width: m.spacingMd),
        ],
      ],
    );
  }

  // ============ Body（双栏）============

  Widget _buildBody(ApiClientFactory api, MediaItem item, TvMetrics m) {
    final hasOverview = item.overview != null && item.overview!.trim().isNotEmpty;
    final people = (item.people ?? [])
        .where((p) => p.type == null || p.type == 'Actor' || p.role != null)
        .take(20)
        .toList(growable: false);
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasOverview) ...[
          _sectionTitle('剧情简介', m),
          SizedBox(height: m.spacingSm),
          Text(
            item.overview!.trim(),
            style: TextStyle(
              fontSize: m.fontSizeSm,
              color: TvDesignTokens.textSecondary,
              height: TvDesignTokens.lineHeightRelaxed,
            ),
          ),
        ],
        if (people.isNotEmpty) ...[
          SizedBox(height: m.spacingLg),
          _sectionTitle('演员', m),
          SizedBox(height: m.spacingMd),
          SizedBox(
            height: m.s(150),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: people.length,
              separatorBuilder: (_, __) => SizedBox(width: m.spacingLg),
              itemBuilder: (context, i) =>
                  TvFocusable(child: _personCard(api, people[i], m)),
            ),
          ),
        ],
      ],
    );
    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildVersionInfo(item.id, m),
        _buildAggregationBar(item, m),
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: left),
        SizedBox(width: m.spacingXxl),
        Expanded(flex: 2, child: right),
      ],
    );
  }

  Widget _sectionTitle(String t, TvMetrics m) => Text(
        t,
        style: TextStyle(
          fontSize: m.fontSizeLg,
          color: TvDesignTokens.textPrimary,
          fontWeight: FontWeight.bold,
        ),
      );

  Widget _buildVersionInfo(String itemId, TvMetrics m) {
    final info = ref.watch(playbackInfoProvider(itemId)).valueOrNull;
    if (info == null || info.mediaSources.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('版本信息', m),
        SizedBox(height: m.spacingSm),
        for (final source in info.mediaSources)
          MediaSourceInfoCard(source: source),
      ],
    );
  }

  Widget _buildAggregationBar(MediaItem item, TvMetrics m) {
    final versions =
        ref.watch(episodeAggregationProvider(item.id)).valueOrNull ??
            const <AggregatedVersion>[];
    if (versions.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: m.spacingLg),
        _sectionTitle('其他服务器版本', m),
        SizedBox(height: m.spacingSm),
        for (final v in versions)
          Padding(
            padding: EdgeInsets.only(bottom: m.spacingMd),
            child: TvFocusable(
              onSelect: () => playAggregatedVersion(ref, context, v, isTv: true),
              child: _aggregationCard(v, m),
            ),
          ),
      ],
    );
  }

  Widget _aggregationCard(AggregatedVersion v, TvMetrics m) {
    final hit = v.matchesRegex;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: m.spacingMd, vertical: m.spacingSm),
      decoration: BoxDecoration(
        color: TvDesignTokens.surface,
        borderRadius: BorderRadius.circular(m.posterRadius),
        border: Border.all(
          color: hit ? TvDesignTokens.brand : TvDesignTokens.surfaceElevated,
          width: hit ? m.s(2) : m.s(1),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.dns_outlined,
              size: m.s(26),
              color: hit ? TvDesignTokens.brand : TvDesignTokens.textSecondary),
          SizedBox(width: m.spacingSm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(v.server.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: m.fontSizeSm,
                              color: TvDesignTokens.textPrimary,
                              fontWeight: FontWeight.w600)),
                    ),
                    if (hit) ...[
                      SizedBox(width: m.spacingXs),
                      Icon(Icons.star, size: m.s(16), color: TvDesignTokens.brand),
                    ],
                  ],
                ),
                SizedBox(height: m.spacingXs),
                Text(aggregatedVersionLabel(v.source),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: m.fontSizeXs,
                        color: TvDesignTokens.textSecondary)),
              ],
            ),
          ),
          SizedBox(width: m.spacingSm),
          Icon(Icons.play_circle_outline,
              size: m.s(26), color: TvDesignTokens.brand),
        ],
      ),
    );
  }

  Widget _personCard(ApiClientFactory api, Person p, TvMetrics m) {
    final double d = m.s(88);
    final url = p.primaryImageTag != null
        ? api.image.getPrimaryImageUrl(p.id, tag: p.primaryImageTag, maxWidth: 200)
        : null;
    return SizedBox(
      width: m.s(110),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipOval(
            child: SizedBox(
              width: d,
              height: d,
              child: url != null
                  ? MediaImage(imageUrl: url, width: d, height: d, fit: BoxFit.cover)
                  : ColoredBox(
                      color: TvDesignTokens.surfaceElevated,
                      child: Icon(Icons.person,
                          color: TvDesignTokens.textDisabled, size: m.s(40)),
                    ),
            ),
          ),
          SizedBox(height: m.spacingXs),
          Text(p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: m.fontSizeXs,
                  color: TvDesignTokens.textPrimary,
                  fontWeight: FontWeight.w600)),
          if (p.role != null && p.role!.trim().isNotEmpty)
            Text(p.role!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: m.fs(11), color: TvDesignTokens.textSecondary)),
        ],
      ),
    );
  }

  // ============ 圆钮 / 交互 ============

  Widget _circleButton({
    required IconData icon,
    required VoidCallback onSelect,
    required TvMetrics m,
    Color iconColor = Colors.white,
    bool busy = false,
  }) {
    return TvFocusable(
      onSelect: onSelect,
      padding: EdgeInsets.all(m.spacingXs),
      child: Container(
        width: m.s(52),
        height: m.s(52),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: busy
            ? SizedBox(
                width: m.s(22),
                height: m.s(22),
                child: const CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Icon(icon, color: iconColor, size: m.s(26)),
      ),
    );
  }

  Future<void> _toggleFavorite(MediaItem item, bool current) async {
    setState(() => _favoriteOverride = !current);
    try {
      final api = ref.read(apiClientProvider);
      if (current) {
        await api.favorite.removeFavorite(item.id);
      } else {
        await api.favorite.addFavorite(item.id);
      }
      if (mounted) TvToast.show(context, current ? '已取消收藏' : '已收藏');
    } catch (_) {
      if (mounted) {
        setState(() => _favoriteOverride = current);
        TvToast.show(context, '操作失败');
      }
    }
  }

  void _showMoreMenu(MediaItem item) {
    final canDownload = item.canDownload ?? true;
    final watched = item.userData?.played ?? false;
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => TvPanel(
        title: '更多',
        onClose: () => Navigator.pop(ctx),
        children: [
          TvPanelOption(
            title: '下载本集',
            leading: const Icon(Icons.download, color: TvDesignTokens.textPrimary),
            onTap: () {
              Navigator.pop(ctx);
              if (canDownload) {
                _onDownload(item);
              } else {
                TvToast.show(context, '当前服务器未开放下载权限');
              }
            },
          ),
          TvPanelOption(
            title: watched ? '标记为未观看' : '标记为已观看',
            leading:
                const Icon(Icons.visibility, color: TvDesignTokens.textPrimary),
            onTap: () {
              Navigator.pop(ctx);
              _toggleWatched(item, watched);
            },
          ),
          TvPanelOption(
            title: '搜索其他播放源',
            leading: const Icon(Icons.search, color: TvDesignTokens.textPrimary),
            onTap: () {
              Navigator.pop(ctx);
              context.push('/tv/search');
            },
          ),
        ],
      ),
    );
  }

  Future<void> _onDownload(MediaItem item) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final api = ref.read(apiClientProvider);
      final allowedByPolicy = await ref.read(downloadPermissionProvider.future);
      if (!allowedByPolicy || !(item.canDownload ?? true)) {
        if (mounted) TvToast.show(context, '当前服务器未开放下载权限');
        return;
      }
      final manager = ref.read(downloadManagerProvider);
      final task =
          await startMediaDownload(api: api, manager: manager, item: item);
      if (mounted) {
        TvToast.show(context, task != null ? '已添加到下载队列' : '添加下载失败');
      }
    } catch (_) {
      if (mounted) TvToast.show(context, '下载失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _toggleWatched(MediaItem item, bool watched) async {
    try {
      final api = ref.read(apiClientProvider);
      if (watched) {
        await api.playback.reportPlaybackStopped(PlaybackStopInfo(
          itemId: item.id,
          mediaSourceId: '',
          positionTicks: 0,
        ));
      } else {
        await api.playback.reportPlaybackStart(PlaybackStartInfo(
          itemId: item.id,
          mediaSourceId: '',
        ));
        await api.playback.reportPlaybackStopped(PlaybackStopInfo(
          itemId: item.id,
          mediaSourceId: '',
          positionTicks: item.runTimeTicks ?? 0,
        ));
      }
      ref.invalidate(mediaItemProvider(item.id));
      if (mounted) TvToast.show(context, watched ? '已标记未观看' : '已标记已观看');
    } catch (_) {
      if (mounted) TvToast.show(context, '操作失败');
    }
  }

  Widget _errorScaffold(String msg, TvMetrics m) => Scaffold(
        backgroundColor: TvDesignTokens.background,
        body: _errorBody(msg, m),
      );

  Widget _errorBody(String msg, TvMetrics m) => Center(
        child: Text(msg,
            style: TextStyle(
                color: TvDesignTokens.textSecondary, fontSize: m.fontSizeMd)),
      );
}
