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

/// TV 详情页（剧/电影）—— 观感对齐移动端：沉浸式 Hero 背景（海报取色染整页）+
/// 返回/收藏/下载角标按钮 + 标题·评分·类型标签 + 播放/更多 + 季选择 + 选集 + 简介 +
/// 版本信息。全部交互项走 [TvFocusable] 遥控器焦点驱动。
class TvDetailScreen extends ConsumerStatefulWidget {
  final String? mediaId;

  const TvDetailScreen({super.key, this.mediaId});

  @override
  ConsumerState<TvDetailScreen> createState() => _TvDetailScreenState();
}

class _TvDetailScreenState extends ConsumerState<TvDetailScreen> {
  String? _selectedSeasonId;
  bool? _favoriteOverride; // 本地乐观状态
  bool _downloadingSeries = false;

  /// Hero 取色 → 整页沉浸背景（对齐移动端）。默认深色。
  Color _bgColor = const Color(0xFF121212);
  String? _colorFor; // 已取色的条目 id，防重复触发

  @override
  void initState() {
    super.initState();
    _triggerPreload();
  }

  /// 进入详情页即按规范流程预热真实播放流（受「预加载」开关控制，fire-and-forget）。
  /// 剧集根等非可直接播放条目会在服务内部自动 no-op。
  void _triggerPreload() {
    final id = widget.mediaId;
    if (id == null || id.isEmpty) return;
    if (!ref.read(preloadEnabledProvider)) return;
    final ApiClientFactory api;
    try {
      api = ref.read(apiClientProvider);
    } catch (_) {
      return; // 未连接服务器
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

  /// 从横图取色染整页背景（每个条目只跑一次，异步回填）。
  void _ensureColor(ApiClientFactory api, MediaItem item) {
    if (_colorFor == item.id) return;
    _colorFor = item.id;
    final urls = resolveMediaItemLandscapeImageUrls(api, item, maxWidth: 640);
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
    if (id == null || id.isEmpty) {
      return _errorScaffold('无效的媒体 ID', m);
    }
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
          error: (e, _) => _errorBody('加载详情失败：$e', m),
        ),
      ),
    );
  }

  Widget _buildContent(MediaItem item, TvMetrics m) {
    final api = ref.read(apiClientProvider);
    _ensureColor(api, item);
    final isSeries = item.type == 'Series';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeroArea(api, item, m),
          Padding(
            padding: EdgeInsets.all(m.spacingXl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildActionButtons(item, m),
                if (isSeries) ...[
                  // 剧：聚合栏 + 季/选集大网格（单栏，选集是主角）+ 简介 + 演员。
                  _buildAggregationBar(item, m),
                  SizedBox(height: m.spacingLg),
                  _buildSeasonsAndEpisodes(api, item, m),
                  if (item.overview != null && item.overview!.isNotEmpty) ...[
                    SizedBox(height: m.spacingLg),
                    _buildSynopsis(item.overview!, m),
                  ],
                  _buildCast(api, item, m),
                ] else
                  // 电影：左(简介+演员) 右(版本信息+其他服务器版本) 双栏。
                  _buildMovieBody(api, item, m),
                SizedBox(height: m.spacingXxl),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroArea(ApiClientFactory api, MediaItem item, TvMetrics m) {
    final banner = resolveMediaItemBannerImageUrls(api, item,
        maxWidth: 1600, allowPosterFallback: true);
    final logo = (item.logoItemId != null && item.logoImageTag != null)
        ? api.image
            .getLogoImageUrl(item.logoItemId!, tag: item.logoImageTag, maxWidth: 320)
        : null;
    final fg = readableTextColorForBackground(_bgColor);
    final favorited = _favoriteOverride ?? (item.userData?.isFavorite ?? false);

    return SizedBox(
      height: m.s(420),
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
          // 底部渐变：让海报柔和融进沉浸背景色。
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  _bgColor.withValues(alpha: 0.55),
                  _bgColor.withValues(alpha: 0.92),
                  _bgColor,
                ],
                stops: const [0.35, 0.7, 0.88, 1.0],
              ),
            ),
          ),
          // 左上角：返回
          Positioned(
            top: m.spacingMd,
            left: m.spacingMd,
            child: _circleButton(
              icon: Icons.arrow_back,
              onSelect: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/tv');
                }
              },
              m: m,
            ),
          ),
          // 右上角：收藏 + 下载（剧集为整剧下载）
          Positioned(
            top: m.spacingMd,
            right: m.spacingMd,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _circleButton(
                  icon: favorited ? Icons.favorite : Icons.favorite_border,
                  iconColor: favorited ? const Color(0xFFFF6B6B) : Colors.white,
                  onSelect: () => _toggleFavorite(item, favorited),
                  m: m,
                ),
                SizedBox(width: m.spacingSm),
                _circleButton(
                  icon: Icons.download,
                  busy: _downloadingSeries,
                  onSelect: () => _onDownload(item),
                  m: m,
                ),
              ],
            ),
          ),
          // 标题 + 评分 + 类型标签
          Positioned(
            left: m.spacingXl,
            right: m.spacingXl,
            bottom: m.spacingLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (logo != null && logo.isNotEmpty)
                  Image.network(logo,
                      height: m.s(64),
                      fit: BoxFit.contain,
                      alignment: Alignment.centerLeft,
                      errorBuilder: (_, __, ___) => _titleText(item.name, m, fg))
                else
                  _titleText(item.name, m, fg),
                SizedBox(height: m.spacingSm),
                Row(
                  children: [
                    if (item.communityRating != null) ...[
                      RatingBadge(
                          rating: item.communityRating, size: m.fs(16)),
                      SizedBox(width: m.spacingMd),
                    ],
                    Expanded(
                      child: Wrap(
                        spacing: m.spacingSm,
                        runSpacing: m.spacingXs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (item.productionYear != null)
                            Text(
                              '${item.productionYear}',
                              style: TextStyle(
                                fontSize: m.fontSizeSm,
                                color: fg.withValues(alpha: 0.85),
                              ),
                            ),
                          ...?item.genres
                              ?.take(4)
                              .map((g) => TagBadge(text: g)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ).animate().fadeIn(duration: TvDesignTokens.contentFadeDuration),
          ),
        ],
      ),
    );
  }

  /// Hero 角标圆形按钮（返回/收藏/下载），遥控器可聚焦。
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

  Widget _titleText(String name, TvMetrics m, Color fg) => Text(
        name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: m.fontSizeXxl,
          color: fg,
          fontWeight: FontWeight.w800,
          shadows: [
            Shadow(
                blurRadius: 8,
                color: Colors.black.withValues(alpha: 0.5)),
          ],
        ),
      );

  Widget _buildActionButtons(MediaItem item, TvMetrics m) {
    final resumeTicks = item.userData?.playbackPositionTicks ?? 0;
    final hasResume =
        item.type != 'Series' && !(item.userData?.played ?? false) && resumeTicks > 0;
    final progress = watchedFraction(resumeTicks, item.runTimeTicks);
    final timeText = formatWatchedOverTotalLabel(resumeTicks, item.runTimeTicks);
    final showProgress = hasResume && progress != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 播放键：键内显示「继续观看 12:34 / 45:00」，键下贴一条等宽观看进度条
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
                onPressed: () => _onPlayMain(item),
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
                      valueColor: const AlwaysStoppedAnimation(
                          TvDesignTokens.brand),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(width: m.spacingMd),
        TvButton(
          text: '更多',
          icon: Icons.more_horiz,
          outlined: true,
          onPressed: () => _showMoreMenu(item),
        ),
      ],
    );
  }

  /// 顶部「播放/继续观看」：影片直接播；剧集挑「进行中 → 首个未看 → 第一集」。
  Future<void> _onPlayMain(MediaItem item) async {
    if (item.type != 'Series') {
      context.push('/tv/player?mediaId=${item.id}');
      return;
    }
    try {
      final api = ref.read(apiClientProvider);
      final seasons = await api.media.getSeasons(item.id);
      final seasonId = seasons.isNotEmpty ? seasons.first.id : null;
      final episodes = await api.media.getEpisodes(item.id, seasonId: seasonId);
      if (episodes.isEmpty) return;
      Episode? target;
      for (final e in episodes) {
        final pos = e.userData?.playbackPositionTicks ?? 0;
        if (!(e.userData?.played ?? false) && pos > 0) {
          target = e;
          break;
        }
      }
      target ??= episodes.firstWhere(
        (e) => !(e.userData?.played ?? false),
        orElse: () => episodes.first,
      );
      if (mounted) context.push('/tv/player?mediaId=${target.id}');
    } catch (_) {
      if (mounted) context.push('/tv/player?mediaId=${item.id}');
    }
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
    } catch (e) {
      if (mounted) {
        setState(() => _favoriteOverride = current);
        TvToast.show(context, '操作失败');
      }
    }
  }

  /// 下载：剧集整剧入队，电影单条入队；先过服务端下载权限。
  Future<void> _onDownload(MediaItem item) async {
    if (_downloadingSeries) return;
    setState(() => _downloadingSeries = true);
    try {
      final api = ref.read(apiClientProvider);
      final allowedByPolicy =
          await ref.read(downloadPermissionProvider.future);
      if (!allowedByPolicy || !(item.canDownload ?? true)) {
        if (mounted) TvToast.show(context, '当前服务器未开放下载权限');
        return;
      }
      final manager = ref.read(downloadManagerProvider);
      if (item.type == 'Series') {
        final result = await startSeriesDownload(
            api: api, manager: manager, series: item);
        if (mounted) {
          TvToast.show(
              context,
              result.queued > 0
                  ? '已加入下载 ${result.queued} 集'
                  : '全部 ${result.total} 集已在下载列表');
        }
      } else {
        final task =
            await startMediaDownload(api: api, manager: manager, item: item);
        if (mounted) {
          TvToast.show(context, task != null ? '已添加到下载队列' : '添加下载失败');
        }
      }
    } catch (_) {
      if (mounted) TvToast.show(context, '下载失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _downloadingSeries = false);
    }
  }

  /// 更多菜单：右侧滑入面板（下载 / 标记已看未看 / 搜索其他播放源）。
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
            title: '下载',
            leading: const Icon(Icons.download,
                color: TvDesignTokens.textPrimary),
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
            leading: const Icon(Icons.visibility,
                color: TvDesignTokens.textPrimary),
            onTap: () {
              Navigator.pop(ctx);
              _toggleWatched(item, watched);
            },
          ),
          TvPanelOption(
            title: '搜索其他播放源',
            leading:
                const Icon(Icons.search, color: TvDesignTokens.textPrimary),
            onTap: () {
              Navigator.pop(ctx);
              context.push('/tv/search');
            },
          ),
        ],
      ),
    );
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

  /// 电影正文双栏：左「简介 + 演员」，右「版本信息 + 其他服务器版本」。
  /// 10-foot 上双栏比长列表少上下翻，遥控器左右即可跨栏。
  Widget _buildMovieBody(ApiClientFactory api, MediaItem item, TvMetrics m) {
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.overview != null && item.overview!.isNotEmpty)
          _buildSynopsis(item.overview!, m),
        _buildCast(api, item, m),
      ],
    );
    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildVersionInfo(item.id, m),
        _buildAggregationBar(item, m),
      ],
    );
    return Padding(
      padding: EdgeInsets.only(top: m.spacingLg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: left),
          SizedBox(width: m.spacingXxl),
          Expanded(flex: 2, child: right),
        ],
      ),
    );
  }

  /// 演员表：圆形头像 + 姓名 + 角色，横向可聚焦浏览（纯展示，OK 无动作）。
  Widget _buildCast(ApiClientFactory api, MediaItem item, TvMetrics m) {
    final people = (item.people ?? [])
        .where((p) => p.type == null || p.type == 'Actor' || p.role != null)
        .take(20)
        .toList(growable: false);
    if (people.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: m.spacingLg),
        Text(
          '演员',
          style: TextStyle(
            fontSize: m.fontSizeLg,
            color: TvDesignTokens.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: m.spacingMd),
        SizedBox(
          height: m.s(150),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: people.length,
            separatorBuilder: (_, __) => SizedBox(width: m.spacingLg),
            itemBuilder: (context, i) =>
                TvFocusable(child: _buildPersonCard(api, people[i], m)),
          ),
        ),
      ],
    );
  }

  Widget _buildPersonCard(ApiClientFactory api, Person p, TvMetrics m) {
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
          Text(
            p.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: m.fontSizeXs,
              color: TvDesignTokens.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (p.role != null && p.role!.trim().isNotEmpty)
            Text(
              p.role!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: m.fs(11),
                color: TvDesignTokens.textSecondary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSynopsis(String overview, TvMetrics m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '简介',
          style: TextStyle(
            fontSize: m.fontSizeLg,
            color: TvDesignTokens.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: m.spacingSm),
        Text(
          overview,
          style: TextStyle(
            fontSize: m.fontSizeSm,
            color: TvDesignTokens.textSecondary,
            height: TvDesignTokens.lineHeightRelaxed,
          ),
        ),
      ],
    );
  }

  /// 电影版本信息：复用移动端 [MediaSourceInfoCard]（名称/视频/容器·大小·码率/音轨/字幕）。
  Widget _buildVersionInfo(String itemId, TvMetrics m) {
    final info = ref.watch(playbackInfoProvider(itemId)).valueOrNull;
    if (info == null || info.mediaSources.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: m.spacingLg),
        Text(
          '版本信息',
          style: TextStyle(
            fontSize: m.fontSizeLg,
            color: TvDesignTokens.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: m.spacingSm),
        for (final source in info.mediaSources)
          MediaSourceInfoCard(source: source),
      ],
    );
  }

  /// 其他服务器版本聚合栏：同一集/同一部电影在其它已登录 Emby 服务器上的所有版本，
  /// 正则命中者描边高亮并排前。无匹配/加载中静默不占位。焦点选中即切服并播。
  Widget _buildAggregationBar(MediaItem item, TvMetrics m) {
    final versions =
        ref.watch(episodeAggregationProvider(item.id)).valueOrNull ??
            const <AggregatedVersion>[];
    if (versions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: m.spacingLg),
        Text(
          '其他服务器版本',
          style: TextStyle(
            fontSize: m.fontSizeLg,
            color: TvDesignTokens.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: m.spacingSm),
        SizedBox(
          height: m.s(96),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: versions.length,
            separatorBuilder: (_, __) => SizedBox(width: m.spacingMd),
            itemBuilder: (context, index) {
              final v = versions[index];
              return TvFocusable(
                onSelect: () => playAggregatedVersion(ref, context, v, isTv: true),
                child: _buildAggregationCard(v, m),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAggregationCard(AggregatedVersion v, TvMetrics m) {
    final hit = v.matchesRegex;
    return Container(
      width: m.s(320),
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
                      child: Text(
                        v.server.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: m.fontSizeSm,
                          color: TvDesignTokens.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (hit) ...[
                      SizedBox(width: m.spacingXs),
                      Icon(Icons.star,
                          size: m.s(16), color: TvDesignTokens.brand),
                    ],
                  ],
                ),
                SizedBox(height: m.spacingXs),
                Text(
                  aggregatedVersionLabel(v.source),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: m.fontSizeXs,
                    color: TvDesignTokens.textSecondary,
                  ),
                ),
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

  Widget _buildSeasonsAndEpisodes(
      ApiClientFactory api, MediaItem series, TvMetrics m) {
    final seasonsAsync = ref.watch(seasonsProvider(series.id));
    return seasonsAsync.when(
      data: (seasons) {
        if (seasons.isEmpty) return const SizedBox.shrink();
        final seasonId = _selectedSeasonId ?? seasons.first.id;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '季度选择',
              style: TextStyle(
                fontSize: m.fontSizeLg,
                color: TvDesignTokens.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: m.spacingSm),
            SizedBox(
              height: m.s(150) * 1.5 + m.spacingMd,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: seasons.length,
                separatorBuilder: (_, __) => SizedBox(width: m.spacingMd),
                itemBuilder: (context, index) {
                  final season = seasons[index];
                  final selected = season.id == seasonId;
                  return TvFocusable(
                    onSelect: () =>
                        setState(() => _selectedSeasonId = season.id),
                    child: _buildSeasonCard(api, season, selected, m),
                  );
                },
              ),
            ),
            SizedBox(height: m.spacingLg),
            _buildEpisodeList(api, series.id, seasonId, m),
          ],
        );
      },
      loading: () => Padding(
        padding: EdgeInsets.all(m.spacingLg),
        child: const AppLoadingIndicator(size: 48, color: TvDesignTokens.brand),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  /// 季封面卡片：2:3 海报 + 底部渐变叠季名（对齐移动端），选中时描品牌色边。
  Widget _buildSeasonCard(
      ApiClientFactory api, Season season, bool selected, TvMetrics m) {
    final double w = m.s(150);
    final double h = w * 1.5;
    final poster = _seasonImageUrl(api, season);
    final label = season.name.trim().isNotEmpty
        ? season.name
        : 'S${season.indexNumber ?? ''}';
    return SizedBox(
      width: w,
      height: h,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(m.posterRadius),
          border: selected
              ? Border.all(color: TvDesignTokens.brand, width: m.s(3))
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            poster != null
                ? MediaImage(
                    imageUrl: poster, width: w, height: h, fit: BoxFit.cover)
                : const ColoredBox(
                    color: TvDesignTokens.surfaceElevated,
                    child: Icon(Icons.video_library_outlined,
                        color: TvDesignTokens.textDisabled),
                  ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.only(top: m.s(20), bottom: m.spacingXs),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: m.fontSizeSm,
                    color: selected ? TvDesignTokens.brand : Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEpisodeList(
      ApiClientFactory api, String seriesId, String seasonId, TvMetrics m) {
    final episodesAsync =
        ref.watch(episodesProvider((seriesId: seriesId, seasonId: seasonId)));
    return episodesAsync.when(
      data: (episodes) {
        if (episodes.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '共 ${episodes.length} 集',
              style: TextStyle(
                fontSize: m.fontSizeLg,
                color: TvDesignTokens.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: m.spacingMd),
            // 竖向剧集卡片网格（封面 + 第N集 + 集名），便于遥控器上下左右选集。
            Wrap(
              spacing: m.spacingMd,
              runSpacing: m.spacingLg,
              children: [
                for (final entry in episodes.asMap().entries)
                  TvFocusable(
                    onSelect: () =>
                        context.push('/tv/episode/${entry.value.id}'),
                    child: _buildEpisodeCard(api, entry.value, m),
                  ).animate().fadeIn(
                        delay: Duration(milliseconds: 20 * (entry.key % 12)),
                        duration: TvDesignTokens.contentFadeDuration,
                      ),
              ],
            ),
          ],
        );
      },
      loading: () => Padding(
        padding: EdgeInsets.all(m.spacingLg),
        child: const AppLoadingIndicator(size: 48, color: TvDesignTokens.brand),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  /// 竖向剧集卡片：16:9 封面（集数角标 + 已看标记 + 进度）+ 第N集 + 集名。
  Widget _buildEpisodeCard(ApiClientFactory api, Episode ep, TvMetrics m) {
    final double w = m.s(260);
    final double coverH = w * 9 / 16;
    final thumbUrl = _episodeImageUrl(api, ep);
    final watched = ep.userData?.played ?? false;
    final progress = _episodeProgress(ep);
    return SizedBox(
      width: w,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(m.posterRadius),
            child: SizedBox(
              width: w,
              height: coverH,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  thumbUrl != null
                      ? MediaImage(
                          imageUrl: thumbUrl,
                          width: w,
                          height: coverH,
                          fit: BoxFit.cover,
                        )
                      : const ColoredBox(
                          color: TvDesignTokens.surfaceElevated,
                          child: Icon(Icons.movie_outlined,
                              color: TvDesignTokens.textDisabled),
                        ),
                  // 集数角标
                  if (ep.indexNumber != null)
                    Positioned(
                      top: m.spacingXs,
                      left: m.spacingXs,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: m.s(8), vertical: m.s(2)),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(m.s(4)),
                        ),
                        child: Text(
                          'E${ep.indexNumber}',
                          style: TextStyle(
                            fontSize: m.fs(12),
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  if (watched)
                    Positioned(
                      top: m.spacingXs,
                      right: m.spacingXs,
                      child: Icon(Icons.check_circle,
                          color: TvDesignTokens.success, size: m.s(22)),
                    ),
                  if (progress > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: m.s(4),
                        backgroundColor: Colors.black54,
                        valueColor: const AlwaysStoppedAnimation(
                            TvDesignTokens.brand),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(height: m.spacingXs),
          Text(
            '第 ${ep.indexNumber ?? '?'} 集',
            style: TextStyle(
              fontSize: m.fontSizeXs,
              color: TvDesignTokens.textSecondary,
            ),
          ),
          Text(
            ep.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: m.fontSizeSm,
              color: TvDesignTokens.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String? _seasonImageUrl(ApiClientFactory api, Season s) {
    if (s.primaryImageTag != null) {
      return api.image
          .getPrimaryImageUrl(s.id, tag: s.primaryImageTag, maxWidth: 400);
    }
    if (s.thumbImageTag != null) {
      return api.image
          .getThumbImageUrl(s.id, tag: s.thumbImageTag, maxWidth: 400);
    }
    if (s.seriesId.isNotEmpty && s.seriesPrimaryImageTag != null) {
      return api.image.getPrimaryImageUrl(s.seriesId,
          tag: s.seriesPrimaryImageTag, maxWidth: 400);
    }
    return null;
  }

  double _episodeProgress(Episode ep) {
    if (ep.userData?.played ?? false) return 0;
    final pos = ep.userData?.playbackPositionTicks ?? 0;
    final total = ep.runTimeTicks ?? 0;
    if (total <= 0 || pos <= 0) return 0;
    final p = pos / total;
    return p > 0.98 ? 0 : p.clamp(0.0, 1.0).toDouble();
  }

  String? _episodeImageUrl(ApiClientFactory api, Episode ep) {
    if (ep.primaryImageTag != null) {
      return api.image
          .getPrimaryImageUrl(ep.id, tag: ep.primaryImageTag, maxWidth: 400);
    }
    if (ep.thumbImageTag != null) {
      return api.image
          .getThumbImageUrl(ep.id, tag: ep.thumbImageTag, maxWidth: 400);
    }
    return null;
  }

  Widget _errorScaffold(String msg, TvMetrics m) => Scaffold(
        backgroundColor: TvDesignTokens.background,
        body: _errorBody(msg, m),
      );

  Widget _errorBody(String msg, TvMetrics m) => Center(
        child: Text(
          msg,
          style: TextStyle(
            color: TvDesignTokens.textSecondary,
            fontSize: m.fontSizeMd,
          ),
        ),
      );
}
