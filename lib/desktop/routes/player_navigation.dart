import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// 打开桌面播放页的统一入口，对**同一目标**做导航去重防抖。
///
/// 修「双声音」根因：短时间内对同一 `/player/...` 目标的重复 push（手抖双击、
/// 事件重复触发、控件重建重发）会挂起两个 DesktopPlayerScreen → 两个 mpv 实例
/// 同时解同一文件 → 两份音轨，且暂停只停住其一，另一个成孤儿继续出声。
/// 1 秒内对**完全相同 location** 的重复导航直接忽略；不同集/不同源 location 不同，
/// 正常放行（换集走 context.replace，也不受影响）。
DateTime? _lastPushAt;
String? _lastPushLocation;

void pushPlayerRoute(BuildContext context, String location) {
  final now = DateTime.now();
  if (_lastPushLocation == location &&
      _lastPushAt != null &&
      now.difference(_lastPushAt!) < const Duration(milliseconds: 1000)) {
    return;
  }
  _lastPushAt = now;
  _lastPushLocation = location;
  context.push(location);
}
