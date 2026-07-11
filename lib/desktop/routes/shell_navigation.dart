import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// 从「壳外命令式 push 的页」安全切回某个一级 Tab（StatefulShellRoute 分支）。
///
/// 为什么不能只 `context.go('/x')`：命令式 `context.push` 压在壳之上的顶级页，会让 go
/// **既不清压栈页、也不复位 shell 分支索引** → 回到壳还停在原分支（如"服务器"）。更坑的是
/// go 已把 location 改成目标（如 '/'），此后侧栏 Home=`goBranch(0)` 因「目标 location 与
/// 当前 location 相同」被 go_router 当作无变化而**静默失效** → 首页按钮从此按不动（需先去别的
/// Tab 再回来才好）。这正是「做了服务器页操作后回不了首页」的根因。
///
/// 正解：先捕获 router，再 `rootNavigator.popUntil(isFirst)` 弹掉所有压栈页回到壳，最后
/// `go(location)` 切到目标分支。⚠️**先捕获 router 再 pop**——pop 后本页 context 可能已失效。
/// 与 desktop_add_server_screen 的 `_returnToHomeAfterAdd` 同一套路，抽出来给各源登录/删除等
/// 「壳外页返回一级 Tab」复用。
void returnToShellRoute(BuildContext context, String location) {
  final router = GoRouter.of(context);
  Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
  router.go(location);
}
