import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_interfaces.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/media_providers.dart';
import '../../../core/utils/color_extractor.dart';
import '../../../ui/utils/media_helpers.dart';
import '../../../ui/widgets/common/dynamic_background.dart';
import '../../../ui/widgets/common/media_widgets.dart';
import '../anirss/tv_anirss_view.dart';
import '../source/tv_source_browse_screen.dart';
import '../../theme/tv_design_tokens.dart';
import '../../theme/tv_metrics.dart';
import '../../widgets/tv_button.dart';
import '../../widgets/tv_media_card.dart';

/// TV 首页
///
/// 10-foot 版式：顶部一张影院级大图 Hero（当前精选：大标题/Logo + 评分·年份·类型 +
/// 「播放 / 详情 / 换一部」焦点按钮），下方是继续观看 / 媒体库 / 各库最新 / 合集的横向
/// 焦点行。不再嵌移动端的自动翻页轮播（那个既是移动端观感，方向键还会把「←」吃掉、
/// 让焦点跨不回侧栏）。Hero 取色渲染整页沉浸背景。
class TvHomeScreen extends ConsumerStatefulWidget {
  const TvHomeScreen({super.key});

  @override
  ConsumerState<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends ConsumerState<TvHomeScreen> {
  /// Hero 取色 → 整页沉浸背景（对齐移动端）。默认深色。
  Color _bgColor = const Color(0xFF121212);
  String? _colorFor; // 已取色的条目 id，防重复触发
  int _featuredIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  void _refresh() {
    ref.invalidate(resumeItemsProvider);
    ref.invalidate(librariesProvider);
    ref.invalidate(randomRecommendationsProvider);
  }

  /// 从横图取色染整页背景（每个精选条目只跑一次，异步回填）。
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
    final servers = ref.watch(serverListProvider);
    if (servers.isEmpty) {
      return _buildEmptyServers(m);
    }

    // 网盘/聚合源：首页改渲染对应视图（保留侧边栏）。
    final currentServer = ref.watch(currentServerProvider);
    if (currentServer != null && currentServer.sourceKind == SourceKind.anirss) {
      return TvAniRssView(server: currentServer);
    }
    if (currentServer != null && currentServer.isFileBrowse) {
      return TvSourceBrowseView(server: currentServer);
    }

    final api = ref.read(apiClientProvider);
    final resumeAsync = ref.watch(resumeItemsProvider);
    final librariesAsync = ref.watch(librariesProvider);
    final hideDaily = ref.watch(hideDailyRecommendationsProvider);
    final featured =
        ref.watch(randomRecommendationsProvider).valueOrNull ?? const [];

    return DynamicBackground(
      backgroundColor: _bgColor,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 影院级大图 Hero（当前精选）。
              if (!hideDaily && featured.isNotEmpty)
                _buildHero(api, featured, m)
              else if (!hideDaily)
                _heroPlaceholder(m),
              SizedBox(height: m.spacingLg),

              // 继续观看
              resumeAsync.when(
                data: (items) {
                  final visible = items
                      .where((i) => !(i.userData?.played ?? false))
                      .toList(growable: false);
                  if (visible.isEmpty) return const SizedBox.shrink();
                  return TvRow(
                    title: '继续观看',
                    rowHeight: m.posterHeight16_9 + m.s(80),
                    cards: [
                      for (final it in visible)
                        TvLandscapeCard(
                          imageUrl: _first(resolveMediaItemLandscapeImageUrls(
                              api, it,
                              maxWidth: 720)),
                          title: _continueTitle(it),
                          subtitle: _continueSubtitle(it),
                          badge: _continueBadge(it),
                          progress: it.progress,
                          // 剧集直接进「集详情」（带续播）；影片进影片详情。
                          onSelect: () => it.type == 'Episode'
                              ? context.push('/tv/episode/${it.id}')
                              : context.push('/tv/detail/${it.id}'),
                        ),
                    ],
                  );
                },
                loading: () => _rowPlaceholder('继续观看', m),
                error: (_, __) => const SizedBox.shrink(),
              ),
              SizedBox(height: m.spacingMd),

              // 媒体库快捷入口
              librariesAsync.when(
                data: (libs) {
                  if (libs.isEmpty) return const SizedBox.shrink();
                  return TvRow(
                    title: '媒体库',
                    rowHeight: m.posterHeight16_9 + m.s(64),
                    onSeeAll: () => context.go('/tv/library'),
                    cards: [
                      for (final lib in libs)
                        TvLandscapeCard(
                          imageUrl: _first(
                              resolveLibraryImageUrls(api, lib, maxWidth: 400)),
                          title: lib.name,
                          onSelect: () =>
                              context.go('/tv/library?libraryId=${lib.id}'),
                        ),
                    ],
                  );
                },
                loading: () => _rowPlaceholder('媒体库', m),
                error: (_, __) => const SizedBox.shrink(),
              ),
              SizedBox(height: m.spacingMd),

              // 各媒体库最新内容（每库一行 2:3 海报）
              librariesAsync.when(
                data: (libs) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final lib in libs)
                      Padding(
                        padding: EdgeInsets.only(bottom: m.spacingSm),
                        child: _TvLibraryLatestRow(library: lib),
                      ),
                  ],
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              SizedBox(height: m.spacingMd),

              // 合集（最底部）
              ref.watch(collectionsProvider).maybeWhen(
                    data: (cols) {
                      if (cols.isEmpty) return const SizedBox.shrink();
                      return TvRow(
                        title: '合集',
                        rowHeight: m.posterHeight2_3 + m.s(80),
                        cards: [
                          for (final c in cols)
                            TvMediaCard(
                              item: c,
                              onSelect: () => context.go(
                                  '/tv/library?libraryId=${c.id}&title=${Uri.encodeComponent(c.name)}'),
                            ),
                        ],
                      );
                    },
                    orElse: () => const SizedBox.shrink(),
                  ),
              SizedBox(height: m.spacingXxl),
            ],
          ),
        ),
      ),
    );
  }

  // ============ Hero ============

  Widget _buildHero(
      ApiClientFactory api, List<MediaItem> featured, TvMetrics m) {
    final index = _featuredIndex % featured.length;
    final item = featured[index];
    _ensureColor(api, item);

    final banner = resolveMediaItemBannerImageUrls(api, item,
        maxWidth: 1600, allowPosterFallback: true);
    final logo = (item.logoItemId != null && item.logoImageTag != null)
        ? api.image.getLogoImageUrl(item.logoItemId!,
            tag: item.logoImageTag, maxWidth: 360)
        : null;
    final fg = readableTextColorForBackground(_bgColor);
    // Hero 占屏高约 56%，贴近 10-foot 影院大图比例；小屏/Pad 收紧下限。
    final heroHeight =
        (MediaQuery.sizeOf(context).height * 0.56).clamp(360.0, 720.0);

    return SizedBox(
      height: heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 背景大图（切换精选时淡入）。
          if (banner.isNotEmpty)
            MediaImage(
              key: ValueKey(item.id),
              imageUrl: banner.first,
              imageUrls: banner.length > 1 ? banner.sublist(1) : null,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
            ).animate(key: ValueKey('bg_${item.id}')).fadeIn(
                duration: TvDesignTokens.contentFadeDuration)
          else
            const ColoredBox(color: TvDesignTokens.surfaceElevated),
          // 左侧 + 底部双向渐变，保证文字与按钮在任何图上都清晰。
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  _bgColor.withValues(alpha: 0.92),
                  _bgColor.withValues(alpha: 0.55),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.45, 0.85],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  _bgColor.withValues(alpha: 0.6),
                  _bgColor,
                ],
                stops: const [0.5, 0.85, 1.0],
              ),
            ),
          ),
          // 右上角系统时钟（TV 常驻信息）。
          Positioned(
            top: m.spacingMd,
            right: m.spacingXl,
            child: const _HomeClock(),
          ),
          // 文案 + 按钮（左下对齐，10-foot 常见布局）。
          Positioned(
            left: m.spacingXl,
            right: m.spacingXl,
            bottom: m.spacingLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '每日精选',
                  style: TextStyle(
                    fontSize: m.fontSizeXs,
                    color: TvDesignTokens.brandLight,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                  ),
                ),
                SizedBox(height: m.spacingXs),
                if (logo != null && logo.isNotEmpty)
                  Image.network(logo,
                      height: m.s(72),
                      fit: BoxFit.contain,
                      alignment: Alignment.centerLeft,
                      errorBuilder: (_, __, ___) => _heroTitle(item.name, m, fg))
                else
                  _heroTitle(item.name, m, fg),
                SizedBox(height: m.spacingSm),
                Row(
                  children: [
                    if (item.communityRating != null) ...[
                      RatingBadge(rating: item.communityRating, size: m.fs(16)),
                      SizedBox(width: m.spacingMd),
                    ],
                    if (item.productionYear != null) ...[
                      Text('${item.productionYear}',
                          style: TextStyle(
                              fontSize: m.fontSizeSm,
                              color: fg.withValues(alpha: 0.85))),
                      SizedBox(width: m.spacingMd),
                    ],
                    Expanded(
                      child: Wrap(
                        spacing: m.spacingSm,
                        runSpacing: m.spacingXs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ...?item.genres?.take(3).map((g) => TagBadge(text: g)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (item.overview != null && item.overview!.trim().isNotEmpty) ...[
                  SizedBox(height: m.spacingSm),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: m.s(720)),
                    child: Text(
                      item.overview!.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: m.fontSizeSm,
                        color: fg.withValues(alpha: 0.85),
                        height: TvDesignTokens.lineHeightNormal,
                      ),
                    ),
                  ),
                ],
                SizedBox(height: m.spacingMd),
                Row(
                  children: [
                    TvButton(
                      text: '播放',
                      icon: Icons.play_arrow,
                      autofocus: true,
                      onPressed: () => _heroPlay(item),
                    ),
                    SizedBox(width: m.spacingMd),
                    TvButton(
                      text: '详情',
                      icon: Icons.info_outline,
                      outlined: true,
                      onPressed: () => context.push('/tv/detail/${item.id}'),
                    ),
                    if (featured.length > 1) ...[
                      SizedBox(width: m.spacingMd),
                      TvButton(
                        text: '换一部',
                        icon: Icons.refresh,
                        outlined: true,
                        onPressed: () => setState(
                            () => _featuredIndex = index + 1),
                      ),
                    ],
                  ],
                ),
              ],
            ).animate(key: ValueKey('fg_${item.id}')).fadeIn(
                duration: TvDesignTokens.contentFadeDuration),
          ),
        ],
      ),
    );
  }

  void _heroPlay(MediaItem item) {
    // 剧集需选集，交给详情页的播放逻辑；影片直接进播放器。
    if (item.type == 'Series') {
      context.push('/tv/detail/${item.id}');
    } else {
      context.push('/tv/player?mediaId=${item.id}');
    }
  }

  Widget _heroTitle(String name, TvMetrics m, Color fg) => Text(
        name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: m.heroTitleSize,
          color: fg,
          fontWeight: FontWeight.w800,
          shadows: [
            Shadow(blurRadius: 8, color: Colors.black.withValues(alpha: 0.5)),
          ],
        ),
      );

  Widget _heroPlaceholder(TvMetrics m) {
    return Container(
      height: m.s(460),
      color: TvDesignTokens.surfaceElevated,
    ).animate(onPlay: (c) => c.repeat()).shimmer(
          duration: TvDesignTokens.shimmerDuration,
          color: Colors.white10,
        );
  }

  // ============ 辅助 ============

  String? _first(List<String> urls) => urls.isNotEmpty ? urls.first : null;

  String _continueTitle(MediaItem it) {
    if (it.type == 'Episode') {
      final s = it.seriesName?.trim();
      if (s != null && s.isNotEmpty) return s;
    }
    return it.name;
  }

  String? _continueSubtitle(MediaItem it) {
    if (it.type != 'Episode') return null;
    final parts = <String>[];
    if (it.parentIndexNumber != null) parts.add('第${it.parentIndexNumber}季');
    if (it.indexNumber != null) parts.add('第${it.indexNumber}集');
    if (it.name.trim().isNotEmpty) parts.add(it.name);
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String? _continueBadge(MediaItem it) {
    if (it.type != 'Episode') return null;
    final s = it.parentIndexNumber;
    final e = it.indexNumber;
    if (s == null && e == null) return null;
    final sb = StringBuffer();
    if (s != null) sb.write('S$s');
    if (e != null) sb.write('E$e');
    return sb.toString();
  }

  // ============ 占位 / 空态 ============

  Widget _rowPlaceholder(String title, TvMetrics m) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: m.spacingXl,
        vertical: m.spacingMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: m.fontSizeLg,
              color: TvDesignTokens.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: m.spacingMd),
          SizedBox(
            height: m.posterHeight16_9,
            child: Row(
              children: List.generate(
                4,
                (i) => Container(
                  width: m.posterWidth16_9,
                  height: m.posterHeight16_9,
                  margin: EdgeInsets.only(right: m.posterSpacing),
                  decoration: BoxDecoration(
                    color: TvDesignTokens.surfaceElevated,
                    borderRadius: BorderRadius.circular(m.posterRadius),
                  ),
                ),
              ),
            ),
          ).animate(onPlay: (c) => c.repeat()).shimmer(
                duration: TvDesignTokens.shimmerDuration,
                color: Colors.white10,
              ),
        ],
      ),
    );
  }

  Widget _buildEmptyServers(TvMetrics m) {
    return Scaffold(
      backgroundColor: TvDesignTokens.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dns_outlined,
              color: TvDesignTokens.textSecondary,
              size: m.s(96),
            ),
            SizedBox(height: m.spacingLg),
            Text(
              '还没有连接服务器',
              style: TextStyle(
                fontSize: m.fontSizeXl,
                color: TvDesignTokens.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: m.spacingSm),
            Text(
              '连接 Emby 服务器后即可浏览媒体库',
              style: TextStyle(
                fontSize: m.fontSizeSm,
                color: TvDesignTokens.textSecondary,
              ),
            ),
            SizedBox(height: m.spacingXl),
            // 首启无服务器时，除了手动添加，还要能扫码导入配置、进设置——
            // 否则遥控器只有一个按钮可去，批量导入无路可走。
            Wrap(
              spacing: m.spacingMd,
              runSpacing: m.spacingMd,
              alignment: WrapAlignment.center,
              children: [
                TvButton(
                  text: '添加服务器',
                  icon: Icons.add,
                  autofocus: true,
                  onPressed: () => context.go('/tv/server'),
                ),
                TvButton(
                  text: '手机扫码导入',
                  icon: Icons.qr_code_scanner,
                  outlined: true,
                  onPressed: () => context.go('/tv/scan'),
                ),
                TvButton(
                  text: '设置',
                  icon: Icons.settings,
                  outlined: true,
                  onPressed: () => context.go('/tv/settings'),
                ),
              ],
            ),
          ],
        ).animate().fadeIn(duration: TvDesignTokens.contentFadeDuration).moveY(
              begin: 12,
              end: 0,
              duration: TvDesignTokens.contentFadeDuration,
              curve: Curves.easeOut,
            ),
      ),
    );
  }
}

/// Hero 右上角时钟：HH:mm，随分钟更新（20s 轮询足够，省电）。
class _HomeClock extends StatefulWidget {
  const _HomeClock();

  @override
  State<_HomeClock> createState() => _HomeClockState();
}

class _HomeClockState extends State<_HomeClock> {
  late Timer _timer;
  late String _text = _now();

  static String _now() {
    final t = TimeOfDay.now();
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      final next = _now();
      if (mounted && next != _text) setState(() => _text = next);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.tv;
    return Text(
      _text,
      style: TextStyle(
        fontSize: m.fontSizeMd,
        color: Colors.white,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
        shadows: [Shadow(blurRadius: 6, color: Colors.black.withValues(alpha: 0.6))],
      ),
    );
  }
}

/// 单个媒体库的「最新内容」横向行（每库一行 2:3 海报）。
class _TvLibraryLatestRow extends ConsumerWidget {
  final Library library;

  const _TvLibraryLatestRow({required this.library});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = context.tv;
    final latestAsync = ref.watch(latestItemsProvider(library.id));

    return latestAsync.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return TvRow(
          title: library.name,
          rowHeight: m.posterHeight2_3 + m.s(80),
          onSeeAll: () => context.go('/tv/library?libraryId=${library.id}'),
          cards: [
            for (final it in items)
              TvMediaCard(
                item: it,
                onSelect: () => context.push('/tv/detail/${it.id}'),
              ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
