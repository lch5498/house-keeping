import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/home_widget_service.dart';
import '../../core/theme_preference.dart';
import '../../design_system/app_colors.dart';
import '../family/family_screen.dart';
import '../activity/group_activity_log_screen.dart';
import '../activity/group_activity_read_state.dart';
import '../parking/parking_screen.dart';
import '../schedule/schedule_hub_screen.dart';
import '../scrap/scrap_screen.dart';
import '../settings/settings_screen.dart';
import '../travel/travel_screen.dart';
import '../../shared/member_filter.dart';
import '../../shared/refreshable_scroll_view.dart';

const _preferencesChannel = MethodChannel('checky/preferences');
const _deepLinkChannel = MethodChannel('checky/deep_links');
const _selectedFamilyPreferenceKey = 'selectedFamilyId';

typedef ProfileUpdateCallback =
    Future<AppUser> Function(
      String nickname, {
      required bool updateFamilyMemberNicknames,
    });

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.user,
    required this.sessionToken,
    required this.onUpdateProfile,
    required this.onDeleteAccount,
    this.initialFamilies,
    this.initialSelectedFamilyId,
    this.initialScheduleDashboard,
    this.initialParkingDashboard,
    this.onLogout,
  });

  final AppUser user;
  final String sessionToken;
  final ProfileUpdateCallback onUpdateProfile;
  final Future<void> Function() onDeleteAccount;
  final List<FamilySummary>? initialFamilies;
  final String? initialSelectedFamilyId;
  final ScheduleDashboard? initialScheduleDashboard;
  final ParkingDashboard? initialParkingDashboard;
  final Future<void> Function()? onLogout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _apiClient = ApiClient();
  late final CupertinoTabController _tabController;

  List<FamilySummary> _families = const [];
  String? _selectedFamilyId;
  String? _message;
  bool _isLoadingFamilies = true;
  int _homeRefreshToken = 0;
  int _scheduleRefreshToken = 0;
  int _todayScheduleRequestToken = 0;
  int _notificationRefreshToken = 0;
  final Set<String> _handledInviteTokens = <String>{};

  AppFamily? get _selectedFamily {
    if (_families.isEmpty) {
      return null;
    }

    for (final summary in _families) {
      if (summary.family.id == _selectedFamilyId) {
        return summary.family;
      }
    }

    return _families.first.family;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = CupertinoTabController();
    _tabController.addListener(_handleTabChange);
    _deepLinkChannel.setMethodCallHandler(_handleDeepLinkMethodCall);
    final initialFamilies = widget.initialFamilies;
    if (initialFamilies != null) {
      _families = initialFamilies;
      _selectedFamilyId = _resolveSelectedFamilyId(
        initialFamilies,
        widget.initialSelectedFamilyId,
      );
      _isLoadingFamilies = false;
    } else {
      _loadFamilies();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumeInviteLinkFromChannel('getInitialLink');
      _consumeInviteLinkFromChannel('getLatestLink');
      _consumeInviteLinkFromChannelLater('getLatestLink');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deepLinkChannel.setMethodCallHandler(null);
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      setState(() {
        _notificationRefreshToken += 1;
      });
      _consumeInviteLinkFromChannel('getLatestLink');
      _consumeInviteLinkFromChannelLater('getLatestLink');
    }
  }

  void _handleTabChange() {
    if (_tabController.index == 0) {
      setState(() {
        _homeRefreshToken += 1;
        _notificationRefreshToken += 1;
      });
    } else if (_tabController.index == 1) {
      setState(() {
        _scheduleRefreshToken += 1;
      });
    }
  }

  void _openScheduleTab() {
    setState(() {
      _todayScheduleRequestToken += 1;
    });
    _tabController.index = 1;
  }

  void _openParkingTab() {
    _tabController.index = 2;
  }

  void _openScrapTab() {
    _tabController.index = 3;
  }

  void _openScrapActivity(ScrapRecentActivity activity) {
    final family = _selectedFamily;

    if (family == null) {
      return;
    }

    final now = DateTime.now();
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => ScrapChannelScreen(
          family: family,
          sessionToken: widget.sessionToken,
          channel: ScrapChannel(
            id: activity.channelId,
            familyId: family.id,
            name: activity.channelName,
            sortOrder: null,
            authorNickname: '알 수 없음',
            canEdit: false,
            canDelete: false,
            hasRecentPosts: false,
            createdAt: now,
            updatedAt: now,
          ),
          initialPostId: activity.postId,
        ),
      ),
    );
  }

  Future<void> _handleDeepLinkMethodCall(MethodCall call) async {
    if (call.method != 'onLink') {
      return;
    }

    final link = call.arguments as String?;

    if (link == null || link.trim().isEmpty) {
      return;
    }

    await _handleInviteLink(link);
  }

  Future<void> _consumeInviteLinkFromChannelLater(String method) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));

    if (!mounted) {
      return;
    }

    await _consumeInviteLinkFromChannel(method);
  }

  Future<void> _consumeInviteLinkFromChannel(String method) async {
    try {
      final link = await _deepLinkChannel.invokeMethod<String>(method);

      if (!mounted || link == null || link.trim().isEmpty) {
        return;
      }

      await _handleInviteLink(link);
    } on MissingPluginException {
      return;
    }
  }

  Future<void> _handleInviteLink(String link) async {
    final inviteToken = _extractInviteToken(link);

    if (inviteToken.isEmpty || _handledInviteTokens.contains(inviteToken)) {
      return;
    }

    _handledInviteTokens.add(inviteToken);

    final shouldAccept = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text('그룹 초대 수락'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('이 초대 링크로 그룹에 참여할까요?'),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('취소'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('수락'),
          ),
        ],
      ),
    );

    if (shouldAccept != true || !mounted) {
      _handledInviteTokens.remove(inviteToken);
      return;
    }

    setState(() {
      _isLoadingFamilies = true;
      _message = null;
    });

    try {
      final detail = await _apiClient.acceptFamilyInvitation(
        widget.sessionToken,
        inviteToken: inviteToken,
      );
      await _loadFamilies();

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedFamilyId = detail.family.id;
      });
      await _saveSelectedFamilyId(detail.family.id);

      if (!mounted) {
        return;
      }

      await showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text('초대 수락 완료'),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('${detail.family.name} 그룹에 연결되었습니다.'),
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('확인'),
            ),
          ],
        ),
      );
    } catch (error) {
      _handledInviteTokens.remove(inviteToken);

      if (mounted) {
        setState(() {
          _message = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingFamilies = false;
        });
      }
    }
  }

  Future<void> _loadFamilies() async {
    setState(() {
      _isLoadingFamilies = true;
      _message = null;
    });

    try {
      final preferredFamilyId =
          _selectedFamilyId ?? await _readSelectedFamilyId();
      final families = await _apiClient.listFamilies(widget.sessionToken);
      final selectedFamilyId = _resolveSelectedFamilyId(
        families,
        preferredFamilyId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _families = families;
        _selectedFamilyId = selectedFamilyId;
      });

      if (selectedFamilyId != null) {
        await _saveSelectedFamilyId(selectedFamilyId);
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
          _isLoadingFamilies = false;
        });
      }
    }
  }

  String? _resolveSelectedFamilyId(
    List<FamilySummary> families,
    String? preferredFamilyId,
  ) {
    if (families.isEmpty) {
      return null;
    }

    if (preferredFamilyId != null &&
        families.any((summary) => summary.family.id == preferredFamilyId)) {
      return preferredFamilyId;
    }

    return families.first.family.id;
  }

  Future<String?> _readSelectedFamilyId() async {
    try {
      return await _preferencesChannel.invokeMethod<String>('getString', {
        'key': _selectedFamilyPreferenceKey,
      });
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _saveSelectedFamilyId(String familyId) async {
    try {
      await _preferencesChannel.invokeMethod<void>('setString', {
        'key': _selectedFamilyPreferenceKey,
        'value': familyId,
      });
    } on MissingPluginException {
      return;
    }
  }

  Future<void> _openFamilyManagement() async {
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => FamilyScreen(
          sessionToken: widget.sessionToken,
          currentUserId: widget.user.id,
        ),
      ),
    );
    await _loadFamilies();
  }

  Future<void> _switchFamily() async {
    if (_families.length < 2) {
      return;
    }

    final selectedFamilyId = await showCupertinoModalPopup<String>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: Text('그룹 전환'),
        actions: _families
            .map(
              (summary) => CupertinoActionSheetAction(
                isDefaultAction: summary.family.id == _selectedFamilyId,
                onPressed: () =>
                    Navigator.of(popupContext).pop(summary.family.id),
                child: Text(summary.family.name),
              ),
            )
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popupContext).pop(),
          child: Text('취소'),
        ),
      ),
    );

    if (selectedFamilyId == null) {
      return;
    }

    final selectedFamily = _families
        .map((summary) => summary.family)
        .firstWhere((family) => family.id == selectedFamilyId);
    await _selectFamily(selectedFamily);
  }

  Future<void> _selectFamily(AppFamily family) async {
    setState(() {
      _selectedFamilyId = family.id;
    });
    await _saveSelectedFamilyId(family.id);
  }

  @override
  Widget build(BuildContext context) {
    ThemePreferenceScope.of(context);
    AppColors.useBrightness(Theme.of(context).brightness);

    final selectedFamily = _selectedFamily;

    if (!_isLoadingFamilies && selectedFamily != null) {
      final families = _families.map((summary) => summary.family).toList();

      return CupertinoTabScaffold(
        controller: _tabController,
        tabBar: CupertinoTabBar(
          backgroundColor: AppColors.darkSurfaceElevated,
          activeColor: AppColors.darkPrimary,
          inactiveColor: AppColors.darkTextMuted,
          iconSize: 22,
          border: Border(top: BorderSide(color: AppColors.darkBorder)),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.house),
              activeIcon: Icon(CupertinoIcons.house_fill),
              label: '홈',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.calendar),
              activeIcon: Icon(CupertinoIcons.calendar_today),
              label: '일정',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.car_detailed),
              activeIcon: Icon(CupertinoIcons.car_detailed),
              label: '주차',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.bookmark),
              activeIcon: Icon(CupertinoIcons.bookmark_fill),
              label: '스크랩',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.airplane),
              activeIcon: Icon(CupertinoIcons.airplane),
              label: '여행',
            ),
          ],
        ),
        tabBuilder: (context, index) {
          return CupertinoTabView(
            key: ValueKey('family-tab-${selectedFamily.id}-$index'),
            builder: (context) {
              switch (index) {
                case 1:
                  return ScheduleHubScreen(
                    family: selectedFamily,
                    families: families,
                    sessionToken: widget.sessionToken,
                    refreshToken: _scheduleRefreshToken,
                    todayRequestToken: _todayScheduleRequestToken,
                    onSelectFamily: _selectFamily,
                  );
                case 2:
                  return ParkingScreen(
                    family: selectedFamily,
                    families: families,
                    sessionToken: widget.sessionToken,
                    onSelectFamily: _selectFamily,
                  );
                case 3:
                  return ScrapScreen(
                    family: selectedFamily,
                    families: families,
                    sessionToken: widget.sessionToken,
                    onSelectFamily: _selectFamily,
                  );
                case 4:
                  return TravelScreen(
                    family: selectedFamily,
                    families: families,
                    sessionToken: widget.sessionToken,
                    onSelectFamily: _selectFamily,
                  );
                case 0:
                default:
                  return _HomeDashboardTab(
                    user: widget.user,
                    sessionToken: widget.sessionToken,
                    family: selectedFamily,
                    families: families,
                    refreshToken: _homeRefreshToken,
                    notificationRefreshToken: _notificationRefreshToken,
                    initialDashboardFamilyId: _resolveSelectedFamilyId(
                      _families,
                      widget.initialSelectedFamilyId,
                    ),
                    initialScheduleDashboard: widget.initialScheduleDashboard,
                    initialParkingDashboard: widget.initialParkingDashboard,
                    message: _message,
                    onSwitchFamily: _switchFamily,
                    onOpenSchedule: _openScheduleTab,
                    onOpenParking: _openParkingTab,
                    onOpenScraps: _openScrapTab,
                    onOpenScrapActivity: _openScrapActivity,
                    onGroupsChanged: _loadFamilies,
                    onUpdateProfile: widget.onUpdateProfile,
                    onDeleteAccount: widget.onDeleteAccount,
                    onLogout: widget.onLogout,
                  );
              }
            },
          );
        },
      );
    }

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: selectedFamily == null
            ? null
            : _HomeNotificationButton(
                sessionToken: widget.sessionToken,
                family: selectedFamily,
                currentUserId: widget.user.id,
                refreshToken: _notificationRefreshToken,
                onOpenParkingTab: _openParkingTab,
              ),
        middle: _HomeTitle(
          family: selectedFamily,
          canSwitch: _families.length > 1,
          onPressed: _switchFamily,
        ),
        trailing: _HomeNavigationTrailing(
          user: widget.user,
          sessionToken: widget.sessionToken,
          familyCount: _families.length,
          currentUserId: widget.user.id,
          onGroupsChanged: _loadFamilies,
          onUpdateProfile: widget.onUpdateProfile,
          onDeleteAccount: widget.onDeleteAccount,
          onLogout: widget.onLogout,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: _isLoadingFamilies
              ? const Center(child: CupertinoActivityIndicator())
              : _FamilyRequiredIntro(
                  userNickname: widget.user.nickname,
                  message: _message,
                  onReloadFamilies: _loadFamilies,
                  onOpenFamilyManagement: _openFamilyManagement,
                ),
        ),
      ),
    );
  }
}

class _HomeTitle extends StatelessWidget {
  const _HomeTitle({
    required this.family,
    required this.canSwitch,
    required this.onPressed,
  });

  final AppFamily? family;
  final bool canSwitch;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final family = this.family;

    if (family == null) {
      return Text('체키');
    }

    if (!canSwitch) {
      return Text(
        family.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          inherit: false,
          color: AppColors.darkTextPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      );
    }

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 32),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              family.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                inherit: false,
                color: AppColors.darkTextPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          if (canSwitch) ...[
            const SizedBox(width: 4),
            const Icon(CupertinoIcons.chevron_down, size: 15),
          ],
        ],
      ),
    );
  }
}

class _HomeNavigationTrailing extends StatelessWidget {
  const _HomeNavigationTrailing({
    required this.user,
    required this.sessionToken,
    required this.familyCount,
    required this.currentUserId,
    required this.onGroupsChanged,
    required this.onUpdateProfile,
    required this.onDeleteAccount,
    required this.onLogout,
  });

  final AppUser user;
  final String sessionToken;
  final int familyCount;
  final String currentUserId;
  final Future<void> Function() onGroupsChanged;
  final ProfileUpdateCallback onUpdateProfile;
  final Future<void> Function() onDeleteAccount;
  final Future<void> Function()? onLogout;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(32, 32),
      onPressed: () {
        Navigator.of(context, rootNavigator: true).push(
          CupertinoPageRoute<void>(
            builder: (_) => SettingsScreen(
              user: user,
              sessionToken: sessionToken,
              familyCount: familyCount,
              onSaveProfile: onUpdateProfile,
              onDeleteAccount: onDeleteAccount,
              currentUserId: currentUserId,
              onGroupsChanged: onGroupsChanged,
              onLogout: onLogout,
            ),
          ),
        );
      },
      child: const Icon(CupertinoIcons.gear),
    );
  }
}

class _HomeNotificationButton extends StatefulWidget {
  const _HomeNotificationButton({
    required this.sessionToken,
    required this.family,
    required this.currentUserId,
    required this.refreshToken,
    required this.onOpenParkingTab,
  });

  final String sessionToken;
  final AppFamily family;
  final String currentUserId;
  final int refreshToken;
  final VoidCallback onOpenParkingTab;

  @override
  State<_HomeNotificationButton> createState() =>
      _HomeNotificationButtonState();
}

class _HomeNotificationButtonState extends State<_HomeNotificationButton> {
  final _apiClient = ApiClient();
  bool _hasUnreadActivities = false;

  @override
  void initState() {
    super.initState();
    _loadUnreadActivities();
  }

  @override
  void didUpdateWidget(covariant _HomeNotificationButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.family.id != widget.family.id ||
        oldWidget.refreshToken != widget.refreshToken) {
      _loadUnreadActivities();
    }
  }

  Future<void> _loadUnreadActivities() async {
    try {
      final familyId = widget.family.id;
      final activities = await _apiClient.getGroupActivities(
        widget.sessionToken,
        familyId: familyId,
      );
      final readAt = await GroupActivityReadState.readAt(familyId: familyId);
      final hasUnread = activities.any(
        (activity) =>
            activity.actorUserId != widget.currentUserId &&
            (readAt == null || activity.createdAt.isAfter(readAt)),
      );

      if (mounted && widget.family.id == familyId) {
        setState(() {
          _hasUnreadActivities = hasUnread;
        });
      }
    } catch (_) {
      // 활동 로그 조회 실패가 홈 탐색을 방해하지 않도록 배지는 그대로 둔다.
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(32, 32),
      onPressed: () async {
        await Navigator.of(context, rootNavigator: true).push(
          CupertinoPageRoute<void>(
            builder: (_) => GroupActivityLogScreen(
              sessionToken: widget.sessionToken,
              family: widget.family,
              onOpenParkingTab: widget.onOpenParkingTab,
            ),
          ),
        );
        await _loadUnreadActivities();
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(CupertinoIcons.bell),
          if (_hasUnreadActivities)
            Positioned(
              top: -5,
              right: -7,
              child: Container(
                width: 14,
                height: 14,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.darkDanger,
                  shape: BoxShape.circle,
                ),
                child: const Text(
                  'N',
                  style: TextStyle(
                    color: CupertinoColors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HomeDashboardTab extends StatefulWidget {
  const _HomeDashboardTab({
    required this.user,
    required this.sessionToken,
    required this.family,
    required this.families,
    required this.refreshToken,
    required this.notificationRefreshToken,
    required this.initialDashboardFamilyId,
    required this.initialScheduleDashboard,
    required this.initialParkingDashboard,
    required this.message,
    required this.onSwitchFamily,
    required this.onOpenSchedule,
    required this.onOpenParking,
    required this.onOpenScraps,
    required this.onOpenScrapActivity,
    required this.onGroupsChanged,
    required this.onUpdateProfile,
    required this.onDeleteAccount,
    required this.onLogout,
  });

  final AppUser user;
  final String sessionToken;
  final AppFamily family;
  final List<AppFamily> families;
  final int refreshToken;
  final int notificationRefreshToken;
  final String? initialDashboardFamilyId;
  final ScheduleDashboard? initialScheduleDashboard;
  final ParkingDashboard? initialParkingDashboard;
  final String? message;
  final VoidCallback onSwitchFamily;
  final VoidCallback onOpenSchedule;
  final VoidCallback onOpenParking;
  final VoidCallback onOpenScraps;
  final void Function(ScrapRecentActivity activity) onOpenScrapActivity;
  final Future<void> Function() onGroupsChanged;
  final ProfileUpdateCallback onUpdateProfile;
  final Future<void> Function() onDeleteAccount;
  final Future<void> Function()? onLogout;

  @override
  State<_HomeDashboardTab> createState() => _HomeDashboardTabState();
}

class _HomeDashboardTabState extends State<_HomeDashboardTab> {
  final _apiClient = ApiClient();

  ScheduleDashboard? _scheduleDashboard;
  ParkingDashboard? _parkingDashboard;
  TravelDashboard? _travelDashboard;
  List<ScrapRecentActivity> _recentScrapActivities = const [];
  String? _message;
  bool _isLoading = true;
  bool _isScheduleLoading = false;
  int _briefingLoadToken = 0;
  late DateTime _scheduleDate;

  @override
  void initState() {
    super.initState();
    _scheduleDate = _dateOnly(DateTime.now());
    final canUseInitialDashboard =
        widget.initialDashboardFamilyId == widget.family.id;
    _scheduleDashboard = canUseInitialDashboard
        ? widget.initialScheduleDashboard
        : null;
    _parkingDashboard = canUseInitialDashboard
        ? widget.initialParkingDashboard
        : null;
    _isLoading = _scheduleDashboard == null && _parkingDashboard == null;

    if (_isLoading) {
      _loadBriefing();
    } else {
      _loadHomeSecondaryBriefing();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateHomeWidget());
  }

  @override
  void didUpdateWidget(covariant _HomeDashboardTab oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.family.id != widget.family.id ||
        oldWidget.sessionToken != widget.sessionToken ||
        oldWidget.refreshToken != widget.refreshToken) {
      setState(() {
        _scheduleDashboard = null;
        _parkingDashboard = null;
        _travelDashboard = null;
        _recentScrapActivities = const [];
        _scheduleDate = _dateOnly(DateTime.now());
        _isLoading = true;
        _isScheduleLoading = false;
        _message = null;
      });
      _loadBriefing();
    }
  }

  Future<void> _loadBriefing() async {
    final loadToken = ++_briefingLoadToken;
    final familyId = widget.family.id;

    setState(() {
      _isLoading = true;
      _isScheduleLoading = false;
      _message = null;
    });

    final dayStart = _scheduleDate;
    final dayEnd = dayStart.add(const Duration(days: 1));

    try {
      final results = await Future.wait([
        _apiClient.getScheduleDashboard(
          widget.sessionToken,
          familyId: familyId,
          rangeStart: dayStart,
          rangeEnd: dayEnd,
        ),
        _apiClient.getParkingDashboard(widget.sessionToken, familyId: familyId),
        _apiClient.getRecentScrapActivities(
          widget.sessionToken,
          familyId: familyId,
        ),
        _apiClient.getTravelDashboard(widget.sessionToken, familyId: familyId),
      ]);
      final schedules = results[0] as ScheduleDashboard;
      final parking = results[1] as ParkingDashboard;
      final recentScrapActivities = results[2] as List<ScrapRecentActivity>;
      final travel = results[3] as TravelDashboard;

      if (!mounted || loadToken != _briefingLoadToken) {
        return;
      }

      setState(() {
        _scheduleDashboard = schedules;
        _parkingDashboard = parking;
        _recentScrapActivities = recentScrapActivities;
        _travelDashboard = travel;
      });
      _updateHomeWidget();
    } catch (error) {
      if (mounted && loadToken == _briefingLoadToken) {
        setState(() {
          _message = error.toString();
        });
      }
    } finally {
      if (mounted && loadToken == _briefingLoadToken) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadHomeSecondaryBriefing() async {
    final loadToken = ++_briefingLoadToken;
    final familyId = widget.family.id;

    try {
      final results = await Future.wait([
        _apiClient.getRecentScrapActivities(
          widget.sessionToken,
          familyId: familyId,
        ),
        _apiClient.getTravelDashboard(widget.sessionToken, familyId: familyId),
      ]);
      final activities = results[0] as List<ScrapRecentActivity>;
      final travel = results[1] as TravelDashboard;

      if (!mounted || loadToken != _briefingLoadToken) {
        return;
      }

      setState(() {
        _recentScrapActivities = activities;
        _travelDashboard = travel;
      });
      _updateHomeWidget();
    } catch (_) {
      // The main home briefing remains usable if secondary content fails.
    }
  }

  Future<void> _openTravelDetail(
    TravelTrip trip, {
    bool initialChecklist = false,
  }) async {
    await Navigator.of(context, rootNavigator: true).push<void>(
      CupertinoPageRoute<void>(
        builder: (_) => TravelDetailScreen(
          family: widget.family,
          sessionToken: widget.sessionToken,
          trip: trip,
          initialChecklist: initialChecklist,
        ),
      ),
    );

    if (mounted) {
      await _loadBriefing();
    }
  }

  Future<AppUser> _updateProfile(
    String nickname, {
    required bool updateFamilyMemberNicknames,
  }) async {
    final user = await widget.onUpdateProfile(
      nickname,
      updateFamilyMemberNicknames: updateFamilyMemberNicknames,
    );

    if (updateFamilyMemberNicknames && mounted) {
      await _loadBriefing();
    }

    return user;
  }

  Future<void> _loadScheduleBriefing(DateTime date) async {
    final loadToken = ++_briefingLoadToken;
    final familyId = widget.family.id;
    final dayStart = _dateOnly(date);
    final dayEnd = dayStart.add(const Duration(days: 1));

    setState(() {
      _scheduleDate = dayStart;
      _isScheduleLoading = true;
      _message = null;
    });

    try {
      final schedules = await _apiClient.getScheduleDashboard(
        widget.sessionToken,
        familyId: familyId,
        rangeStart: dayStart,
        rangeEnd: dayEnd,
      );

      if (!mounted || loadToken != _briefingLoadToken) {
        return;
      }

      setState(() {
        _scheduleDashboard = schedules;
      });
    } catch (error) {
      if (mounted && loadToken == _briefingLoadToken) {
        setState(() {
          _message = error.toString();
        });
      }
    } finally {
      if (mounted && loadToken == _briefingLoadToken) {
        setState(() {
          _isScheduleLoading = false;
        });
      }
    }
  }

  void _changeScheduleDate(int dayOffset) {
    _loadScheduleBriefing(_scheduleDate.add(Duration(days: dayOffset)));
  }

  void _updateHomeWidget() {
    final now = DateTime.now();
    final schedules = [...?_scheduleDashboard?.schedules]
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final memberColors = _homeMemberColors(
      _scheduleDashboard?.members ?? const [],
    );

    final scheduleItems = schedules
        .take(5)
        .map(
          (schedule) => _homeWidgetScheduleItem(
            schedule,
            memberColor:
                memberColors[schedule.familyMemberId] ?? MemberFilterColor.gray,
          ),
        )
        .toList();

    HomeWidgetService.update(
      schedule: HomeWidgetPageData(
        title: '체키 오늘 일정',
        weekday: _homeWidgetWeekday(now),
        day: now.day.toString(),
        fullDate: '${now.month}월 ${now.day}일 ${_homeWidgetWeekday(now)}',
        items: scheduleItems,
        moreCount: schedules.length - scheduleItems.length,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final homeTrips = _homeTravelTrips(_travelDashboard?.trips ?? const []);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: _HomeNotificationButton(
          sessionToken: widget.sessionToken,
          family: widget.family,
          currentUserId: widget.user.id,
          refreshToken: widget.notificationRefreshToken,
          onOpenParkingTab: widget.onOpenParking,
        ),
        middle: _HomeTitle(
          family: widget.family,
          canSwitch: widget.families.length > 1,
          onPressed: widget.onSwitchFamily,
        ),
        trailing: _HomeNavigationTrailing(
          user: widget.user,
          sessionToken: widget.sessionToken,
          familyCount: widget.families.length,
          currentUserId: widget.user.id,
          onGroupsChanged: widget.onGroupsChanged,
          onUpdateProfile: _updateProfile,
          onDeleteAccount: widget.onDeleteAccount,
          onLogout: widget.onLogout,
        ),
      ),
      child: SafeArea(
        child: RefreshableScrollView(
          onRefresh: _loadBriefing,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            if (widget.message != null) ...[
              _InlineMessage(message: widget.message!),
              const SizedBox(height: 14),
            ],
            if (_message != null) ...[
              _InlineMessage(message: _message!),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: CupertinoButton(
                  color: AppColors.darkSurfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  onPressed: _loadBriefing,
                  child: Text(
                    '브리핑 새로고침',
                    style: TextStyle(
                      color: AppColors.darkPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (_isLoading &&
                _scheduleDashboard == null &&
                _parkingDashboard == null)
              Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CupertinoActivityIndicator()),
              )
            else ...[
              _ScheduleBriefingSection(
                schedules: _scheduleDashboard?.schedules ?? const [],
                members: _scheduleDashboard?.members ?? const [],
                selectedDate: _scheduleDate,
                isLoading: _isScheduleLoading,
                onPreviousDate: () => _changeScheduleDate(-1),
                onNextDate: () => _changeScheduleDate(1),
                onPressed: widget.onOpenSchedule,
              ),
              _ParkingBriefingSection(
                dashboard: _parkingDashboard,
                onPressed: widget.onOpenParking,
              ),
              if (homeTrips.isNotEmpty)
                _TravelBriefingSection(
                  trips: homeTrips,
                  onPressed: () => _openTravelDetail(homeTrips.first),
                  onChecklistPressed: (trip) =>
                      _openTravelDetail(trip, initialChecklist: true),
                ),
              if (_recentScrapActivities.isNotEmpty)
                _ScrapBriefingSection(
                  activities: _recentScrapActivities,
                  onPressed: widget.onOpenScraps,
                  onActivityPressed: widget.onOpenScrapActivity,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScheduleBriefingSection extends StatefulWidget {
  const _ScheduleBriefingSection({
    required this.schedules,
    required this.members,
    required this.selectedDate,
    required this.isLoading,
    required this.onPreviousDate,
    required this.onNextDate,
    required this.onPressed,
  });

  final List<AppSchedule> schedules;
  final List<FamilyMember> members;
  final DateTime selectedDate;
  final bool isLoading;
  final VoidCallback onPreviousDate;
  final VoidCallback onNextDate;
  final VoidCallback onPressed;

  @override
  State<_ScheduleBriefingSection> createState() =>
      _ScheduleBriefingSectionState();
}

class _ScheduleBriefingSectionState extends State<_ScheduleBriefingSection> {
  bool _isExpanded = false;

  @override
  void didUpdateWidget(covariant _ScheduleBriefingSection oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.schedules.length != widget.schedules.length ||
        !_isSameDate(oldWidget.selectedDate, widget.selectedDate)) {
      _isExpanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderedSchedules = [...widget.schedules]
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final memberColors = _homeMemberColors(widget.members);
    final visibleSchedules = _isExpanded
        ? orderedSchedules
        : orderedSchedules.take(5);
    final hiddenScheduleCount = orderedSchedules.length - 5;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -250) {
          widget.onNextDate();
        } else if (velocity > 250) {
          widget.onPreviousDate();
        }
      },
      child: _BriefingSection(
        icon: CupertinoIcons.calendar,
        title: _homeScheduleTitle(widget.selectedDate),
        emptyText: '등록된 일정이 없습니다.',
        isEmpty: !widget.isLoading && orderedSchedules.isEmpty,
        onPressed: widget.onPressed,
        children: [
          if (widget.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CupertinoActivityIndicator()),
            )
          else ...[
            for (final schedule in visibleSchedules)
              _ScheduleBriefingTile(
                schedule: schedule,
                memberColor:
                    memberColors[schedule.familyMemberId] ??
                    MemberFilterColor.gray,
              ),
            if (!_isExpanded && hiddenScheduleCount > 0)
              _MoreSchedulesLink(
                hiddenCount: hiddenScheduleCount,
                onPressed: () {
                  setState(() {
                    _isExpanded = true;
                  });
                },
              ),
          ],
        ],
      ),
    );
  }
}

class _MoreSchedulesLink extends StatelessWidget {
  const _MoreSchedulesLink({
    required this.hiddenCount,
    required this.onPressed,
  });

  final int hiddenCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 8),
        child: Text(
          '더보기 +$hiddenCount개',
          style: TextStyle(
            color: AppColors.darkPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _ParkingBriefingSection extends StatelessWidget {
  const _ParkingBriefingSection({
    required this.dashboard,
    required this.onPressed,
  });

  final ParkingDashboard? dashboard;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final parkingDashboard = dashboard;
    final currentLocations = parkingDashboard?.currentLocations ?? const [];
    final vehiclesById = {
      for (final vehicle in parkingDashboard?.vehicles ?? const <Vehicle>[])
        vehicle.id: vehicle,
    };

    return _BriefingSection(
      icon: CupertinoIcons.car_detailed,
      title: '주차 위치',
      emptyText: '등록된 현재 주차 위치가 없습니다.',
      isEmpty: currentLocations.isEmpty,
      onPressed: onPressed,
      children: currentLocations
          .map(
            (record) => _ParkingBriefingTile(
              record: record,
              vehicle: vehiclesById[record.vehicleId],
            ),
          )
          .toList(),
    );
  }
}

class _TravelBriefingSection extends StatelessWidget {
  const _TravelBriefingSection({
    required this.trips,
    required this.onPressed,
    required this.onChecklistPressed,
  });

  final List<TravelTrip> trips;
  final VoidCallback onPressed;
  final void Function(TravelTrip trip) onChecklistPressed;

  @override
  Widget build(BuildContext context) {
    return _BriefingSection(
      icon: CupertinoIcons.airplane,
      title: '여행',
      emptyText: '',
      isEmpty: false,
      onPressed: onPressed,
      trailingActionLabel: '여행 보기',
      children: trips
          .map(
            (trip) => _TravelBriefingTile(
              trip: trip,
              onChecklistPressed: () => onChecklistPressed(trip),
            ),
          )
          .toList(),
    );
  }
}

class _TravelBriefingTile extends StatelessWidget {
  const _TravelBriefingTile({
    required this.trip,
    required this.onChecklistPressed,
  });

  final TravelTrip trip;
  final VoidCallback onChecklistPressed;

  @override
  Widget build(BuildContext context) {
    final isInProgress = _isTravelInProgress(trip);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isInProgress
                  ? AppColors.darkWarning.withValues(alpha: 0.18)
                  : AppColors.darkPrimarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              CupertinoIcons.airplane,
              color: isInProgress
                  ? AppColors.darkWarning
                  : AppColors.darkPrimary,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        trip.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.darkTextPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isInProgress)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.darkWarning.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '여행 중',
                          style: TextStyle(
                            color: AppColors.darkWarning,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            height: 1,
                            letterSpacing: 0,
                          ),
                        ),
                      )
                    else
                      Text(
                        _travelCountdownText(trip.startsOn),
                        style: TextStyle(
                          color: AppColors.darkPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _travelDateText(trip),
                  style: TextStyle(
                    color: AppColors.darkTextSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
                if (trip.checklistItemCount > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '체크리스트 ${trip.checklistCompletedCount}/${trip.checklistItemCount} 완료',
                          style: TextStyle(
                            color: AppColors.darkTextSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      Text(
                        '${trip.checklistCompletionPercent}%',
                        style: TextStyle(
                          color: AppColors.darkPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: SizedBox(
                      height: 4,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(color: AppColors.darkBorder),
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor:
                                trip.checklistCompletedCount /
                                trip.checklistItemCount,
                            child: ColoredBox(color: AppColors.darkPrimary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 5),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: onChecklistPressed,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.checkmark_alt_circle,
                        color: AppColors.darkPrimary,
                        size: 15,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '체크리스트로 가기',
                        style: TextStyle(
                          color: AppColors.darkPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScrapBriefingSection extends StatelessWidget {
  const _ScrapBriefingSection({
    required this.activities,
    required this.onPressed,
    required this.onActivityPressed,
  });

  final List<ScrapRecentActivity> activities;
  final VoidCallback onPressed;
  final void Function(ScrapRecentActivity activity) onActivityPressed;

  @override
  Widget build(BuildContext context) {
    return _BriefingSection(
      icon: CupertinoIcons.bookmark,
      title: '최근 스크랩',
      emptyText: '',
      isEmpty: false,
      onPressed: onPressed,
      trailingActionLabel: '더 보기',
      children: activities
          .map(
            (activity) => _ScrapBriefingTile(
              activity: activity,
              onPressed: () => onActivityPressed(activity),
            ),
          )
          .toList(),
    );
  }
}

class _ScrapBriefingTile extends StatelessWidget {
  const _ScrapBriefingTile({required this.activity, required this.onPressed});

  final ScrapRecentActivity activity;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final activityLabel = activity.type == ScrapRecentActivityType.post
        ? '글'
        : '댓글';
    final previewText = _scrapActivityPreviewText(activity);

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.darkPrimarySoft,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                activity.type == ScrapRecentActivityType.post
                    ? CupertinoIcons.doc_text
                    : CupertinoIcons.chat_bubble,
                color: AppColors.darkPrimary,
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    previewText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.darkTextPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$activityLabel · ${activity.channelName} · '
                    '${activity.authorNickname} · ${_scrapActivityTimeText(activity.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.darkTextSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _scrapActivityPreviewText(ScrapRecentActivity activity) {
  final firstLine = activity.content
      .trim()
      .split(RegExp(r'\r?\n'))
      .first
      .trim();
  final linkTitle = activity.linkTitle?.trim();

  return linkTitle == null || linkTitle.isEmpty ? firstLine : linkTitle;
}

HomeWidgetScheduleItem _homeWidgetScheduleItem(
  AppSchedule schedule, {
  required MemberFilterColor memberColor,
}) {
  final startsAt = schedule.isAllDay
      ? '종일'
      : _homeWidgetTimeText(schedule.startsAt);
  final endsAt = schedule.isAllDay ? '' : _homeWidgetTimeText(schedule.endsAt);
  return HomeWidgetScheduleItem(
    startsAt: startsAt,
    endsAt: endsAt,
    title: schedule.title,
    memberName: schedule.memberNickname,
    memberColor: memberColor.name,
  );
}

String _homeWidgetTimeText(DateTime start) {
  final hour = start.hour.toString().padLeft(2, '0');
  final minute = start.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _homeWidgetWeekday(DateTime date) {
  const labels = <String>['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];
  return labels[date.weekday - 1];
}

class _BriefingSection extends StatelessWidget {
  const _BriefingSection({
    required this.icon,
    required this.title,
    required this.emptyText,
    required this.isEmpty,
    required this.onPressed,
    required this.children,
    this.trailingActionLabel,
  });

  final IconData icon;
  final String title;
  final String emptyText;
  final bool isEmpty;
  final VoidCallback onPressed;
  final List<Widget> children;
  final String? trailingActionLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.darkBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: onPressed,
            child: Row(
              children: [
                Icon(icon, color: AppColors.darkPrimary, size: 21),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.darkTextPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                if (trailingActionLabel != null)
                  Text(
                    trailingActionLabel!,
                    style: TextStyle(
                      color: AppColors.darkPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  )
                else
                  const Icon(
                    CupertinoIcons.chevron_forward,
                    color: CupertinoColors.systemGrey3,
                    size: 17,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      emptyText,
                      style: TextStyle(
                        color: AppColors.darkTextSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  )
                else
                  ...children,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleBriefingTile extends StatelessWidget {
  const _ScheduleBriefingTile({
    required this.schedule,
    required this.memberColor,
  });

  final AppSchedule schedule;
  final MemberFilterColor memberColor;

  @override
  Widget build(BuildContext context) {
    final timeText =
        '${_briefTimeText(schedule.startsAt)}~${_briefTimeText(schedule.endsAt)}';
    final memberColorStyle = MemberFilterColorStyle.from(memberColor);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 100, maxWidth: 116),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.darkPrimarySoft,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppColors.darkPrimary.withValues(alpha: 0.22),
              ),
            ),
            child: Center(
              child: Text(
                timeText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.darkPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    schedule.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.darkTextPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(maxWidth: 96),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: memberColorStyle.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: memberColorStyle.border),
                  ),
                  child: Text(
                    schedule.memberNickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: memberColorStyle.foreground,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ParkingBriefingTile extends StatelessWidget {
  const _ParkingBriefingTile({required this.record, required this.vehicle});

  final ParkingRecord record;
  final Vehicle? vehicle;

  @override
  Widget build(BuildContext context) {
    final vehicleTitle = vehicle == null
        ? '차량'
        : '${vehicle!.nickname} · ${vehicle!.plateNumber}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.darkPrimarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              CupertinoIcons.location_solid,
              color: AppColors.darkPrimary,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vehicleTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.darkTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  record.locationText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.darkTextSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Map<String, MemberFilterColor> _homeMemberColors(List<FamilyMember> members) {
  return {
    for (var index = 0; index < members.length; index++)
      members[index].id:
          MemberFilterColor.fromValue(members[index].color) ??
          MemberFilterColor.values[index % MemberFilterColor.values.length],
  };
}

List<TravelTrip> _homeTravelTrips(List<TravelTrip> trips) {
  final today = _dateOnly(DateTime.now());
  final homeTrips = trips.where((trip) {
    final startsOn = _dateOnly(trip.startsOn);
    final endsOn = _dateOnly(trip.endsOn);
    final daysUntilStart = startsOn.difference(today).inDays;

    return (startsOn.isBefore(today) || _isSameDate(startsOn, today)) &&
            (endsOn.isAfter(today) || _isSameDate(endsOn, today)) ||
        (daysUntilStart >= 0 && daysUntilStart <= 7);
  }).toList();

  homeTrips.sort((a, b) {
    final aIsInProgress = _isTravelInProgress(a, today: today);
    final bIsInProgress = _isTravelInProgress(b, today: today);

    if (aIsInProgress != bIsInProgress) {
      return aIsInProgress ? -1 : 1;
    }

    return a.startsOn.compareTo(b.startsOn);
  });
  return homeTrips;
}

bool _isTravelInProgress(TravelTrip trip, {DateTime? today}) {
  final currentDate = _dateOnly(today ?? DateTime.now());
  final startsOn = _dateOnly(trip.startsOn);
  final endsOn = _dateOnly(trip.endsOn);

  return (startsOn.isBefore(currentDate) ||
          _isSameDate(startsOn, currentDate)) &&
      (endsOn.isAfter(currentDate) || _isSameDate(endsOn, currentDate));
}

String _travelCountdownText(DateTime startsOn) {
  final daysUntilStart = _dateOnly(
    startsOn,
  ).difference(_dateOnly(DateTime.now())).inDays;

  return daysUntilStart == 0 ? 'D-Day' : 'D-$daysUntilStart';
}

String _travelDateText(TravelTrip trip) {
  final startsOn = trip.startsOn;
  final endsOn = trip.endsOn;
  final startsOnText = '${startsOn.month}월 ${startsOn.day}일';

  if (_isSameDate(startsOn, endsOn)) {
    return startsOnText;
  }

  return '$startsOnText ~ ${endsOn.month}월 ${endsOn.day}일';
}

DateTime _dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

bool _isSameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _homeScheduleTitle(DateTime date) {
  final today = _dateOnly(DateTime.now());
  final target = _dateOnly(date);
  final dayDiff = target.difference(today).inDays;

  if (dayDiff == -1) {
    return '어제 일정';
  }
  if (dayDiff == 0) {
    return '오늘 일정';
  }
  if (dayDiff == 1) {
    return '내일 일정';
  }
  if (dayDiff == 2) {
    return '모레 일정';
  }

  return '${target.year}.${_twoDigits(target.month)}.${_twoDigits(target.day)} 일정';
}

String _twoDigits(int value) {
  return value.toString().padLeft(2, '0');
}

String _briefTimeText(DateTime value) {
  return '${_twoDigits(value.hour)}:${_twoDigits(value.minute)}';
}

String _scrapActivityTimeText(DateTime value) {
  final now = DateTime.now();
  final today = _dateOnly(now);
  final target = _dateOnly(value);

  if (_isSameDate(today, target)) {
    return '${_twoDigits(value.hour)}:${_twoDigits(value.minute)}';
  }

  if (value.year == now.year) {
    return '${value.month}.${value.day}';
  }

  return '${value.year}.${value.month}.${value.day}';
}

class _FamilyRequiredIntro extends StatelessWidget {
  const _FamilyRequiredIntro({
    required this.userNickname,
    required this.message,
    required this.onReloadFamilies,
    required this.onOpenFamilyManagement,
  });

  final String userNickname;
  final String? message;
  final Future<void> Function() onReloadFamilies;
  final VoidCallback onOpenFamilyManagement;

  @override
  Widget build(BuildContext context) {
    return RefreshableScrollView(
      onRefresh: onReloadFamilies,
      children: [
        const SizedBox(height: 24),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Icon(
            CupertinoIcons.check_mark_circled_solid,
            color: AppColors.darkPrimary,
            size: 34,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          '$userNickname님,\n체키를 시작해 볼까요?',
          style: TextStyle(
            color: AppColors.darkTextPrimary,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.16,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '체키는 우리의 하루를 함께 체크하는 작은 비서예요. 우리의 일정과 주차 위치를 예쁘게 챙겨요.',
          style: TextStyle(
            color: AppColors.darkTextSecondary,
            fontSize: 16,
            height: 1.45,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _IntroFeaturePill(
                icon: CupertinoIcons.calendar,
                title: '반복 일정 관리',
                description: '반복 일정 시간을 그룹이 함께 확인',
                color: AppColors.darkPrimary,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _IntroFeaturePill(
                icon: CupertinoIcons.car_detailed,
                title: '주차 관리',
                description: '차량별 주차 위치를 빠르게 공유',
                color: AppColors.brandCoral,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '일정, 차량, 주차 기록은 모두 그룹 단위로 저장됩니다. 그룹을 만들거나 초대 링크를 수락하면 홈에서 바로 사용할 수 있어요.',
          style: TextStyle(
            color: AppColors.darkTextMuted,
            fontSize: 14,
            height: 1.42,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 22),
        if (message != null) ...[
          _InlineMessage(message: message!),
          const SizedBox(height: 14),
        ],
        SizedBox(
          height: 54,
          child: CupertinoButton.filled(
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(14),
            onPressed: onOpenFamilyManagement,
            child: const Center(
              child: Text(
                '그룹 등록하기',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 50,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            color: AppColors.darkSurfaceElevated,
            borderRadius: BorderRadius.circular(14),
            onPressed: onReloadFamilies,
            child: Center(
              child: Text(
                '그룹 목록 새로고침',
                style: TextStyle(
                  color: AppColors.darkPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _IntroFeaturePill extends StatelessWidget {
  const _IntroFeaturePill({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.darkTextPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                height: 1.15,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.darkTextSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.3,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.message});

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

String _extractInviteToken(String input) {
  final trimmed = input.trim();
  final uri = Uri.tryParse(trimmed);

  if (uri != null && uri.pathSegments.isNotEmpty) {
    return uri.pathSegments.last;
  }

  if (trimmed.contains('/')) {
    return trimmed.split('/').where((segment) => segment.isNotEmpty).last;
  }

  return trimmed;
}
