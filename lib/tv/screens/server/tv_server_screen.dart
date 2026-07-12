import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/providers/media_providers.dart';
import '../../../ui/widgets/common/media_widgets.dart';
import '../../theme/tv_design_tokens.dart';
import '../../theme/tv_metrics.dart';
import '../../widgets/tv_button.dart';
import '../../widgets/tv_focusable.dart';
import '../../widgets/tv_panel.dart';
import '../../widgets/tv_toast.dart';

/// TV 服务器页 —— 观感对齐移动端服务器列表：卡片（图标+名称+备注）+ 右侧「更多」
/// 唤起面板（编辑/删除），焦点驱动。逻辑沿用：切换当前服务器、编辑、删除。
class TvServerScreen extends ConsumerWidget {
  const TvServerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = context.tv;
    final servers = ref.watch(serverListProvider);
    final current = ref.watch(currentServerProvider);

    return Scaffold(
      backgroundColor: TvDesignTokens.background,
      body: Padding(
        padding: EdgeInsets.all(m.spacingXl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏：对齐移动端 AppBar（标题 + 右侧添加）。
            Row(
              children: [
                Text(
                  '服务器',
                  style: TextStyle(
                    fontSize: m.fontSizeXxl,
                    color: TvDesignTokens.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (servers.isNotEmpty)
                  TvFocusable(
                    padding: EdgeInsets.all(m.spacingXs),
                    onSelect: () => context.go('/tv/add-server'),
                    child: Icon(Icons.add,
                        color: TvDesignTokens.textPrimary, size: m.s(34)),
                  ),
              ],
            ),
            SizedBox(height: m.spacingLg),
            Expanded(
              child: servers.isEmpty
                  ? _buildEmpty(context, m)
                  : ListView(
                      children: [
                        for (final entry in servers.asMap().entries)
                          _buildServerCard(
                            context,
                            ref,
                            entry.value,
                            m,
                            isCurrent: entry.value.id == current?.id,
                            autofocus: entry.key == 0,
                          ).animate().fadeIn(
                                delay: Duration(milliseconds: 40 * entry.key),
                                duration: TvDesignTokens.contentFadeDuration,
                              ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, TvMetrics m) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.dns_outlined,
              color: TvDesignTokens.textSecondary, size: m.s(80)),
          SizedBox(height: m.spacingLg),
          Text('还没有服务器',
              style: TextStyle(
                  fontSize: m.fontSizeXl,
                  color: TvDesignTokens.textPrimary,
                  fontWeight: FontWeight.bold)),
          SizedBox(height: m.spacingXl),
          TvButton(
            text: '添加服务器',
            icon: Icons.add,
            autofocus: true,
            onPressed: () => context.go('/tv/add-server'),
          ),
        ],
      ),
    );
  }

  Widget _buildServerCard(
    BuildContext context,
    WidgetRef ref,
    ServerConfig server,
    TvMetrics m, {
    required bool isCurrent,
    bool autofocus = false,
  }) {
    final online = serverHasUsableAuth(server);
    final subtitle = (server.remark != null && server.remark!.isNotEmpty)
        ? server.remark!
        : server.baseUrl;
    return Padding(
      padding: EdgeInsets.only(bottom: m.spacingMd),
      child: TvFocusable(
        autofocus: autofocus,
        padding: EdgeInsets.all(m.s(6)),
        onSelect: () => _selectServer(context, ref, server),
        // 长按（Pad）/ 遥控器菜单键 → 唤起「更多」面板。
        onLongPress: () => _showMoreMenu(context, ref, server),
        child: Container(
          padding: EdgeInsets.all(m.spacingLg),
          decoration: BoxDecoration(
            color: isCurrent
                ? TvDesignTokens.brand.withValues(alpha: 0.15)
                : TvDesignTokens.surface,
            borderRadius: BorderRadius.circular(m.posterRadius),
            border: isCurrent
                ? Border.all(color: TvDesignTokens.brand, width: 2)
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: m.s(56),
                height: m.s(56),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: TvDesignTokens.brand.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(m.s(12)),
                ),
                // 有自定义图标（本地图片/网络图标）就显示图标，否则退回机房图标。
                child: (server.iconUrl != null && server.iconUrl!.isNotEmpty)
                    ? MediaImage(
                        imageUrl: server.iconUrl,
                        fit: BoxFit.contain,
                        useDefaultUserAgent: true,
                        errorWidget: const EmbyDefaultIcon(),
                      )
                    : Icon(Icons.dns,
                        color: TvDesignTokens.brand, size: m.s(30)),
              ),
              SizedBox(width: m.spacingLg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            server.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: m.fontSizeLg,
                              color: isCurrent
                                  ? TvDesignTokens.brand
                                  : TvDesignTokens.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isCurrent) ...[
                          SizedBox(width: m.spacingSm),
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: m.s(8), vertical: m.s(2)),
                            decoration: BoxDecoration(
                              color: TvDesignTokens.brand,
                              borderRadius: BorderRadius.circular(m.s(4)),
                            ),
                            child: Text('当前',
                                style: TextStyle(
                                    fontSize: m.fs(12),
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: m.spacingXs),
                    Row(
                      children: [
                        Container(
                          width: m.s(8),
                          height: m.s(8),
                          decoration: BoxDecoration(
                            color: online
                                ? TvDesignTokens.success
                                : TvDesignTokens.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: m.spacingXs),
                        Expanded(
                          child: Text(subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: m.fontSizeSm,
                                  color: TvDesignTokens.textSecondary)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: m.spacingSm),
              // 「更多」——对齐移动端卡片右侧的 more_vert，唤起选项面板。
              TvFocusable(
                padding: EdgeInsets.all(m.spacingXs),
                onSelect: () => _showMoreMenu(context, ref, server),
                child: Icon(Icons.more_vert,
                    color: TvDesignTokens.textSecondary, size: m.s(28)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectServer(BuildContext context, WidgetRef ref, ServerConfig server) {
    ref.read(currentServerProvider.notifier).state = server;
    ref.read(authStateProvider.notifier).state = serverHasUsableAuth(server)
        ? AuthState.authenticated
        : AuthState.unauthenticated;
    ref.invalidate(librariesProvider);
    ref.invalidate(resumeItemsProvider);
    ref.invalidate(randomRecommendationsProvider);
    // 网盘/聚合源：进首页（由 TvHomeScreen 渲染文件浏览视图）。
    if (server.isFileBrowse) {
      context.go('/tv/home');
      return;
    }
    TvToast.show(context, '已切换到 ${server.name}');
  }

  /// 「更多」面板：对齐移动端底部菜单（编辑 / 删除）。
  void _showMoreMenu(BuildContext context, WidgetRef ref, ServerConfig server) {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) {
        return TvPanel(
          title: server.name,
          onClose: () => Navigator.pop(dialogContext),
          children: [
            TvPanelOption(
              title: '编辑信息',
              leading: const Icon(Icons.edit_outlined,
                  color: TvDesignTokens.textPrimary),
              onTap: () {
                Navigator.pop(dialogContext);
                context.push('/tv/edit-server/${server.id}');
              },
            ),
            SizedBox(height: dialogContext.tv.spacingXs),
            TvPanelOption(
              title: '删除',
              leading: const Icon(Icons.delete_outline,
                  color: TvDesignTokens.error),
              onTap: () {
                Navigator.pop(dialogContext);
                _confirmDelete(context, ref, server);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, ServerConfig server) async {
    final ok = await showTvConfirm(
      context,
      title: '删除服务器',
      message: '确定要删除 “${server.name}” 吗？',
      confirmLabel: '删除',
      danger: true,
    );
    if (!ok) return;
    ref.read(serverListProvider.notifier).removeServer(server.id);
    if (ref.read(currentServerProvider)?.id == server.id) {
      ref.read(currentServerProvider.notifier).clear();
    }
    if (context.mounted) TvToast.show(context, '服务器已删除');
  }
}
