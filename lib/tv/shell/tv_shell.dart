import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/tv_design_tokens.dart';
import '../widgets/tv_sidebar.dart';

/// TV Shell
/// 左侧导航栏 + 右侧内容区。
///
/// 焦点：侧边栏与内容各自是一个 FocusTraversalGroup，方向键左右在两组之间自然跳转。
/// 关键——不再用「裸 Focus 包一层」：那种包裹自身可聚焦却没有任何高亮，
/// 会把焦点吞到一个看不见的节点上（表现为「光标不见了 / 完全动不了」）。
class TvShell extends StatelessWidget {
  final Widget child;
  final int selectedIndex;

  const TvShell({
    super.key,
    required this.child,
    required this.selectedIndex,
  });

  static const List<String> _routes = [
    '/tv/home',
    '/tv/search',
    '/tv/favorites',
    '/tv/server',
    '/tv/scan',
    '/tv/settings',
    '/tv/rankings',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TvDesignTokens.background,
      body: Row(
        children: [
          // 左侧导航栏（独立遍历组）
          FocusTraversalGroup(
            child: TvSidebar(
              selectedIndex: selectedIndex,
              onItemSelected: (index) => _navigateToPage(context, index),
            ),
          ),
          // 右侧内容区（独立遍历组）
          Expanded(
            child: FocusTraversalGroup(child: child),
          ),
        ],
      ),
    );
  }

  void _navigateToPage(BuildContext context, int index) {
    if (index >= 0 && index < _routes.length) {
      context.go(_routes[index]);
    }
  }
}
