import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/constants.dart';
import '../theme/ui_style.dart';

/// 待机屏与「时间」页共用的胶囊按钮：同一颗芯片只定义一次
Widget clockChip({
  required UiTokens tokens,
  required String label,
  required bool selected,
  required VoidCallback onTap,
  IconData? icon,
}) {
  final fg = tokens.fg;
  final ink = tokens.accentSelection ? tokens.accentInk : fg;
  final border = selected ? ink : fg.withValues(alpha: 0.32);
  final shape = tokens.chipRadius >= 900
      ? const StadiumBorder()
      : RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.chipRadius));
  return ActionChip(
    // 芯片默认只有 32 高（SDK chip.dart 的 _kChipHeight），低于 44x44 命中区；
    // 用内衬撑到 44+，视觉上的胶囊形状不变。
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    label: Text(uiLabelText(tokens, label)),
    labelStyle: TextStyle(
        color: fg,
        letterSpacing: tokens.labelTracking * 0.3,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w400),
    avatar: icon == null ? null : Icon(icon, size: 18, color: fg),
    backgroundColor: selected ? ink.withValues(alpha: 0.16) : Colors.transparent,
    side: BorderSide(color: border, width: tokens.chipStrokeWidth),
    shape: shape,
    onPressed: () {
      HapticFeedback.selectionClick();
      onTap();
    },
  );
}

/// 自定义倒计时分钟数（1-600）；取消返回 null
Future<int?> askCustomCountdown(BuildContext context) => showDialog<int>(
      context: context,
      builder: (_) => const _CustomCountdownDialog(),
    );

class _CustomCountdownDialog extends StatefulWidget {
  const _CustomCountdownDialog();

  @override
  State<_CustomCountdownDialog> createState() => _CustomCountdownDialogState();
}

class _CustomCountdownDialogState extends State<_CustomCountdownDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final minutes = int.tryParse(_controller.text.trim());
    if (minutes == null ||
        minutes < AppConstants.minCountdownMinutes ||
        minutes > AppConstants.maxCountdownMinutes) {
      setState(() => _error =
          '请输入 ${AppConstants.minCountdownMinutes}-${AppConstants.maxCountdownMinutes} 之间的分钟数');
      return;
    }
    Navigator.of(context).pop(minutes);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // 横屏手机上软键盘会把弹窗可用高度压到 150 逻辑像素左右：AlertDialog 的外边距
      // 是 viewInsets + insetPadding 之和，非 scrollable 的 content 会被 Flexible 压成
      // 3 像素高，输入框整块消失（Pixel7 横屏实测）。三处一起改才留得住输入区。
      scrollable: true,
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      title: const Text('自定义倒计时'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            // 不自动抢焦点：一抢焦点就弹键盘，弹窗立刻被压瘪；改成用户点输入框才弹，
            // 且下面的快捷档不需要键盘就能用。
            autofocus: false,
            keyboardType: TextInputType.number,
            maxLength: 3,
            decoration: InputDecoration(
              labelText: '分钟',
              hintText:
                  '${AppConstants.minCountdownMinutes}-${AppConstants.maxCountdownMinutes}',
              counterText: '',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final min in AppConstants.countdownPresets)
                ActionChip(
                  label: Text('$min'),
                  onPressed: () => Navigator.of(context).pop(min),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('开始'),
        ),
      ],
    );
  }
}
