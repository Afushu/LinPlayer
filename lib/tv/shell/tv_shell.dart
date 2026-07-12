import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/tv_design_tokens.dart';
import '../widgets/tv_sidebar.dart';

/// TV Shell
/// 左侧导航栏 + 右侧内容区。
///
/// 焦点：侧边栏与内容各自是一个 [FocusScope] + [FocusTraversalGroup]。方向键在组内
/// 正常移动；到达边界时由 [_EdgeEscape] 显式跨组：
/// - 内容区最左边界按「←」→ 跳到侧栏（修复遥控器「Tab 栏怎么都按不过去」）。
/// - 侧栏按「→」→ 返回内容区。
///
/// 为什么要显式跨组：Flutter 的方向遍历按几何「就近」找目标，当内容焦点被滚到很下面、
/// 或落在很高的 Hero 上时，侧栏项与它不在同一垂直带里 → 「←」找不到目标 → 焦点卡死在
/// 内容区。显式边界跳转彻底绕开这个「垂直带错位」问题。
class TvShell extends StatefulWidget {
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
  State<TvShell> createState() => _TvShellState();
}

class _TvShellState extends State<TvShell> {
  final FocusScopeNode _sidebarScope = FocusScopeNode(debugLabel: 'tvSidebar');
  final FocusScopeNode _contentScope = FocusScopeNode(debugLabel: 'tvContent');

  @override
  void dispose() {
    _sidebarScope.dispose();
    _contentScope.dispose();
    super.dispose();
  }

  void _focusSidebar() => _focusScope(_sidebarScope);
  void _focusContent() => _focusScope(_contentScope);

  /// 把焦点交给某个作用域：优先恢复它上次的焦点子项，否则落到第一个可聚焦项。
  void _focusScope(FocusScopeNode scope) {
    final child = scope.focusedChild;
    if (child != null) {
      child.requestFocus();
    } else {
      scope.requestFocus();
      scope.nextFocus(); // 从作用域自身移动到第一个子项
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TvDesignTokens.background,
      body: Row(
        children: [
          // 左侧导航栏：到达右边界「→」返回内容区。
          FocusTraversalGroup(
            child: FocusScope(
              node: _sidebarScope,
              child: _EdgeEscape(
                onEscapeRight: _focusContent,
                child: TvSidebar(
                  selectedIndex: widget.selectedIndex,
                  onItemSelected: (index) => _navigateToPage(context, index),
                ),
              ),
            ),
          ),
          // 右侧内容区：到达左边界「←」跳到侧栏。
          Expanded(
            child: FocusTraversalGroup(
              child: FocusScope(
                node: _contentScope,
                child: _EdgeEscape(
                  onEscapeLeft: _focusSidebar,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToPage(BuildContext context, int index) {
    if (index >= 0 && index < TvShell._routes.length) {
      context.go(TvShell._routes[index]);
    }
  }
}

/// 覆写子树内的方向导航：正常在组内移动焦点；当某方向到达边界（组内已无目标）时，
/// 触发对应的越界回调，把焦点交给相邻的作用域。其它方向沿用默认行为。
class _EdgeEscape extends StatelessWidget {
  final Widget child;
  final VoidCallback? onEscapeLeft;
  final VoidCallback? onEscapeRight;

  const _EdgeEscape({
    required this.child,
    this.onEscapeLeft,
    this.onEscapeRight,
  });

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        DirectionalFocusIntent: _EdgeEscapeAction(
          onEscapeLeft: onEscapeLeft,
          onEscapeRight: onEscapeRight,
        ),
      },
      child: child,
    );
  }
}

class _EdgeEscapeAction extends Action<DirectionalFocusIntent> {
  _EdgeEscapeAction({this.onEscapeLeft, this.onEscapeRight});

  final VoidCallback? onEscapeLeft;
  final VoidCallback? onEscapeRight;

  @override
  void invoke(DirectionalFocusIntent intent) {
    final node = primaryFocus;
    // 先按默认行为在当前组内移动焦点。
    final moved = node?.focusInDirection(intent.direction) ?? false;
    if (moved) return;
    // 组内已到边界：按方向跨组。
    switch (intent.direction) {
      case TraversalDirection.left:
        onEscapeLeft?.call();
        break;
      case TraversalDirection.right:
        onEscapeRight?.call();
        break;
      case TraversalDirection.up:
      case TraversalDirection.down:
        break;
    }
  }
}
