import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/providers/media_providers.dart';
import '../../../core/widgets/app_shimmer.dart';
import '../../../ui/utils/media_helpers.dart';
import '../../../ui/widgets/common/media_widgets.dart';
import '../../theme/tv_design_tokens.dart';
import '../../theme/tv_metrics.dart';
import '../../widgets/tv_focusable.dart';

/// TV 收藏页 —— 2:3 海报网格（真实数据），点开进详情页取消/管理收藏。
class TvFavoritesScreen extends ConsumerWidget {
  const TvFavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = context.tv;
    final favoritesAsync = ref.watch(favoriteItemsProvider);
    final api = ref.read(apiClientProvider);

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
            SizedBox(height: m.spacingLg),
            Expanded(
              child: favoritesAsync.when(
                data: (items) {
                  if (items.isEmpty) {
                    return _centerHint(m, '还没有收藏内容，在详情页点收藏后会同步到这里');
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
                      final urls =
                          resolveMediaItemImageUrls(api, item, maxWidth: 360);
                      return TvFocusable(
                        autofocus: index == 0,
                        padding: EdgeInsets.all(m.s(6)),
                        onSelect: () => context.push('/tv/detail/${item.id}'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(m.posterRadius),
                                child: urls.isNotEmpty
                                    ? MediaImage(
                                        imageUrl: urls.first,
                                        imageUrls: urls.length > 1
                                            ? urls.sublist(1)
                                            : null,
                                        width: double.infinity,
                                        height: double.infinity,
                                        fit: BoxFit.cover,
                                      )
                                    : ColoredBox(
                                        color: TvDesignTokens.surfaceElevated,
                                        child: Icon(Icons.movie_outlined,
                                            color: TvDesignTokens.textDisabled,
                                            size: m.s(40)),
                                      ),
                              ),
                            ),
                            SizedBox(height: m.spacingXs),
                            Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: m.fontSizeXs,
                                color: TvDesignTokens.textPrimary,
                              ),
                            ),
                          ],
                        ),
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
