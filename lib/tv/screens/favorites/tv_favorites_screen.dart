import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_interfaces.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/media_providers.dart';
import '../../../core/widgets/app_shimmer.dart';
import '../../theme/tv_design_tokens.dart';
import '../../theme/tv_metrics.dart';
import '../../widgets/tv_media_card.dart';
import '../../widgets/tv_panel.dart';
import '../../widgets/tv_toast.dart';

/// TV 收藏页 —— 2:3 海报网格（对齐移动端 [FavoritesScreen]）。
/// 确认键进详情；遥控器「菜单键」/ 长按弹确认框移除收藏。
class TvFavoritesScreen extends ConsumerWidget {
  const TvFavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = context.tv;
    final favoritesAsync = ref.watch(favoriteItemsProvider);

    return Scaffold(
      backgroundColor: TvDesignTokens.background,
      body: Padding(
        padding: EdgeInsets.all(m.spacingXl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '收藏',
              style: TextStyle(
                fontSize: m.fontSizeXxl,
                color: TvDesignTokens.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: m.spacingXs),
            Text(
              '菜单键 / 长按可移除收藏',
              style: TextStyle(
                fontSize: m.fontSizeXs,
                color: TvDesignTokens.textSecondary,
              ),
            ),
            SizedBox(height: m.spacingLg),
            Expanded(
              child: favoritesAsync.when(
                data: (items) {
                  if (items.isEmpty) {
                    return _emptyState(m);
                  }
                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: m.posterWidth2_3,
                      childAspectRatio: 2 / 3.4,
                      crossAxisSpacing: m.posterSpacing,
                      mainAxisSpacing: m.posterSpacing,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return TvMediaCard(
                        item: item,
                        autofocus: index == 0,
                        onSelect: () => context.push('/tv/detail/${item.id}'),
                        onLongPress: () => _confirmRemove(context, ref, item),
                      ).animate().fadeIn(
                            delay: Duration(milliseconds: 12 * (index % 6)),
                            duration: TvDesignTokens.contentFadeDuration,
                          );
                    },
                  );
                },
                loading: () => const Center(
                    child: AppLoadingIndicator(
                        size: 48, color: TvDesignTokens.brand)),
                error: (e, _) => _centerHint(m, '加载收藏失败：$e'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(
      BuildContext context, WidgetRef ref, MediaItem item) async {
    final ok = await showTvConfirm(
      context,
      title: '移除收藏',
      message: '确定从收藏移除“${item.name}”吗？',
      confirmLabel: '移除',
      danger: true,
    );
    if (!ok) return;
    try {
      final api = ref.read(apiClientProvider);
      await api.favorite.removeFavorite(item.id);
      refreshFavorites(ref);
      ref.invalidate(mediaItemProvider(item.id));
      if (context.mounted) TvToast.show(context, '已从收藏移除 ${item.name}');
    } catch (error) {
      if (context.mounted) TvToast.show(context, '移除收藏失败：$error');
    }
  }

  Widget _emptyState(TvMetrics m) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite_border_rounded,
              size: m.s(68), color: TvDesignTokens.textDisabled),
          SizedBox(height: m.spacingMd),
          Text(
            '还没有收藏内容',
            style: TextStyle(
              fontSize: m.fontSizeLg,
              color: TvDesignTokens.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: m.spacingSm),
          Text(
            '在首页或详情页点击收藏后，这里会立即同步显示',
            style: TextStyle(
              fontSize: m.fontSizeSm,
              color: TvDesignTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _centerHint(TvMetrics m, String text) {
    return Center(
      child: Text(
        text,
        style: TextStyle(
          color: TvDesignTokens.textSecondary,
          fontSize: m.fontSizeMd,
        ),
      ),
    );
  }
}
