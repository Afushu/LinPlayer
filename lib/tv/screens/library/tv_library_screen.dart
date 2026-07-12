import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_interfaces.dart';
import '../../../core/providers/media_providers.dart';
import '../../../core/utils/library_filter_utils.dart';
import '../../../core/widgets/app_shimmer.dart';
import '../../theme/tv_design_tokens.dart';
import '../../theme/tv_metrics.dart';
import '../../widgets/tv_focusable.dart';
import '../../widgets/tv_media_card.dart';
import '../../widgets/tv_panel.dart';

/// TV 媒体库页 —— 观感对齐移动端 [LibraryDetailScreen]：顶部筛选条（随网格下滑渐隐/滚出）
/// + 下方 2:3 海报网格（复用移动端 MediaPoster，遥控器焦点驱动）。
///
/// 保留原有 TV 数据/筛选/排序逻辑（[LibraryFilterValue] + 服务端过滤），仅重绘 build。
class TvLibraryScreen extends ConsumerStatefulWidget {
  /// 由首页/查看全部传入的目标媒体库；为空时取第一个媒体库。
  final String? initialLibraryId;

  /// 标题兜底：当 [initialLibraryId] 不是媒体库（如合集 BoxSet）时用它显示名字。
  final String? initialTitle;

  const TvLibraryScreen({super.key, this.initialLibraryId, this.initialTitle});

  @override
  ConsumerState<TvLibraryScreen> createState() => _TvLibraryScreenState();
}

class _TvLibraryScreenState extends ConsumerState<TvLibraryScreen> {
  /// 海报密度档位：调节网格目标列宽，配合 max-extent 让列数随屏宽自适应。
  /// 三档对应「较密 / 中等 / 较疏」，中等在 1920 上约 6 列（对齐移动端 3 列的加宽版）。
  static const List<double> _densityFactors = [0.85, 1.0, 1.3];
  int _densityIndex = 1;
  String? _libraryId;
  // 筛选 + 排序（服务端过滤；排序字段/升降序也并入 _filter）。
  late LibraryFilterValue _filter;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _libraryId = widget.initialLibraryId;
    // 排序从持久化偏好恢复；其它筛选保持每次进页面重置。
    final sort = ref.read(librarySortProvider);
    _filter = LibraryFilterValue(
      sortBy: sort.sortBy,
      sortDescending: sort.descending,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 套用筛选并把排序落盘（退出播放器返回后仍生效）。
  void _apply(LibraryFilterValue v) {
    setState(() => _filter = v);
    ref.read(librarySortProvider.notifier).state =
        LibrarySortPref(sortBy: v.sortBy, descending: v.sortDescending);
  }

  @override
  Widget build(BuildContext context) {
    final m = context.tv;
    final librariesAsync = ref.watch(librariesProvider);

    return Scaffold(
      backgroundColor: TvDesignTokens.background,
      body: librariesAsync.when(
        data: (libs) {
          if (libs.isEmpty) return _centerHint('暂无媒体库');
          final libId = _libraryId ?? libs.first.id;
          return CustomScrollView(
            controller: _scroll,
            slivers: [
              // 筛选条：随网格下滑逐渐渐隐并滚出（对齐移动端）。
              SliverToBoxAdapter(
                child: AnimatedBuilder(
                  animation: _scroll,
                  builder: (context, child) {
                    final offset =
                        _scroll.hasClients ? _scroll.offset : 0.0;
                    // 前 120px 线性渐隐；面板本身也随滚动上移滑出 = 往上逐渐消失。
                    final opacity = (1 - offset / 120).clamp(0.0, 1.0);
                    return Opacity(opacity: opacity, child: child);
                  },
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                        m.spacingXl, m.spacingXl, m.spacingXl, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(m, libs, libId),
                        SizedBox(height: m.spacingMd),
                        _buildFilterBar(m, libId),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(child: SizedBox(height: m.spacingLg)),
              _buildGridSliver(m, libId),
              SliverToBoxAdapter(child: SizedBox(height: m.spacingXxl)),
            ],
          );
        },
        loading: () => const Center(
            child: AppLoadingIndicator(size: 48, color: TvDesignTokens.brand)),
        error: (e, _) => _centerHint('加载媒体库失败：$e'),
      ),
    );
  }

  Widget _buildHeader(TvMetrics m, List<Library> libs, String selectedId) {
    // selectedId 可能是合集(不在 libs 里)，匹配不到就用传入标题兜底。
    final match = libs.where((l) => l.id == selectedId).firstOrNull;
    final title = match?.name ?? widget.initialTitle ?? libs.first.name;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: m.fontSizeXxl,
              color: TvDesignTokens.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (_filter.activeCount > 0) ...[
          TvFocusable(
            onSelect: () => _apply(_filter.cleared()),
            child: _chip(m, icon: Icons.restart_alt, label: '重置', selected: false),
          ),
          SizedBox(width: m.spacingSm),
        ],
        TvFocusable(
          onSelect: () => setState(() {
            _densityIndex = (_densityIndex + 1) % _densityFactors.length;
          }),
          child: _chip(
            m,
            icon: _densityIndex == 0 ? Icons.grid_on : Icons.grid_view,
            label: _densityIndex == 0
                ? '较密'
                : (_densityIndex == 1 ? '中等' : '较疏'),
            selected: false,
          ),
        ),
      ],
    );
  }

  /// 排序选项：更新时间 / 标题排序 / 官方评级。点选中项切升/降序，点未选中项切到该字段。
  static const List<({String label, String key})> _sortOptions = [
    (label: '更新时间', key: 'DateLastContentAdded'),
    (label: '标题排序', key: 'SortName'),
    (label: '官方评级', key: 'OfficialRating'),
  ];

  /// 筛选条：时间（平铺胶囊）+ 类型/标签/工作室（回显行，点开 TvPanel 单选）+ 排序。
  /// 对齐移动端紧凑筛选栏：小取值平铺、大取值走弹窗。下方网格服务端实时过滤。
  Widget _buildFilterBar(TvMetrics m, String libraryId) {
    final facetsAsync = ref.watch(filtersProvider(libraryId));
    return facetsAsync.maybeWhen(
      data: (f) {
        final years = buildYearChips(f.years, currentYear: DateTime.now().year);
        final rows = <Widget>[];
        // 顺序（自上而下）：时间 → 类型 → 标签 → 工作室 → 排序。
        if (years.isNotEmpty) {
          rows.add(_facetChipRow(m, '时间', [
            for (final yc in years)
              _facetChip(m, yc.label, _filter.yearLabel == yc.label, () {
                final on = _filter.yearLabel == yc.label;
                _apply(_filter.withYear(
                    on ? null : yc.label, on ? null : yc.yearsCsv));
              }),
          ]));
        }
        if (f.genres.isNotEmpty) {
          rows.add(_pickerRow(m, '类型', _filter.genre, () {
            _openFacetPanel('类型', f.genres, _filter.genre,
                (p) => _apply(_filter.withGenre(p)));
          }));
        }
        if (f.tags.isNotEmpty) {
          rows.add(_pickerRow(m, '标签', _filter.tag, () {
            _openFacetPanel('标签', sortByPinyin(f.tags), _filter.tag,
                (p) => _apply(_filter.withTag(p)));
          }));
        }
        if (f.studios.isNotEmpty) {
          rows.add(_pickerRow(m, '工作室', _filter.studio, () {
            // 工作室优先存 Id（StudioIds），服务端 GUID 严格时 API 层自动退回按名过滤。
            _openFacetPanel('工作室', sortByPinyin(f.studios), _filter.studio,
                (p) => _apply(_filter.withStudio(
                    p, p == null ? null : f.studioIds[p])));
          }));
        }
        rows.add(_facetChipRow(m, '排序', [for (final o in _sortOptions) _sortChip(m, o)]));
        return Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: rows);
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  Widget _sortChip(TvMetrics m, ({String label, String key}) opt) {
    final selected = _filter.sortBy == opt.key;
    return TvFocusable(
      onSelect: () => _apply(_filter.toggledSort(opt.key)),
      child: _chip(
        m,
        icon: selected
            ? (_filter.sortDescending
                ? Icons.arrow_downward
                : Icons.arrow_upward)
            : null,
        label: opt.label,
        selected: selected,
      ),
    );
  }

  /// 一行平铺可点选胶囊（时间 / 排序）。
  Widget _facetChipRow(TvMetrics m, String label, List<Widget> chips) {
    return Padding(
      padding: EdgeInsets.only(bottom: m.spacingSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: m.spacingXs, right: m.spacingMd),
            child: SizedBox(width: m.s(64), child: _dimLabel(m, label)),
          ),
          Expanded(
            child: Wrap(
                spacing: m.spacingSm, runSpacing: m.spacingSm, children: chips),
          ),
        ],
      ),
    );
  }

  Widget _facetChip(
      TvMetrics m, String label, bool selected, VoidCallback apply) {
    return TvFocusable(
      onSelect: apply,
      child: _chip(m, label: label, selected: selected),
    );
  }

  /// 回显当前选中值（未选「全部」），点开 TvPanel 单选（工作室/类型/标签）。
  Widget _pickerRow(
      TvMetrics m, String label, String? selected, VoidCallback onOpen) {
    return Padding(
      padding: EdgeInsets.only(bottom: m.spacingSm),
      child: Row(
        children: [
          SizedBox(width: m.s(76), child: _dimLabel(m, label)),
          SizedBox(width: m.spacingMd),
          TvFocusable(
            onSelect: onOpen,
            child: _chip(m,
                icon: Icons.keyboard_arrow_down,
                label: selected ?? '全部',
                selected: selected != null),
          ),
        ],
      ),
    );
  }

  Widget _dimLabel(TvMetrics m, String label) => Text(
        label,
        style: TextStyle(
          fontSize: m.fontSizeSm,
          color: TvDesignTokens.textSecondary,
          fontWeight: FontWeight.bold,
        ),
      );

  /// TV 右侧滑入面板单选：顶部「全部」+ 拼音排序取值。选中回调 [onPick]（null=全部/清除）。
  void _openFacetPanel(String title, List<String> options, String? current,
      void Function(String? picked) onPick) {
    showDialog<void>(
      context: context,
      builder: (ctx) => TvPanel(
        title: title,
        onClose: () => Navigator.pop(ctx),
        children: [
          TvPanelOption(
            title: '全部',
            isSelected: current == null,
            onTap: () {
              Navigator.pop(ctx);
              onPick(null);
            },
          ),
          for (final o in options)
            TvPanelOption(
              title: o,
              isSelected: o == current,
              onTap: () {
                Navigator.pop(ctx);
                onPick(o);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildGridSliver(TvMetrics m, String libraryId) {
    final itemsAsync = ref.watch(libraryItemsProvider((
      libraryId: libraryId,
      sortBy: _filter.sortBy,
      sortOrder: _filter.sortDescending ? 'Descending' : 'Ascending',
      genres: _filter.genre,
      tags: _filter.tag,
      studioIds: _filter.studioId,
      studios: _filter.studio,
      years: _filter.yearsCsv,
      ratingMin: _filter.ratingMin,
      ratingMax: _filter.ratingMax,
    )));

    // 2:3 海报 + 标题；列数随屏宽自适应，密度档位微调目标列宽（中等档 1920 上约 6 列）。
    final double maxExtent =
        m.posterWidth2_3 * 1.4 * _densityFactors[_densityIndex];

    return itemsAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return SliverToBoxAdapter(child: _centerHint('该媒体库暂无内容'));
        }
        return SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: m.spacingXl),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: maxExtent,
              childAspectRatio: 0.58, // 海报(2:3) + 标题/年份/评分
              crossAxisSpacing: m.posterSpacing,
              mainAxisSpacing: m.posterSpacing,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = items[index];
                return TvMediaCard(
                  item: item,
                  width: double.infinity,
                  height: double.infinity,
                  onSelect: () => context.push('/tv/detail/${item.id}'),
                );
              },
              childCount: items.length,
            ),
          ),
        );
      },
      loading: () => const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
            child: AppLoadingIndicator(size: 48, color: TvDesignTokens.brand)),
      ),
      error: (e, _) => SliverToBoxAdapter(child: _centerHint('加载失败：$e')),
    );
  }

  Widget _chip(TvMetrics m,
      {IconData? icon, required String label, required bool selected}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: m.spacingMd,
        vertical: m.spacingXs,
      ),
      decoration: BoxDecoration(
        color: selected
            ? TvDesignTokens.brand.withValues(alpha: 0.18)
            : TvDesignTokens.surface,
        borderRadius: BorderRadius.circular(m.posterRadius),
        border:
            selected ? Border.all(color: TvDesignTokens.brand, width: 2) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon,
                size: m.s(22),
                color: selected
                    ? TvDesignTokens.brand
                    : TvDesignTokens.textSecondary),
            SizedBox(width: m.spacingXs),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: m.fontSizeSm,
              color: selected ? TvDesignTokens.brand : TvDesignTokens.textPrimary,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _centerHint(String text) {
    final m = context.tv;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(m.spacingXxl),
        child: Text(
          text,
          style: TextStyle(
            color: TvDesignTokens.textSecondary,
            fontSize: m.fontSizeMd,
          ),
        ),
      ),
    );
  }
}
