import 'package:flutter/material.dart';
import '../theme/tv_metrics.dart';
import 'tv_focusable.dart';

/// TV 自适应卡片网格：把「一条条满宽行/卡」改成按屏宽等分的多列网格，
/// 用满横向空间（电视布局的核心）。
///
/// - 不自带滚动：外层放进已有的 SingleChildScrollView / ListView / Column 即可。
/// - 每格等宽（填满整行），高度由子项自身决定；两列高度不一时按顶部对齐。
/// - [minCellWidth] 是「每格最小宽度」的 1080p 基准，内部按 context.tv 等比缩放后，
///   用它推列数：列数 = 可用宽度能放下几个 minCellWidth（至少 1）。
class TvResponsiveGrid extends StatelessWidget {
  final List<Widget> children;

  /// 每格最小宽度（1080p 基准，会按 m.s 缩放）。越大列数越少。
  final double minCellWidth;

  /// 列间距 / 行间距（1080p 基准，会按 m.s 缩放）。传 null 用 spacingMd。
  final double? spacing;

  const TvResponsiveGrid({
    super.key,
    required this.children,
    this.minCellWidth = 460,
    this.spacing,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final m = context.tv;
    final gap = m.s(spacing ?? 24);
    final minW = m.s(minCellWidth);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : m.s(1600);
        // 能放下几列：(maxW + gap) / (minW + gap)，至少 1 列。
        var cols = ((maxW + gap) / (minW + gap)).floor();
        if (cols < 1) cols = 1;
        if (cols > children.length) cols = children.length;
        final cellW = (maxW - gap * (cols - 1)) / cols;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children)
              SizedBox(width: cellW, child: child),
          ],
        );
      },
    );
  }
}

/// 把「整宽分隔项（标题 Text / 间距 SizedBox / 分区头 Padding）+ 可聚焦瓦片
/// [TvFocusable]」的扁平列表就地改成多列：连续的瓦片收进一个 [TvResponsiveGrid]，
/// 其余整宽项原样穿插其间。用来把单列设置页改成 TV 多列网格，而不动各 build 逻辑。
List<Widget> tvGridifyFocusables(List<Widget> items,
    {double minCellWidth = 460, double? spacing}) {
  final out = <Widget>[];
  var run = <Widget>[];
  void flush() {
    if (run.isEmpty) return;
    out.add(TvResponsiveGrid(
        minCellWidth: minCellWidth, spacing: spacing, children: run));
    run = <Widget>[];
  }

  for (final w in items) {
    if (w is TvFocusable) {
      run.add(w);
    } else {
      flush();
      out.add(w);
    }
  }
  flush();
  return out;
}
