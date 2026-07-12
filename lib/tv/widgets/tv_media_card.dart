import 'package:flutter/material.dart';

import '../../core/api/api_interfaces.dart';
import '../../ui/widgets/common/media_widgets.dart';
import '../theme/tv_design_tokens.dart';
import '../theme/tv_metrics.dart';
import 'tv_focusable.dart';

/// TV 端标准可聚焦海报卡：复用移动端 [MediaPoster] 的观感（2:3 海报 + 已看勾选 +
/// 未看集数角标 + 标题/年份/评分），外套 [TvFocusable] 提供遥控器焦点放大与高亮。
///
/// 这是把「移动端 UI」搬到 TV 的核心桥：视觉沿用移动端组件，交互换成焦点驱动。
class TvMediaCard extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onSelect;
  /// 次级动作（遥控器菜单键 / 平板长按）：如收藏页「移除收藏」确认。
  final VoidCallback? onLongPress;
  final double? width;
  final double? height;
  final bool autofocus;

  const TvMediaCard({
    super.key,
    required this.item,
    required this.onSelect,
    this.onLongPress,
    this.width,
    this.height,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.tv;
    return TvFocusable(
      autofocus: autofocus,
      onSelect: onSelect,
      onLongPress: onLongPress,
      padding: EdgeInsets.all(m.spacingSm),
      child: MediaPoster(
        item: item,
        width: width ?? m.posterWidth2_3,
        height: height ?? m.posterHeight2_3,
        onTap: null, // 交互交给 TvFocusable
      ),
    );
  }
}

/// TV 端横向（16:9）卡片：继续观看等场景用。复用 [MediaImage] 的加载/兜底管线，
/// 叠加进度条 + SxEx 角标 + 标题/副标题，观感对齐移动端继续观看卡。
class TvLandscapeCard extends StatelessWidget {
  final String? imageUrl;
  final String title;
  final String? subtitle;
  final String? badge;
  final double? progress;
  final VoidCallback onSelect;
  final bool autofocus;

  const TvLandscapeCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.onSelect,
    this.subtitle,
    this.badge,
    this.progress,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.tv;
    final w = m.posterWidth16_9;
    final h = m.posterHeight16_9;
    final radius = BorderRadius.circular(m.posterRadius);
    return TvFocusable(
      autofocus: autofocus,
      onSelect: onSelect,
      padding: EdgeInsets.all(m.spacingSm),
      child: SizedBox(
        width: w,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: radius,
              child: Stack(
                children: [
                  MediaImage(
                    imageUrl: imageUrl,
                    width: w,
                    height: h,
                    fit: BoxFit.cover,
                    borderRadius: radius,
                  ),
                  if (badge != null && badge!.isNotEmpty)
                    Positioned(
                      top: m.spacingXs,
                      right: m.spacingXs,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: m.spacingSm,
                          vertical: m.spacingXs / 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(m.spacingXs),
                        ),
                        child: Text(
                          badge!,
                          style: TextStyle(
                            fontSize: m.fontSizeXs,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  if (progress != null && progress! > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progress!.clamp(0.0, 1.0),
                        minHeight: m.s(3),
                        backgroundColor: Colors.black.withValues(alpha: 0.4),
                        valueColor: const AlwaysStoppedAnimation(
                          TvDesignTokens.brand,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(height: m.spacingXs),
            SizedBox(
              width: w,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: m.fontSizeSm,
                  color: TvDesignTokens.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (subtitle != null && subtitle!.isNotEmpty)
              SizedBox(
                width: w,
                child: Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: m.fontSizeXs,
                    color: TvDesignTokens.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// TV 端小节标题：对齐移动端 SectionHeader（大标题 + 可选「查看全部」），
/// 但「查看全部」是可聚焦项，遥控器上移即可选中。
class TvSectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;

  const TvSectionHeader({super.key, required this.title, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    final m = context.tv;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        m.spacingXl,
        m.spacingMd,
        m.spacingXl,
        m.spacingSm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: m.fontSizeLg,
              color: TvDesignTokens.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (onSeeAll != null)
            TvFocusable(
              onSelect: onSeeAll!,
              padding: EdgeInsets.symmetric(
                horizontal: m.spacingSm,
                vertical: m.spacingXs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '查看全部',
                    style: TextStyle(
                      fontSize: m.fontSizeSm,
                      color: TvDesignTokens.brand,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: m.s(18),
                    color: TvDesignTokens.brand,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// TV 端横向内容行：小节标题 + 一排横向滚动的卡片。焦点右移时 ListView 自动滚动。
class TvRow extends StatelessWidget {
  final String title;
  final List<Widget> cards;
  final VoidCallback? onSeeAll;
  final double? rowHeight;

  const TvRow({
    super.key,
    required this.title,
    required this.cards,
    this.onSeeAll,
    this.rowHeight,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.tv;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TvSectionHeader(title: title, onSeeAll: onSeeAll),
        SizedBox(
          height: rowHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: m.spacingLg),
            itemCount: cards.length,
            itemBuilder: (_, i) => cards[i],
          ),
        ),
      ],
    );
  }
}
