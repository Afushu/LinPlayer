import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/ranking/ranking_models.dart';
import '../../../core/providers/ranking_providers.dart';
import '../../../core/widgets/app_shimmer.dart';
import '../../../ui/widgets/common/media_widgets.dart';
import '../../../ui/widgets/common/ranking_entry_panel.dart';
import '../../theme/tv_design_tokens.dart';
import '../../theme/tv_metrics.dart';
import '../../widgets/tv_focusable.dart';
import '../../widgets/tv_grid.dart';

/// TV 排行榜（观感对齐移动端）：顶部一级分组胶囊 + 子类胶囊，下方名次列表。
/// 前三名金/银/铜大号名次 + 封面 + 评分。交互全部换成遥控器焦点驱动，
/// 选中条目弹出跨服务器查找面板。
class TvRankingsScreen extends ConsumerStatefulWidget {
  const TvRankingsScreen({super.key});

  @override
  ConsumerState<TvRankingsScreen> createState() => _TvRankingsScreenState();
}

class _TvRankingsScreenState extends ConsumerState<TvRankingsScreen> {
  RankingGroup? _group;
  String? _categoryId;

  @override
  Widget build(BuildContext context) {
    final m = context.tv;
    final groups = ref.watch(rankingGroupsProvider);

    if (groups.isEmpty) {
      return Scaffold(
        backgroundColor: TvDesignTokens.background,
        body: _emptyState(m, Icons.leaderboard_outlined, '当前版本未配置排行榜数据源'),
      );
    }

    final group = groups.contains(_group) ? _group! : groups.first;
    final categories = ref.watch(rankingCategoriesProvider(group));
    final categoryId = categories.any((c) => c.id == _categoryId)
        ? _categoryId!
        : (categories.isNotEmpty ? categories.first.id : '');

    return Scaffold(
      backgroundColor: TvDesignTokens.background,
      body: Padding(
        padding: EdgeInsets.fromLTRB(m.spacingXl, m.spacingXl, m.spacingXl, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('排行榜',
                style: TextStyle(
                  fontSize: m.fontSizeXxl,
                  color: TvDesignTokens.textPrimary,
                  fontWeight: FontWeight.bold,
                )),
            SizedBox(height: m.spacingLg),
            // 一级分组胶囊
            Wrap(
              children: [
                for (final g in groups)
                  _pill(
                    m,
                    g.label,
                    g == group,
                    autofocus: g == groups.first,
                    onSelect: () => setState(() {
                      _group = g;
                      _categoryId = null;
                    }),
                  ),
              ],
            ),
            SizedBox(height: m.spacingSm),
            // 子类胶囊（横向滚动）
            if (categories.isNotEmpty)
              SizedBox(
                height: m.s(72),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length,
                  itemBuilder: (_, i) {
                    final c = categories[i];
                    return _chip(m, c.label, c.id == categoryId,
                        onSelect: () => setState(() => _categoryId = c.id));
                  },
                ),
              ),
            SizedBox(height: m.spacingSm),
            Expanded(
              child: categoryId.isEmpty
                  ? _emptyState(m, Icons.inbox_outlined, '暂无榜单')
                  : _RankingList(categoryId: categoryId),
            ),
          ],
        ),
      ),
    );
  }
}

/// 名次列表（复用移动端行结构：名次 + 封面 + 标题/副标题 + 评分）。
class _RankingList extends ConsumerWidget {
  const _RankingList({required this.categoryId});

  final String categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = context.tv;
    final async = ref.watch(rankingListProvider(categoryId));
    return async.when(
      loading: () => ListView.builder(
        itemCount: 8,
        itemBuilder: (_, __) => Padding(
          padding: EdgeInsets.symmetric(
              vertical: m.spacingSm, horizontal: m.spacingSm),
          child: _SkeletonRow(m: m),
        ),
      ),
      error: (_, __) => _emptyState(m, Icons.wifi_off_rounded, '加载失败'),
      data: (items) {
        if (items.isEmpty) {
          return _emptyState(m, Icons.inbox_outlined, '暂无数据');
        }
        final top = items.take(3).toList();
        final rest =
            items.length > 3 ? items.sublist(3) : const <RankingEntry>[];
        return SingleChildScrollView(
          padding: EdgeInsets.only(bottom: m.spacingXl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Podium(top: top),
              if (rest.isNotEmpty) ...[
                SizedBox(height: m.spacingLg),
                TvResponsiveGrid(
                  minCellWidth: 640,
                  children: [
                    for (final e in rest) _RankRow(entry: e),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.entry});

  final RankingEntry entry;

  @override
  Widget build(BuildContext context) {
    final m = context.tv;
    return TvFocusable(
      onSelect: () => showRankingEntryDialog(context, entry),
      padding:
          EdgeInsets.symmetric(vertical: m.spacingXs, horizontal: m.spacingSm),
      child: Container(
        padding: EdgeInsets.all(m.spacingMd),
        decoration: BoxDecoration(
          color: TvDesignTokens.surface,
          borderRadius: BorderRadius.circular(m.posterRadius),
        ),
        child: Row(
          children: [
            SizedBox(
              width: m.s(46),
              child: Text(
                '${entry.rank}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: entry.rank <= 3 ? m.fontSizeXl : m.fontSizeLg,
                  fontWeight: FontWeight.w800,
                  fontStyle: FontStyle.italic,
                  color: _rankColor(entry.rank) ?? TvDesignTokens.textSecondary,
                ),
              ),
            ),
            SizedBox(width: m.spacingSm),
            ClipRRect(
              borderRadius: BorderRadius.circular(m.s(6)),
              child: MediaImage(
                imageUrl: entry.imageUrl,
                width: m.s(64),
                height: m.s(90),
                fit: BoxFit.cover,
                cacheWidth: 180,
              ),
            ),
            SizedBox(width: m.spacingMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: m.fontSizeMd,
                      color: TvDesignTokens.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if ((entry.subtitle ?? '').isNotEmpty) ...[
                    SizedBox(height: m.spacingXs),
                    Text(
                      entry.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: m.fontSizeSm,
                        color: TvDesignTokens.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (entry.rating != null && entry.rating! > 0) ...[
              SizedBox(width: m.spacingSm),
              _ratingChip(m, entry.rating!),
            ],
          ],
        ),
      ),
    );
  }
}

/// 前三名领奖台：亚军-冠军-季军三列，冠军居中最高、品牌色高亮。
/// 兼容不足 3 条（0/1/2）的榜单。
class _Podium extends StatelessWidget {
  const _Podium({required this.top});

  /// 已按名次升序，index 0 = 第 1 名（长度 1~3）。
  final List<RankingEntry> top;

  @override
  Widget build(BuildContext context) {
    final m = context.tv;
    final rank1 = top[0];
    final rank2 = top.length > 1 ? top[1] : null;
    final rank3 = top.length > 2 ? top[2] : null;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: m.spacingMd),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (rank2 != null) _PodiumCard(entry: rank2, big: false),
          _PodiumCard(entry: rank1, big: true, autofocus: true),
          if (rank3 != null) _PodiumCard(entry: rank3, big: false),
        ],
      ),
    );
  }
}

class _PodiumCard extends StatelessWidget {
  const _PodiumCard({
    required this.entry,
    required this.big,
    this.autofocus = false,
  });

  final RankingEntry entry;
  final bool big;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final m = context.tv;
    final w = m.s(big ? 210 : 168);
    final h = m.s(big ? 294 : 236);
    final highlight = entry.rank == 1;
    final accent = _rankColor(entry.rank) ?? TvDesignTokens.textSecondary;
    return TvFocusable(
      autofocus: autofocus,
      onSelect: () => showRankingEntryDialog(context, entry),
      padding: EdgeInsets.all(m.spacingSm),
      child: SizedBox(
        width: w,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${entry.rank}',
              style: TextStyle(
                fontSize: big ? m.fontSizeXxl : m.fontSizeXl,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                color: accent,
              ),
            ),
            SizedBox(height: m.spacingSm),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(m.s(10)),
                border: highlight
                    ? Border.all(color: TvDesignTokens.brand, width: m.s(3))
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(m.s(8)),
                child: MediaImage(
                  imageUrl: entry.imageUrl,
                  width: w,
                  height: h,
                  fit: BoxFit.cover,
                  cacheWidth: big ? 420 : 340,
                ),
              ),
            ),
            SizedBox(height: m.spacingSm),
            Text(
              entry.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: m.fontSizeMd,
                color: highlight
                    ? TvDesignTokens.brand
                    : TvDesignTokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (entry.rating != null && entry.rating! > 0) ...[
              SizedBox(height: m.spacingXs),
              _ratingChip(m, entry.rating!),
            ],
          ],
        ),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.m});

  final TvMetrics m;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: m.spacingSm),
      child: Row(
        children: [
          SizedBox(width: m.s(46)),
          ShimmerBox(
              width: m.s(64),
              height: m.s(90),
              borderRadius: BorderRadius.circular(m.s(6))),
          SizedBox(width: m.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(
                    width: m.s(220),
                    height: m.s(18),
                    borderRadius: BorderRadius.circular(m.s(4))),
                SizedBox(height: m.spacingSm),
                ShimmerBox(
                    width: m.s(120),
                    height: m.s(14),
                    borderRadius: BorderRadius.circular(m.s(4))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============ 复用小部件 ============

/// 一级分组胶囊（对齐移动端 _GroupBar）。
Widget _pill(
  TvMetrics m,
  String label,
  bool active, {
  required VoidCallback onSelect,
  bool autofocus = false,
}) {
  return TvFocusable(
    autofocus: autofocus,
    onSelect: onSelect,
    padding: EdgeInsets.all(m.spacingXs),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding:
          EdgeInsets.symmetric(horizontal: m.spacingLg, vertical: m.spacingSm),
      decoration: BoxDecoration(
        color: active ? TvDesignTokens.brand : TvDesignTokens.surface,
        borderRadius: BorderRadius.circular(m.s(22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: m.fontSizeMd,
          color: active ? Colors.white : TvDesignTokens.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

/// 子类胶囊（对齐移动端 _CategoryBar 的 ChoiceChip）。
Widget _chip(
  TvMetrics m,
  String label,
  bool active, {
  required VoidCallback onSelect,
}) {
  return TvFocusable(
    onSelect: onSelect,
    padding: EdgeInsets.all(m.spacingXs),
    child: Container(
      padding:
          EdgeInsets.symmetric(horizontal: m.spacingMd, vertical: m.spacingXs),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? TvDesignTokens.brand : TvDesignTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(m.s(18)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: m.fontSizeSm,
          color: active ? Colors.white : TvDesignTokens.textPrimary,
        ),
      ),
    ),
  );
}

/// 评分徽标（对齐移动端 _RatingChip）。
Widget _ratingChip(TvMetrics m, double rating) {
  return Container(
    padding:
        EdgeInsets.symmetric(horizontal: m.spacingSm, vertical: m.spacingXs),
    decoration: BoxDecoration(
      color: const Color(0xFFFFB300).withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(m.s(8)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: m.s(18), color: const Color(0xFFFFB300)),
        SizedBox(width: m.s(3)),
        Text(
          rating.toStringAsFixed(1),
          style: TextStyle(
            fontSize: m.fontSizeSm,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFFFA000),
          ),
        ),
      ],
    ),
  );
}

Widget _emptyState(TvMetrics m, IconData icon, String text) {
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: m.s(72), color: TvDesignTokens.textSecondary),
        SizedBox(height: m.spacingMd),
        Text(text,
            style: TextStyle(
                fontSize: m.fontSizeMd, color: TvDesignTokens.textSecondary)),
      ],
    ),
  );
}

/// 前三名金/银/铜；其余返回 null（用默认色）。
Color? _rankColor(int rank) => switch (rank) {
      1 => const Color(0xFFFFC107),
      2 => const Color(0xFFB0BEC5),
      3 => const Color(0xFFCD7F32),
      _ => null,
    };
