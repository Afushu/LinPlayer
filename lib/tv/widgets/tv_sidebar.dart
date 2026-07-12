import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/ranking_providers.dart';
import '../theme/tv_design_tokens.dart';
import '../theme/tv_metrics.dart';
import 'tv_focusable.dart';

/// TV 左侧导航栏（紧凑竖排轨道）
///
/// 每个 Tab 是「图标在上、文字在下」的竖排块，整块铺满轨道宽度 —— 既是 10-foot UI
/// 的常见形态，又给触控留出足够大的点击热区（旧版是居中的窄药丸，Pad 上难点中）。
/// 固定项：首页、搜索、收藏、服务器、扫码、设置（+ 排行榜按开关显隐，末位对齐路由）。
class TvSidebar extends ConsumerStatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final bool collapsed;

  const TvSidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    this.collapsed = false,
  });

  @override
  ConsumerState<TvSidebar> createState() => _TvSidebarState();
}

class _TvSidebarState extends ConsumerState<TvSidebar> {
  static const List<_NavItem> _baseItems = [
    _NavItem(Icons.home_rounded, '首页'),
    _NavItem(Icons.search_rounded, '搜索'),
    _NavItem(Icons.favorite_rounded, '收藏'),
    _NavItem(Icons.storage_rounded, '服务器'),
    _NavItem(Icons.qr_code_scanner_rounded, '扫码'),
    _NavItem(Icons.settings_rounded, '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final m = context.tv;
    // 排行榜作为末位项（index 6），与 tv_router / tv_shell 的 _routes 对齐。
    final items = <_NavItem>[
      ..._baseItems,
      if (ref.watch(rankingEnabledProvider))
        const _NavItem(Icons.leaderboard_rounded, '排行榜'),
    ];
    // 竖排图标+文字本身就窄，不再需要 240 宽的抽屉；折叠态更窄只留图标。
    final width = widget.collapsed ? m.s(84) : m.s(120);

    return Container(
      width: width,
      color: TvDesignTokens.surface,
      child: SafeArea(
        right: false,
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(vertical: m.spacingMd),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(items.length, (index) {
                return _buildItem(m, items[index], index);
              }),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(TvMetrics m, _NavItem item, int index) {
    final isSelected = widget.selectedIndex == index;
    final Color fg = isSelected
        ? TvDesignTokens.brand
        : TvDesignTokens.textSecondary;

    return TvFocusable(
      // 不 autofocus：初始焦点交给内容区（Hero/首卡/按钮），
      // 避免与内容 autofocus 抢焦点导致「光标落在看不见的地方」。
      onSelect: () => widget.onItemSelected(index),
      padding: EdgeInsets.symmetric(
        horizontal: m.s(8),
        vertical: m.s(5),
      ),
      borderRadius: m.s(14),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: m.spacingSm),
        decoration: BoxDecoration(
          color: isSelected
              ? TvDesignTokens.brand.withValues(alpha: 0.15)
              : null,
          borderRadius: BorderRadius.circular(m.s(14)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, color: fg, size: m.sidebarIconSize),
            if (!widget.collapsed) ...[
              SizedBox(height: m.s(6)),
              Text(
                item.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: m.fs(13),
                  color: fg,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;

  const _NavItem(this.icon, this.label);
}
