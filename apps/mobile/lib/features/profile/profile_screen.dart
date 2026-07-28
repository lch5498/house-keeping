import 'package:flutter/cupertino.dart';

import '../../core/api_client.dart';
import '../../design_system/app_colors.dart';

typedef ProfileSaveCallback =
    Future<AppUser> Function(
      String nickname, {
      required bool updateFamilyMemberNicknames,
    });

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.user,
    required this.familyCount,
    required this.onSave,
    required this.onDeleteAccount,
    this.onLogout,
  });

  final AppUser user;
  final int familyCount;
  final ProfileSaveCallback onSave;
  final Future<void> Function() onDeleteAccount;
  final Future<void> Function()? onLogout;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _nicknameController;

  String? _message;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: widget.user.nickname);
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nickname = _nicknameController.text.trim();

    if (nickname.isEmpty) {
      setState(() {
        _message = '닉네임을 입력해 주세요.';
      });
      return;
    }

    if (nickname.length > 30) {
      setState(() {
        _message = '닉네임은 30자 이하로 입력해 주세요.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      final shouldUpdateFamilyMemberNicknames =
          await _shouldUpdateFamilyMemberNicknames();

      if (shouldUpdateFamilyMemberNicknames == null) {
        if (mounted) {
          setState(() {
            _isSaving = false;
          });
        }
        return;
      }

      await widget.onSave(
        nickname,
        updateFamilyMemberNicknames: shouldUpdateFamilyMemberNicknames,
      );

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<bool?> _shouldUpdateFamilyMemberNicknames() async {
    if (widget.familyCount <= 0) {
      return false;
    }

    if (widget.familyCount == 1) {
      return true;
    }

    return showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return CupertinoAlertDialog(
          title: Text('구성원 이름도 바꿀까요?'),
          content: Text('여러 그룹에 속해 있습니다. 연결된 구성원 이름도 모두 같은 이름으로 변경할까요?'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: Text('취소'),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('프로필만 변경'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('구성원 이름도 변경'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return CupertinoAlertDialog(
          title: Text('로그아웃할까요?'),
          content: Text('다시 사용하려면 재로그인이 필요합니다.'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('취소'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('로그아웃'),
            ),
          ],
        );
      },
    );

    final onLogout = widget.onLogout;

    if (shouldLogout != true || !mounted || onLogout == null) {
      return;
    }

    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }

    await onLogout();
  }

  Future<void> _confirmDeleteAccount() async {
    final shouldDelete = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return CupertinoAlertDialog(
          title: Text('탈퇴할까요?'),
          content: Text('모든 데이터가 삭제되며 복구되지 않습니다. 정말 탈퇴할까요?'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('취소'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('탈퇴하기'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true || !mounted) {
      return;
    }

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      await widget.onDeleteAccount();

      if (mounted) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).popUntil((route) => route.isFirst);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: AppColors.darkBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text('내 정보 관리'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 32),
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const CupertinoActivityIndicator()
              : Text(
                  '저장',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Text(
              '프로필 이름',
              style: TextStyle(
                color: AppColors.darkTextPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                height: 1.12,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 26),
            CupertinoTextField(
              controller: _nicknameController,
              autofocus: true,
              clearButtonMode: OverlayVisibilityMode.editing,
              maxLength: 30,
              placeholder: '닉네임',
              textInputAction: TextInputAction.done,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              style: TextStyle(
                color: AppColors.darkTextPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
              decoration: BoxDecoration(
                color: AppColors.darkSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.darkBorder),
              ),
              onSubmitted: (_) => _save(),
            ),
            if (_message != null) ...[
              const SizedBox(height: 14),
              _ProfileMessage(message: _message!),
            ],
            const SizedBox(height: 34),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (widget.onLogout != null)
                  _ProfileTextAction(
                    label: '로그아웃',
                    onPressed: _isSaving ? null : _confirmLogout,
                  )
                else
                  const SizedBox.shrink(),
                _ProfileTextAction(
                  label: '탈퇴하기',
                  isDestructive: true,
                  onPressed: _isSaving ? null : _confirmDeleteAccount,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTextAction extends StatelessWidget {
  const _ProfileTextAction({
    required this.label,
    required this.onPressed,
    this.isDestructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      minimumSize: Size.zero,
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          color:
              (isDestructive
                      ? CupertinoColors.destructiveRed
                      : AppColors.darkTextMuted)
                  .withValues(alpha: onPressed == null ? 0.35 : 0.78),
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _ProfileMessage extends StatelessWidget {
  const _ProfileMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          message,
          style: TextStyle(
            color: AppColors.darkDanger,
            fontSize: 14,
            height: 1.35,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}
