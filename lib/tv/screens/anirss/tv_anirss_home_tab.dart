import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/server_providers.dart';
import '../../../core/sources/anirss/anirss_nav_args.dart';
import '../../../core/sources/anirss/anirss_providers.dart';
import '../../../core/sources/anirss/models/ani.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/widgets/app_shimmer.dart';
import '../../../ui/widgets/anirss/ani_poster_card.dart';
import '../../theme/tv_design_tokens.dart';
import '../../theme/tv_metrics.dart';
import '../../widgets/tv_focusable.dart';

/// Ani-rss 首页 Tab（TV）：番剧海报墙网格。复用移动端 [AniPosterCard] 视觉，
/// 外套 [TvFocusable] 提供遥控器焦点放大与高亮（观感与移动端一致，交互焦点驱动）。
class TvAniRssHomeTab extends ConsumerStatefulWidget {
  const TvAniRssHomeTab({super.key});

  @override
  ConsumerState<TvAniRssHomeTab> createState() => _TvAniRssHomeTabState();
}

class _TvAniRssHomeTabState extends ConsumerState<TvAniRssHomeTab> {
  // 已播放过入场动效的订阅 id：回滑到已加载项不再重复渐显。
  final Set<String> _seen = {};

  @override
  Widget build(BuildContext context) {
    final m = context.tv;
    final asyncList = ref.watch(aniListProvider);
    return asyncList.when(
      loading: () => const Center(
          child: AppLoadingIndicator(size: 48, color: TvDesignTokens.brand)),
      error: (e, _) => _centerHint(m, '加载失败：$e'),
      data: (list) {
        if (list.isEmpty) {
          return _centerHint(m, '暂无订阅，去「订阅」页添加番剧');
        }
        // 海报放大约 50%，纵横比留足两行标题 + 副标题（对齐移动端海报卡）。
        final double maxExtent = m.posterWidth2_3 * 1.5;
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxExtent,
            childAspectRatio: 0.52,
            crossAxisSpacing: m.posterSpacing,
            mainAxisSpacing: m.posterSpacing,
          ),
          itemCount: list.length,
          itemBuilder: (context, index) {
            final ani = list[index];
            final tile = TvFocusable(
              padding: EdgeInsets.all(m.s(6)),
              onSelect: () => _openDetail(context, ref, ani),
              child: AniPosterCard(
                imageUrls: [if (ani.image != null) ani.image!],
                title: ani.title,
                rating: ani.rating,
                subtitle: _episodeLabel(ani),
                badge: ani.enable ? null : '未启用',
                badgeMuted: !ani.enable,
                onTap: null, // 交互交给 TvFocusable
              ),
            );
            return entranceOnce(
              id: ani.id,
              index: index,
              seen: _seen,
              child: tile,
            );
          },
        );
      },
    );
  }

  static String? _episodeLabel(AniModel ani) {
    final cur = ani.currentEpisodeNumber;
    final total = ani.totalEpisodeNumber;
    if (cur != null && total != null && total > 0) return '$cur / $total 集';
    if (cur != null && cur > 0) return '更新至 $cur 集';
    return null;
  }

  void _openDetail(BuildContext context, WidgetRef ref, AniModel ani) {
    final server = ref.read(currentServerProvider);
    if (server == null) return;
    context.push('/tv/anirss-detail',
        extra: AniRssDetailArgs(server: server, ani: ani));
  }

  Widget _centerHint(TvMetrics m, String text) => Center(
        child: Text(
          text,
          style: TextStyle(
            color: TvDesignTokens.textSecondary,
            fontSize: m.fontSizeMd,
          ),
        ),
      );
}
