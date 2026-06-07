// 百度网盘授权区统一展示 OAuth 状态、说明和重新授权入口。

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class BaiduPanAuthSection extends StatelessWidget {
  const BaiduPanAuthSection({
    super.key,
    required this.accountLabel,
    required this.authorized,
    required this.busy,
    required this.onAuthorize,
  });

  final String accountLabel;
  final bool authorized;
  final bool busy;
  final VoidCallback onAuthorize;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final accent = authorized
        ? theme.colorScheme.primary
        : theme.colorScheme.mutedForeground;
    final statusText = authorized
        ? '已授权：${accountLabel.trim().isEmpty ? '百度网盘账号' : accountLabel.trim()}'
        : '尚未授权';
    final helperText = authorized
        ? '上传会先进入 /apps/网盘demo/，再自动移动到你当前选择的目标目录。'
        : '点击下方按钮后，应用会监听本地端口、拉起浏览器，并等待百度 OAuth 回调 3 分钟。';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.border.withValues(alpha: 0.8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                authorized ? Icons.verified_outlined : Icons.link_outlined,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.foreground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            helperText,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: theme.colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(height: 12),
          ShadButton.outline(
            onPressed: busy ? null : onAuthorize,
            child: Text(authorized ? '重新授权百度网盘' : '登录百度网盘'),
          ),
        ],
      ),
    );
  }
}
