import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../design_system/app_colors.dart';
import '../../shared/alert_offset_picker.dart';
import '../../shared/member_filter.dart';
import '../../shared/schedule_section_switcher.dart';
import '../travel/travel_screen.dart';

enum _CalendarMode { month, week, day }

const _phoneChannel = MethodChannel('checky/phone');

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({
    super.key,
    required this.family,
    required this.families,
    required this.sessionToken,
    required this.refreshToken,
    required this.todayRequestToken,
    required this.onSelectFamily,
    this.initialDate,
    this.showInitialDateInMonth = false,
    this.selectedScheduleSection,
    this.onScheduleSectionChanged,
  });

  final AppFamily family;
  final List<AppFamily> families;
  final String sessionToken;
  final int refreshToken;
  final int todayRequestToken;
  final Future<void> Function(AppFamily family) onSelectFamily;
  final DateTime? initialDate;
  final bool showInitialDateInMonth;
  final ScheduleSection? selectedScheduleSection;
  final ValueChanged<ScheduleSection>? onScheduleSectionChanged;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final _apiClient = ApiClient();
  final _calendarPageController = PageController(initialPage: 1);

  late AppFamily _family;
  ScheduleDashboard? _dashboard;
  TravelDashboard? _travelDashboard;
  _CalendarMode _mode = _CalendarMode.month;
  DateTime _anchorDate = _dateOnly(DateTime.now());
  final Set<String> _hiddenMemberIds = <String>{};
  bool _isAnniversaryHidden = false;
  bool _isTravelHidden = false;
  String? _message;
  bool _isLoading = true;
  int _scheduleLoadToken = 0;

  DateTime get _rangeStart => _startOfRange(_anchorDate, _mode);
  DateTime get _rangeEnd => _endOfRange(_anchorDate, _mode);
  DateTime get _prefetchRangeStart {
    final start = _startOfRange(
      _anchorDateForOffset(_anchorDate, _mode, -1),
      _mode,
    );
    return _mode == _CalendarMode.month
        ? start.subtract(const Duration(days: 6))
        : start;
  }

  DateTime get _prefetchRangeEnd {
    final end = _endOfRange(_anchorDateForOffset(_anchorDate, _mode, 1), _mode);
    return _mode == _CalendarMode.month
        ? end.add(const Duration(days: 6))
        : end;
  }

  List<AppSchedule> _filteredSchedulesForRange(
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final dashboard = _dashboard;

    if (dashboard == null) {
      return const [];
    }

    final schedules = dashboard.schedules
        .where(
          (schedule) =>
              schedule.startsAt.isBefore(rangeEnd) &&
              schedule.endsAt.isAfter(rangeStart) &&
              (!_isAnniversaryHidden || schedule.anniversaryId == null) &&
              (schedule.familyMemberId == null ||
                  !_hiddenMemberIds.contains(schedule.familyMemberId)),
        )
        .toList();

    if (_isTravelHidden) {
      return schedules;
    }

    return [...schedules, ..._travelSchedulesForRange(rangeStart, rangeEnd)];
  }

  List<AppSchedule> _travelSchedulesForRange(
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final travelDashboard = _travelDashboard;

    if (travelDashboard == null) {
      return const [];
    }

    final tripsById = {for (final trip in travelDashboard.trips) trip.id: trip};

    return travelDashboard.itineraries
        .map((itinerary) {
          final trip = tripsById[itinerary.tripId];
          if (trip == null) {
            return null;
          }

          final time = itinerary.startsAt;
          final startsAt = DateTime(
            itinerary.itineraryDate.year,
            itinerary.itineraryDate.month,
            itinerary.itineraryDate.day,
            time?.hour ?? 9,
            time?.minute ?? 0,
          );

          return AppSchedule(
            id: 'travel-itinerary-${itinerary.id}',
            familyId: _family.id,
            familyMemberId: null,
            title: itinerary.title,
            content: itinerary.content,
            startsAt: startsAt,
            endsAt: startsAt.add(const Duration(hours: 1)),
            isAllDay: false,
            vehicleBoardingAt: null,
            vehicleDropoffAt: null,
            educationProgramId: null,
            educationProgramName: null,
            educationProgramPhoneContacts: const [],
            anniversaryId: null,
            anniversaryCategory: null,
            alertOffsetMinutes: null,
            memberNickname: trip.title,
            travelTripId: trip.id,
            travelItineraryId: itinerary.id,
          );
        })
        .whereType<AppSchedule>()
        .where(
          (schedule) =>
              schedule.startsAt.isBefore(rangeEnd) &&
              schedule.endsAt.isAfter(rangeStart),
        )
        .toList();
  }

  bool _hasTravelInRange(DateTime rangeStart, DateTime rangeEnd) {
    return (_travelDashboard?.trips ?? const <TravelTrip>[]).any((trip) {
      final tripStart = _dateOnly(trip.startsOn);
      final tripEndExclusive = _dateOnly(
        trip.endsOn,
      ).add(const Duration(days: 1));

      return tripStart.isBefore(rangeEnd) &&
          tripEndExclusive.isAfter(rangeStart);
    });
  }

  @override
  void initState() {
    super.initState();
    _family = widget.family;
    if (widget.initialDate != null) {
      _mode = widget.showInitialDateInMonth
          ? _CalendarMode.month
          : _CalendarMode.day;
      _anchorDate = _dateOnly(widget.initialDate!);
    } else if (widget.todayRequestToken > 0) {
      _setTodayDayViewState();
    }
    _loadSchedules();
  }

  @override
  void dispose() {
    _calendarPageController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ScheduleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.family.id != widget.family.id) {
      _family = widget.family;
      _hiddenMemberIds.clear();
      _isAnniversaryHidden = false;
      _isTravelHidden = false;
      _resetCalendarPage();
      _loadSchedules();
    } else if (oldWidget.todayRequestToken != widget.todayRequestToken) {
      setState(_setTodayDayViewState);
      _resetCalendarPage();
      _loadSchedules();
    } else if (oldWidget.refreshToken != widget.refreshToken) {
      _loadSchedules();
    }
  }

  void _setTodayDayViewState() {
    _mode = _CalendarMode.day;
    _anchorDate = _dateOnly(DateTime.now());
  }

  Future<void> _loadSchedules() async {
    final loadToken = ++_scheduleLoadToken;
    final rangeStart = _prefetchRangeStart;
    final rangeEnd = _prefetchRangeEnd;

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final results = await Future.wait([
        _apiClient.getScheduleDashboard(
          widget.sessionToken,
          familyId: _family.id,
          rangeStart: rangeStart,
          rangeEnd: rangeEnd,
        ),
        _apiClient.getTravelDashboard(
          widget.sessionToken,
          familyId: _family.id,
        ),
      ]);
      final dashboard = results[0] as ScheduleDashboard;
      final travelDashboard = results[1] as TravelDashboard;

      if (mounted && loadToken == _scheduleLoadToken) {
        setState(() {
          _dashboard = dashboard;
          _travelDashboard = travelDashboard;
          _hiddenMemberIds.removeWhere(
            (memberId) =>
                !dashboard.members.any((member) => member.id == memberId),
          );
        });
      }
    } catch (error) {
      if (mounted && loadToken == _scheduleLoadToken) {
        setState(() {
          _message = error.toString();
        });
      }
    } finally {
      if (mounted && loadToken == _scheduleLoadToken) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _runTask(Future<void> Function() task) async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      await task();
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _setMode(_CalendarMode mode) {
    setState(() {
      _mode = mode;
      _anchorDate = _dateOnly(_anchorDate);
    });
    _resetCalendarPage();
    _loadSchedules();
  }

  void _moveRange(int direction) {
    if (_calendarPageController.hasClients) {
      _calendarPageController.animateToPage(
        1 + direction,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    _commitRangeMove(direction);
  }

  void _commitRangeMove(int direction) {
    if (direction == 0) {
      return;
    }

    setState(() {
      _anchorDate = _anchorDateForOffset(_anchorDate, _mode, direction);
    });
    _jumpCalendarToCenter();
    _loadSchedules();
  }

  void _handleCalendarPageChanged(int page) {
    _commitRangeMove(page - 1);
  }

  void _resetCalendarPage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpCalendarToCenter();
    });
  }

  void _jumpCalendarToCenter() {
    if (!mounted || !_calendarPageController.hasClients) {
      return;
    }

    _calendarPageController.jumpToPage(1);
  }

  void _toggleMemberFilter(String memberId) {
    setState(() {
      if (_hiddenMemberIds.contains(memberId)) {
        _hiddenMemberIds.remove(memberId);
      } else {
        _hiddenMemberIds.add(memberId);
      }
    });
  }

  void _toggleAnniversaryFilter() {
    setState(() {
      _isAnniversaryHidden = !_isAnniversaryHidden;
    });
  }

  void _toggleTravelFilter() {
    setState(() {
      _isTravelHidden = !_isTravelHidden;
    });
  }

  Future<void> _switchFamily() async {
    if (widget.families.length < 2) {
      return;
    }

    final selectedFamilyId = await showCupertinoModalPopup<String>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: Text('그룹 전환'),
        actions: widget.families
            .map(
              (family) => CupertinoActionSheetAction(
                isDefaultAction: family.id == _family.id,
                onPressed: () => Navigator.of(popupContext).pop(family.id),
                child: Text(family.name),
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

    final selectedFamily = widget.families.firstWhere(
      (family) => family.id == selectedFamilyId,
    );

    setState(() {
      _family = selectedFamily;
      _dashboard = null;
      _travelDashboard = null;
      _hiddenMemberIds.clear();
    });
    _resetCalendarPage();
    await widget.onSelectFamily(selectedFamily);
    await _loadSchedules();
  }

  Future<void> _openScheduleForm({
    AppSchedule? schedule,
    DateTime? initialDate,
  }) async {
    final dashboard = _dashboard;

    if (dashboard == null || dashboard.members.isEmpty) {
      setState(() {
        _message = '일정을 등록할 그룹 구성원이 필요합니다.';
      });
      return;
    }

    final input = await Navigator.of(context).push<_ScheduleInput>(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ScheduleFormScreen(
          members: dashboard.members,
          educationPrograms: dashboard.educationPrograms,
          schedule: schedule,
          initialDate: initialDate ?? schedule?.startsAt ?? _anchorDate,
        ),
      ),
    );

    if (input == null) {
      return;
    }

    final shouldSave = await _confirmScheduleConflicts(input, schedule);
    if (!shouldSave) {
      return;
    }

    await _runTask(() async {
      if (schedule == null) {
        await _apiClient.createSchedule(
          widget.sessionToken,
          familyId: _family.id,
          familyMemberId: input.familyMemberId,
          title: input.title,
          content: input.content,
          startsAt: input.startsAt,
          endsAt: input.endsAt,
          isAllDay: input.isAllDay,
          vehicleBoardingAt: input.vehicleBoardingAt,
          vehicleDropoffAt: input.vehicleDropoffAt,
          educationProgramId: input.educationProgramId,
          alertOffsetMinutes: input.alertOffsetMinutes,
        );
      } else {
        await _apiClient.updateSchedule(
          widget.sessionToken,
          familyId: _family.id,
          scheduleId: schedule.id,
          familyMemberId: input.familyMemberId,
          title: input.title,
          content: input.content,
          startsAt: input.startsAt,
          endsAt: input.endsAt,
          isAllDay: input.isAllDay,
          vehicleBoardingAt: input.vehicleBoardingAt,
          vehicleDropoffAt: input.vehicleDropoffAt,
          educationProgramId: input.educationProgramId,
          alertOffsetMinutes: input.alertOffsetMinutes,
        );
      }

      await _loadSchedules();
    });
  }

  Future<bool> _confirmScheduleConflicts(
    _ScheduleInput input,
    AppSchedule? editingSchedule,
  ) async {
    try {
      final results = await Future.wait([
        _apiClient.getScheduleDashboard(
          widget.sessionToken,
          familyId: _family.id,
          rangeStart: input.startsAt,
          rangeEnd: input.endsAt,
          includeHolidays: false,
        ),
        _apiClient.getTravelDashboard(
          widget.sessionToken,
          familyId: _family.id,
        ),
      ]);
      final dashboard = results[0] as ScheduleDashboard;
      final travelDashboard = results[1] as TravelDashboard;
      final conflicts = dashboard.schedules
          .where(
            (candidate) =>
                candidate.id != editingSchedule?.id &&
                candidate.familyMemberId == input.familyMemberId &&
                candidate.startsAt.isBefore(input.endsAt) &&
                candidate.endsAt.isAfter(input.startsAt),
          )
          .toList();
      final overlappingTrips = travelDashboard.trips
          .where(
            (trip) =>
                input.startsAt.isBefore(
                  _dateOnly(trip.endsOn).add(const Duration(days: 1)),
                ) &&
                input.endsAt.isAfter(_dateOnly(trip.startsOn)),
          )
          .toList();

      if (conflicts.isEmpty && overlappingTrips.isEmpty) {
        return true;
      }

      if (!mounted) {
        return false;
      }

      final member = dashboard.members.firstWhere(
        (candidate) => candidate.id == input.familyMemberId,
        orElse: () => dashboard.members.first,
      );
      final details = <String>[
        ...conflicts.map(
          (conflict) =>
              '일정 · ${conflict.title} (${_scheduleConflictTimeLabel(conflict)})',
        ),
        ...overlappingTrips.map(
          (trip) => '여행 · ${trip.title} (${_travelConflictDateLabel(trip)})',
        ),
      ];
      final preview = details.take(4).join('\n');
      final remainingCount = details.length - 4;
      final confirmed = await showCupertinoDialog<bool>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('일정이 겹쳐요'),
          content: Text(
            '${member.nickname}의 기존 일정 또는 여행 기간과 겹칩니다.\n\n'
            '$preview'
            '${remainingCount > 0 ? '\n외 $remainingCount개' : ''}\n\n'
            '그래도 저장할까요?',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('그래도 저장'),
            ),
          ],
        ),
      );

      return confirmed == true;
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = '일정 충돌을 확인하지 못했습니다. 잠시 후 다시 시도해 주세요.';
        });
      }
      return false;
    }
  }

  Future<void> _deleteSchedule(AppSchedule schedule) async {
    await _runTask(() async {
      await _apiClient.deleteSchedule(
        widget.sessionToken,
        familyId: _family.id,
        scheduleId: schedule.id,
      );
      await _loadSchedules();
    });
  }

  Future<void> _openScheduleDetail(AppSchedule schedule) async {
    final travelTripId = schedule.travelTripId;
    if (travelTripId != null) {
      TravelTrip? trip;
      for (final candidate in _travelDashboard?.trips ?? const <TravelTrip>[]) {
        if (candidate.id == travelTripId) {
          trip = candidate;
          break;
        }
      }

      if (trip == null) {
        return;
      }
      final travelTrip = trip;
      final itineraryId = schedule.travelItineraryId;

      if (itineraryId == null) {
        return;
      }

      try {
        final detail = await _apiClient.getTravelTripDetail(
          widget.sessionToken,
          familyId: _family.id,
          tripId: travelTrip.id,
        );
        final itinerary = detail.itineraries
            .where((item) => item.id == itineraryId)
            .firstOrNull;

        if (itinerary == null || !mounted) {
          return;
        }

        final changed = await Navigator.of(context).push<bool>(
          CupertinoPageRoute<bool>(
            builder: (_) => TravelItineraryDetailScreen(
              familyId: _family.id,
              sessionToken: widget.sessionToken,
              trip: detail.trip,
              itinerary: itinerary,
              favoriteTags: detail.tags,
            ),
          ),
        );

        if (changed == true && mounted) {
          await _loadSchedules();
        }
      } catch (error) {
        if (mounted) {
          setState(() {
            _message = error.toString();
          });
        }
      }
      return;
    }

    final dashboard = _dashboard;
    final action = await Navigator.of(context).push<String>(
      CupertinoPageRoute(
        builder: (_) => _ScheduleDetailScreen(
          schedule: schedule,
          canManage: dashboard?.canManage ?? false,
        ),
      ),
    );

    if (action == 'edit') {
      await _openScheduleForm(schedule: schedule);
    } else if (action == 'deleteConfirmed') {
      await _deleteSchedule(schedule);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = CupertinoTheme.brightnessOf(context);
    AppColors.useBrightness(brightness);
    final dashboard = _dashboard;
    final memberColors = _memberFilterColors(dashboard?.members ?? const []);
    final schedulesInRange = (dashboard?.schedules ?? const <AppSchedule>[])
        .where(
          (schedule) =>
              schedule.startsAt.isBefore(_rangeEnd) &&
              schedule.endsAt.isAfter(_rangeStart),
        )
        .toList();
    final filterMembers = (dashboard?.members ?? const <FamilyMember>[])
        .where(
          (member) => schedulesInRange.any(
            (schedule) => schedule.familyMemberId == member.id,
          ),
        )
        .toList();
    final hasAnniversarySchedules = schedulesInRange.any(
      (schedule) => schedule.anniversaryId != null,
    );
    final hasTravelInRange = _hasTravelInRange(_rangeStart, _rangeEnd);
    final calendarKey = ValueKey('schedule-calendar-${brightness.name}');

    return CupertinoPageScaffold(
      backgroundColor: AppColors.darkBackground,
      navigationBar: CupertinoNavigationBar(
        middle: _FeatureFamilyTitle(
          family: _family,
          featureName: '일정',
          canSwitch: widget.families.length > 1,
          onPressed: _switchFamily,
        ),
        trailing: dashboard?.canManage == true
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(32, 32),
                onPressed: _isLoading ? null : () => _openScheduleForm(),
                child: const Icon(CupertinoIcons.plus),
              )
            : null,
      ),
      child: SafeArea(
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            CupertinoSliverRefreshControl(onRefresh: _loadSchedules),
            SliverFillRemaining(
              hasScrollBody: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 18, 0, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.selectedScheduleSection != null &&
                        widget.onScheduleSectionChanged != null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: ScheduleSectionSwitcher(
                          selectedSection: widget.selectedScheduleSection!,
                          onSectionChanged: widget.onScheduleSectionChanged!,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _ScheduleHeader(
                        mode: _mode,
                        rangeLabel: _rangeLabel(_rangeStart, _rangeEnd, _mode),
                        canManage: dashboard?.canManage ?? false,
                        members: filterMembers,
                        hiddenMemberIds: _hiddenMemberIds,
                        isAnniversaryHidden: _isAnniversaryHidden,
                        isTravelHidden: _isTravelHidden,
                        hasAnniversarySchedules: hasAnniversarySchedules,
                        hasTravelInRange: hasTravelInRange,
                        memberColors: memberColors,
                        onToggleMemberFilter: _toggleMemberFilter,
                        onToggleAnniversaryFilter: _toggleAnniversaryFilter,
                        onToggleTravelFilter: _toggleTravelFilter,
                        onModeChanged: _setMode,
                        onPrevious: () => _moveRange(-1),
                        onNext: () => _moveRange(1),
                      ),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _InlineMessage(message: _message!),
                      ),
                    ],
                    const SizedBox(height: 18),
                    if (_isLoading && dashboard == null)
                      Expanded(
                        child: Center(child: CupertinoActivityIndicator()),
                      )
                    else if (dashboard == null)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _EmptyState(
                            icon: CupertinoIcons.calendar,
                            title: '일정을 불러오지 못했습니다.',
                            subtitle: '잠시 후 다시 시도해 주세요.',
                            actionLabel: '다시 불러오기',
                            onPressed: _loadSchedules,
                          ),
                        ),
                      )
                    else if (dashboard.members.isEmpty)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _EmptyState(
                            icon: CupertinoIcons.person_2,
                            title: '그룹 구성원이 없습니다.',
                            subtitle: '그룹 구성원이 있어야 누구 일정인지 지정할 수 있습니다.',
                            actionLabel: '다시 불러오기',
                            onPressed: _loadSchedules,
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: _PagedCalendarBoard(
                          key: calendarKey,
                          controller: _calendarPageController,
                          mode: _mode,
                          anchorDate: _anchorDate,
                          schedulesForRange: _filteredSchedulesForRange,
                          holidaysForRange: _holidaysForRange,
                          memberColors: memberColors,
                          canManage: dashboard.canManage,
                          onTapDate: (date) =>
                              _openScheduleForm(initialDate: date),
                          onTapSchedule: _openScheduleDetail,
                          onPageChanged: _handleCalendarPageChanged,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<KoreanHoliday> _holidaysForRange(
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    return (_dashboard?.holidays ?? const <KoreanHoliday>[])
        .where(
          (holiday) =>
              !holiday.date.isBefore(rangeStart) &&
              holiday.date.isBefore(rangeEnd),
        )
        .toList();
  }
}

class _FeatureFamilyTitle extends StatelessWidget {
  const _FeatureFamilyTitle({
    required this.family,
    required this.featureName,
    required this.canSwitch,
    required this.onPressed,
  });

  final AppFamily family;
  final String featureName;
  final bool canSwitch;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final title = '${family.name} $featureName';

    if (!canSwitch) {
      return Text(
        title,
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
              title,
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
          const SizedBox(width: 4),
          const Icon(CupertinoIcons.chevron_down, size: 15),
        ],
      ),
    );
  }
}

class _ScheduleHeader extends StatelessWidget {
  const _ScheduleHeader({
    required this.mode,
    required this.rangeLabel,
    required this.canManage,
    required this.members,
    required this.hiddenMemberIds,
    required this.isAnniversaryHidden,
    required this.isTravelHidden,
    required this.hasAnniversarySchedules,
    required this.hasTravelInRange,
    required this.memberColors,
    required this.onToggleMemberFilter,
    required this.onToggleAnniversaryFilter,
    required this.onToggleTravelFilter,
    required this.onModeChanged,
    required this.onPrevious,
    required this.onNext,
  });

  final _CalendarMode mode;
  final String rangeLabel;
  final bool canManage;
  final List<FamilyMember> members;
  final Set<String> hiddenMemberIds;
  final bool isAnniversaryHidden;
  final bool isTravelHidden;
  final bool hasAnniversarySchedules;
  final bool hasTravelInRange;
  final Map<String, MemberFilterColor> memberColors;
  final ValueChanged<String> onToggleMemberFilter;
  final VoidCallback onToggleAnniversaryFilter;
  final VoidCallback onToggleTravelFilter;
  final ValueChanged<_CalendarMode> onModeChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.darkBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (members.isNotEmpty ||
              hasAnniversarySchedules ||
              hasTravelInRange) ...[
            MemberFilterBar(
              members: members,
              hiddenMemberIds: hiddenMemberIds,
              memberColors: memberColors,
              onToggleMember: onToggleMemberFilter,
              trailingChildren: [
                if (hasAnniversarySchedules)
                  _AnniversaryFilterButton(
                    isActive: !isAnniversaryHidden,
                    onPressed: onToggleAnniversaryFilter,
                  ),
                if (hasTravelInRange)
                  _TravelFilterButton(
                    isActive: !isTravelHidden,
                    onPressed: onToggleTravelFilter,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(30, 32),
                onPressed: onPrevious,
                child: const Icon(CupertinoIcons.chevron_left, size: 20),
              ),
              Expanded(
                child: Text(
                  rangeLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.darkTextPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _CalendarModeSegment(mode: mode, onModeChanged: onModeChanged),
              const SizedBox(width: 2),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(30, 32),
                onPressed: onNext,
                child: const Icon(CupertinoIcons.chevron_right, size: 20),
              ),
            ],
          ),
          if (!canManage) ...[
            const SizedBox(height: 10),
            Text(
              '구성원 권한은 조회만 가능합니다.',
              style: TextStyle(
                color: AppColors.darkTextSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AnniversaryFilterButton extends StatelessWidget {
  const _AnniversaryFilterButton({
    required this.isActive,
    required this.onPressed,
  });

  final bool isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        color: isActive
            ? CupertinoColors.systemPurple
            : AppColors.darkBackground,
        borderRadius: BorderRadius.circular(8),
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive
                  ? CupertinoIcons.check_mark_circled_solid
                  : CupertinoIcons.circle,
              color: isActive ? CupertinoColors.white : AppColors.darkTextMuted,
              size: 13,
            ),
            const SizedBox(width: 4),
            Text(
              '기념일',
              style: TextStyle(
                color: isActive
                    ? CupertinoColors.white
                    : AppColors.darkTextSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TravelFilterButton extends StatelessWidget {
  const _TravelFilterButton({required this.isActive, required this.onPressed});

  final bool isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        color: isActive ? CupertinoColors.systemTeal : AppColors.darkBackground,
        borderRadius: BorderRadius.circular(8),
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive
                  ? CupertinoIcons.check_mark_circled_solid
                  : CupertinoIcons.circle,
              color: isActive ? CupertinoColors.white : AppColors.darkTextMuted,
              size: 13,
            ),
            const SizedBox(width: 4),
            Text(
              '여행',
              style: TextStyle(
                color: isActive
                    ? CupertinoColors.white
                    : AppColors.darkTextSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarModeSegment extends StatelessWidget {
  const _CalendarModeSegment({required this.mode, required this.onModeChanged});

  final _CalendarMode mode;
  final ValueChanged<_CalendarMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return CupertinoSlidingSegmentedControl<_CalendarMode>(
      groupValue: mode,
      padding: const EdgeInsets.all(2),
      children: const {
        _CalendarMode.month: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text('월'),
        ),
        _CalendarMode.week: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text('주'),
        ),
        _CalendarMode.day: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text('일'),
        ),
      },
      onValueChanged: (value) {
        if (value != null) {
          onModeChanged(value);
        }
      },
    );
  }
}

class _PagedCalendarBoard extends StatelessWidget {
  const _PagedCalendarBoard({
    super.key,
    required this.controller,
    required this.mode,
    required this.anchorDate,
    required this.schedulesForRange,
    required this.holidaysForRange,
    required this.memberColors,
    required this.canManage,
    required this.onTapDate,
    required this.onTapSchedule,
    required this.onPageChanged,
  });

  final PageController controller;
  final _CalendarMode mode;
  final DateTime anchorDate;
  final List<AppSchedule> Function(DateTime rangeStart, DateTime rangeEnd)
  schedulesForRange;
  final List<KoreanHoliday> Function(DateTime rangeStart, DateTime rangeEnd)
  holidaysForRange;
  final Map<String, MemberFilterColor> memberColors;
  final bool canManage;
  final ValueChanged<DateTime> onTapDate;
  final ValueChanged<AppSchedule> onTapSchedule;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: controller,
      itemCount: 3,
      onPageChanged: onPageChanged,
      itemBuilder: (context, index) {
        final pageAnchorDate = _anchorDateForOffset(
          anchorDate,
          mode,
          index - 1,
        );
        final rangeStart = _startOfRange(pageAnchorDate, mode);
        final rangeEnd = _endOfRange(pageAnchorDate, mode);
        final holidayRangeStart = mode == _CalendarMode.month
            ? rangeStart.subtract(Duration(days: rangeStart.weekday % 7))
            : rangeStart;
        final holidayRangeEnd = mode == _CalendarMode.month
            ? holidayRangeStart.add(const Duration(days: 42))
            : rangeEnd;
        final board = _CalendarBoard(
          mode: mode,
          rangeStart: rangeStart,
          rangeEnd: rangeEnd,
          anchorDate: pageAnchorDate,
          schedules: schedulesForRange(rangeStart, rangeEnd),
          holidays: holidaysForRange(holidayRangeStart, holidayRangeEnd),
          memberColors: memberColors,
          canManage: canManage,
          onTapDate: onTapDate,
          onTapSchedule: onTapSchedule,
        );

        if (mode == _CalendarMode.month) {
          return SingleChildScrollView(child: board);
        }

        return board;
      },
    );
  }
}

class _CalendarBoard extends StatelessWidget {
  const _CalendarBoard({
    required this.mode,
    required this.rangeStart,
    required this.rangeEnd,
    required this.anchorDate,
    required this.schedules,
    required this.holidays,
    required this.memberColors,
    required this.canManage,
    required this.onTapDate,
    required this.onTapSchedule,
  });

  final _CalendarMode mode;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final DateTime anchorDate;
  final List<AppSchedule> schedules;
  final List<KoreanHoliday> holidays;
  final Map<String, MemberFilterColor> memberColors;
  final bool canManage;
  final ValueChanged<DateTime> onTapDate;
  final ValueChanged<AppSchedule> onTapSchedule;

  @override
  Widget build(BuildContext context) {
    switch (mode) {
      case _CalendarMode.day:
        return _DayCalendar(
          date: rangeStart,
          schedules: schedules,
          holiday: _holidayForDate(holidays, rangeStart),
          memberColors: memberColors,
          canManage: canManage,
          onTapDateTime: onTapDate,
          onTapSchedule: onTapSchedule,
        );
      case _CalendarMode.week:
        return _WeekCalendar(
          weekStart: rangeStart,
          schedules: schedules,
          holidays: holidays,
          memberColors: memberColors,
          canManage: canManage,
          onTapDate: onTapDate,
          onTapSchedule: onTapSchedule,
        );
      case _CalendarMode.month:
        return _MonthCalendar(
          monthStart: DateTime(anchorDate.year, anchorDate.month),
          schedules: schedules,
          holidays: holidays,
          memberColors: memberColors,
          canManage: canManage,
          onTapDate: onTapDate,
          onTapSchedule: onTapSchedule,
        );
    }
  }
}

const double _calendarHourRowHeight = 74.0;
const double _calendarGridHeight = _calendarHourRowHeight * 24;
const double _calendarBottomScrollPadding = 96.0;
const double _dayTimeColumnWidth = 54.0;
const double _weekTimeColumnWidth = 32.0;
const String _educationProgramNoneValue = '__none__';

class _DayCalendar extends StatefulWidget {
  const _DayCalendar({
    required this.date,
    required this.schedules,
    required this.holiday,
    required this.memberColors,
    required this.canManage,
    required this.onTapDateTime,
    required this.onTapSchedule,
  });

  final DateTime date;
  final List<AppSchedule> schedules;
  final KoreanHoliday? holiday;
  final Map<String, MemberFilterColor> memberColors;
  final bool canManage;
  final ValueChanged<DateTime> onTapDateTime;
  final ValueChanged<AppSchedule> onTapSchedule;

  @override
  State<_DayCalendar> createState() => _DayCalendarState();
}

class _DayCalendarState extends State<_DayCalendar> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
      initialScrollOffset: _initialScrollOffset(),
    );
  }

  @override
  void didUpdateWidget(covariant _DayCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.date != widget.date ||
        oldWidget.schedules != widget.schedules) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_initialScrollOffset());
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  double _initialScrollOffset() {
    final targetHour = _initialDayHour(widget.date, widget.schedules);

    return (targetHour * _calendarHourRowHeight).clamp(
      0,
      23 * _calendarHourRowHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _calendarDecoration,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ColoredBox(
            color: AppColors.darkSurfaceElevated,
            child: _CalendarTitleBar(
              title: _dayLabel(widget.date),
              holidayName: widget.holiday?.name,
            ),
          ),
          Container(height: 1, color: AppColors.darkBorder),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              child: SizedBox(
                height: _calendarGridHeight + _calendarBottomScrollPadding,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _TimeAxis(width: _dayTimeColumnWidth),
                    Expanded(
                      child: _TimedDayColumn(
                        date: widget.date,
                        schedules: widget.schedules,
                        memberColors: widget.memberColors,
                        canManage: widget.canManage,
                        onTapDateTime: widget.onTapDateTime,
                        onTapSchedule: widget.onTapSchedule,
                        showLeftBorder: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekCalendar extends StatefulWidget {
  const _WeekCalendar({
    required this.weekStart,
    required this.schedules,
    required this.holidays,
    required this.memberColors,
    required this.canManage,
    required this.onTapDate,
    required this.onTapSchedule,
  });

  final DateTime weekStart;
  final List<AppSchedule> schedules;
  final List<KoreanHoliday> holidays;
  final Map<String, MemberFilterColor> memberColors;
  final bool canManage;
  final ValueChanged<DateTime> onTapDate;
  final ValueChanged<AppSchedule> onTapSchedule;

  @override
  State<_WeekCalendar> createState() => _WeekCalendarState();
}

class _WeekCalendarState extends State<_WeekCalendar> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
      initialScrollOffset: _initialScrollOffset(),
    );
  }

  @override
  void didUpdateWidget(covariant _WeekCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.weekStart != widget.weekStart ||
        oldWidget.schedules != widget.schedules) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_initialScrollOffset());
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  double _initialScrollOffset() {
    final targetHour = _initialWeekHour(widget.weekStart, widget.schedules);

    return (targetHour * _calendarHourRowHeight).clamp(
      0,
      23 * _calendarHourRowHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final days = List.generate(7, (index) {
      return widget.weekStart.add(Duration(days: index));
    });

    return Container(
      decoration: _calendarDecoration,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ColoredBox(
            color: AppColors.darkSurfaceElevated,
            child: Row(
              children: [
                Container(
                  width: _weekTimeColumnWidth,
                  height: 70,
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(color: AppColors.darkBorder),
                    ),
                  ),
                ),
                ...days.map(
                  (day) => Expanded(
                    child: _WeekDayHeader(
                      date: day,
                      holiday: _holidayForDate(widget.holidays, day),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: AppColors.darkBorder),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              child: SizedBox(
                height: _calendarGridHeight + _calendarBottomScrollPadding,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _TimeAxis(width: _weekTimeColumnWidth),
                    ...days.map(
                      (day) => Expanded(
                        child: _TimedDayColumn(
                          date: day,
                          schedules: widget.schedules,
                          memberColors: widget.memberColors,
                          canManage: widget.canManage,
                          onTapDateTime: widget.onTapDate,
                          onTapSchedule: widget.onTapSchedule,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeAxis extends StatelessWidget {
  const _TimeAxis({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: _calendarGridHeight,
      child: Stack(
        children: [
          for (var hour = 0; hour <= 23; hour++)
            Positioned(
              top: hour * _calendarHourRowHeight,
              left: 0,
              right: 0,
              height: _calendarHourRowHeight,
              child: Container(
                padding: const EdgeInsets.only(top: 8, right: 4),
                alignment: Alignment.topRight,
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppColors.darkBorder),
                    right: BorderSide(color: AppColors.darkBorder),
                  ),
                ),
                child: Text(
                  _hourLabel(hour),
                  style: TextStyle(
                    color: AppColors.darkTextMuted,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimedDayColumn extends StatelessWidget {
  const _TimedDayColumn({
    required this.date,
    required this.schedules,
    required this.memberColors,
    required this.canManage,
    required this.onTapDateTime,
    required this.onTapSchedule,
    this.showLeftBorder = false,
  });

  final DateTime date;
  final List<AppSchedule> schedules;
  final Map<String, MemberFilterColor> memberColors;
  final bool canManage;
  final ValueChanged<DateTime> onTapDateTime;
  final ValueChanged<AppSchedule> onTapSchedule;
  final bool showLeftBorder;

  @override
  Widget build(BuildContext context) {
    final layouts = _buildTimedScheduleLayouts(schedules, date);

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = constraints.maxWidth;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (var hour = 0; hour <= 23; hour++)
              Positioned(
                top: hour * _calendarHourRowHeight,
                left: 0,
                right: 0,
                height: _calendarHourRowHeight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: canManage
                      ? () => onTapDateTime(
                          DateTime(date.year, date.month, date.day, hour),
                        )
                      : null,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: AppColors.darkBorder),
                        right: BorderSide(color: AppColors.darkBorder),
                        left: showLeftBorder
                            ? BorderSide(color: AppColors.darkBorder)
                            : BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
            ...layouts.map((layout) {
              final left = (layout.leftFraction * columnWidth) + 3;
              final width = (layout.widthFraction * columnWidth - 6)
                  .clamp(12.0, columnWidth)
                  .toDouble();
              final height = (layout.height - 4)
                  .clamp(24.0, layout.height)
                  .toDouble();

              return Positioned(
                top: layout.top + 2,
                left: left,
                width: width,
                height: height,
                child: _TimedScheduleBlock(
                  schedule: layout.schedule,
                  color: _scheduleMemberColor(layout.schedule, memberColors),
                  onTap: () => onTapSchedule(layout.schedule),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _TimedScheduleBlock extends StatelessWidget {
  const _TimedScheduleBlock({
    required this.schedule,
    required this.color,
    required this.onTap,
  });

  final AppSchedule schedule;
  final MemberFilterColor color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = MemberFilterColorStyle.from(color);

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onTap,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: style.background,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: style.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxHeight = constraints.maxHeight;
            final isNarrow = constraints.maxWidth < 38;
            final showMember = maxHeight >= 46 && !isNarrow;
            final titleLines = _timedScheduleTitleLines(
              height: maxHeight,
              showMember: showMember,
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _calendarTitleLabel(schedule.title),
                    maxLines: titleLines,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                    style: TextStyle(
                      color: style.foreground,
                      fontSize: 9,
                      height: 1.08,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                if (showMember) ...[
                  const SizedBox(height: 2),
                  Text(
                    schedule.memberNickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: style.foreground,
                      fontSize: 8,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

int _timedScheduleTitleLines({
  required double height,
  required bool showMember,
}) {
  final usableHeight = showMember ? height - 18 : height - 8;
  final lineCount = (usableHeight / 10).floor();

  return lineCount.clamp(1, 6).toInt();
}

class _TimedScheduleLayout {
  const _TimedScheduleLayout({
    required this.schedule,
    required this.top,
    required this.height,
    required this.leftFraction,
    required this.widthFraction,
  });

  final AppSchedule schedule;
  final double top;
  final double height;
  final double leftFraction;
  final double widthFraction;
}

List<_TimedScheduleLayout> _buildTimedScheduleLayouts(
  List<AppSchedule> schedules,
  DateTime day,
) {
  final dayStart = _dateOnly(day);
  final dayEnd = dayStart.add(const Duration(days: 1));
  final daySchedules =
      schedules
          .where(
            (schedule) =>
                schedule.startsAt.isBefore(dayEnd) &&
                schedule.endsAt.isAfter(dayStart),
          )
          .toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  final layouts = <_TimedScheduleLayout>[];

  for (var index = 0; index < daySchedules.length;) {
    final group = <AppSchedule>[];
    var groupEnd = _scheduleEndInDay(daySchedules[index], dayEnd);

    while (index < daySchedules.length) {
      final schedule = daySchedules[index];
      final scheduleStart = _scheduleStartInDay(schedule, dayStart);

      if (group.isNotEmpty && !scheduleStart.isBefore(groupEnd)) {
        break;
      }

      group.add(schedule);
      final scheduleEnd = _scheduleEndInDay(schedule, dayEnd);
      if (scheduleEnd.isAfter(groupEnd)) {
        groupEnd = scheduleEnd;
      }
      index += 1;
    }

    layouts.addAll(_buildTimedScheduleGroupLayouts(group, dayStart, dayEnd));
  }

  return layouts;
}

List<_TimedScheduleLayout> _buildTimedScheduleGroupLayouts(
  List<AppSchedule> group,
  DateTime dayStart,
  DateTime dayEnd,
) {
  final columns = <DateTime>[];
  final columnBySchedule = <AppSchedule, int>{};

  for (final schedule in group) {
    final start = _scheduleStartInDay(schedule, dayStart);
    final end = _scheduleEndInDay(schedule, dayEnd);
    var columnIndex = columns.indexWhere(
      (columnEnd) => !start.isBefore(columnEnd),
    );

    if (columnIndex == -1) {
      columnIndex = columns.length;
      columns.add(end);
    } else {
      columns[columnIndex] = end;
    }

    columnBySchedule[schedule] = columnIndex;
  }

  final columnCount = columns.length.clamp(1, group.length).toInt();
  final widthFraction = 1 / columnCount;

  return group.map((schedule) {
    final start = _scheduleStartInDay(schedule, dayStart);
    final end = _scheduleEndInDay(schedule, dayEnd);
    final startMinutes = start.difference(dayStart).inMinutes;
    final durationMinutes = end
        .difference(start)
        .inMinutes
        .clamp(15, 24 * 60)
        .toInt();
    final columnIndex = columnBySchedule[schedule] ?? 0;

    return _TimedScheduleLayout(
      schedule: schedule,
      top: startMinutes / 60 * _calendarHourRowHeight,
      height: (durationMinutes / 60 * _calendarHourRowHeight)
          .clamp(28, _calendarHourRowHeight * 24)
          .toDouble(),
      leftFraction: columnIndex * widthFraction,
      widthFraction: widthFraction,
    );
  }).toList();
}

DateTime _scheduleStartInDay(AppSchedule schedule, DateTime dayStart) {
  if (schedule.startsAt.isBefore(dayStart)) {
    return dayStart;
  }

  return schedule.startsAt;
}

DateTime _scheduleEndInDay(AppSchedule schedule, DateTime dayEnd) {
  if (schedule.endsAt.isAfter(dayEnd)) {
    return dayEnd;
  }

  return schedule.endsAt;
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.monthStart,
    required this.schedules,
    required this.holidays,
    required this.memberColors,
    required this.canManage,
    required this.onTapDate,
    required this.onTapSchedule,
  });

  final DateTime monthStart;
  final List<AppSchedule> schedules;
  final List<KoreanHoliday> holidays;
  final Map<String, MemberFilterColor> memberColors;
  final bool canManage;
  final ValueChanged<DateTime> onTapDate;
  final ValueChanged<AppSchedule> onTapSchedule;

  @override
  Widget build(BuildContext context) {
    final gridStart = monthStart.subtract(
      Duration(days: monthStart.weekday % 7),
    );
    final days = List.generate(
      42,
      (index) => gridStart.add(Duration(days: index)),
    );
    final weeks = List.generate(6, (weekIndex) {
      return days.skip(weekIndex * 7).take(7).toList();
    });

    return Container(
      decoration: _calendarDecoration,
      child: Column(
        children: [
          ColoredBox(
            color: AppColors.darkSurfaceElevated,
            child: Row(
              children: List.generate(
                7,
                (index) => Expanded(
                  child: _MonthWeekdayHeader(
                    label: _calendarWeekdayLabel(index),
                    isWeekend: index == 0 || index == 6,
                  ),
                ),
              ),
            ),
          ),
          Container(height: 1, color: AppColors.darkBorder),
          ...weeks.map(
            (week) => _MonthWeekRow(
              week: week,
              monthStart: monthStart,
              schedules: schedules,
              holidays: holidays,
              memberColors: memberColors,
              canManage: canManage,
              onTapDate: onTapDate,
              onTapSchedule: onTapSchedule,
            ),
          ),
        ],
      ),
    );
  }
}

const double _monthBaseCellHeight = 92.0;
const double _monthCellHeaderHeight = 40.0;
const double _monthScheduleSlotHeight = 17.0;

double _monthWeekRowHeight(int maxScheduleCount) {
  return (_monthCellHeaderHeight + maxScheduleCount * _monthScheduleSlotHeight)
      .clamp(_monthBaseCellHeight, double.infinity)
      .toDouble();
}

class _CalendarTitleBar extends StatelessWidget {
  const _CalendarTitleBar({required this.title, this.holidayName});

  final String title;
  final String? holidayName;

  @override
  Widget build(BuildContext context) {
    final isHoliday = holidayName != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.calendar,
            color: CupertinoColors.systemTeal,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: title),
                  if (isHoliday) ...[
                    const TextSpan(text: ' - '),
                    TextSpan(
                      text: holidayName,
                      style: const TextStyle(color: CupertinoColors.systemRed),
                    ),
                  ],
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.darkTextPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekDayHeader extends StatelessWidget {
  const _WeekDayHeader({required this.date, required this.holiday});

  final DateTime date;
  final KoreanHoliday? holiday;

  @override
  Widget build(BuildContext context) {
    final isToday = _dateOnly(date) == _dateOnly(DateTime.now());
    final isSpecialDay = _isWeekend(date) || holiday != null;

    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: AppColors.darkBorder)),
      ),
      child: Column(
        children: [
          Text(
            _weekdayLabel(date.weekday),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isToday && !isSpecialDay
                  ? CupertinoColors.systemTeal
                  : isSpecialDay
                  ? CupertinoColors.systemRed
                  : AppColors.darkTextSecondary,
              fontSize: 12,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 26,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isToday && !isSpecialDay
                  ? CupertinoColors.systemTeal
                  : null,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${date.day}',
              style: TextStyle(
                color: isToday && !isSpecialDay
                    ? CupertinoColors.white
                    : isSpecialDay
                    ? CupertinoColors.systemRed
                    : AppColors.darkTextPrimary,
                fontSize: 14,
                height: 1.1,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          if (holiday != null) ...[
            const SizedBox(height: 3),
            Text(
              holiday!.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: CupertinoColors.systemRed,
                fontSize: 8,
                height: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MonthWeekdayHeader extends StatelessWidget {
  const _MonthWeekdayHeader({required this.label, required this.isWeekend});

  final String label;
  final bool isWeekend;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: isWeekend
                ? CupertinoColors.systemRed
                : AppColors.darkTextSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _MonthWeekRow extends StatelessWidget {
  const _MonthWeekRow({
    required this.week,
    required this.monthStart,
    required this.schedules,
    required this.holidays,
    required this.memberColors,
    required this.canManage,
    required this.onTapDate,
    required this.onTapSchedule,
  });

  final List<DateTime> week;
  final DateTime monthStart;
  final List<AppSchedule> schedules;
  final List<KoreanHoliday> holidays;
  final Map<String, MemberFilterColor> memberColors;
  final bool canManage;
  final ValueChanged<DateTime> onTapDate;
  final ValueChanged<AppSchedule> onTapSchedule;

  @override
  Widget build(BuildContext context) {
    final segments = _monthScheduleSegmentsForWeek(schedules, week.first);
    final laneCount = segments.fold<int>(
      0,
      (count, segment) => segment.lane + 1 > count ? segment.lane + 1 : count,
    );
    final rowHeight = _monthWeekRowHeight(laneCount);

    return SizedBox(
      height: rowHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dayWidth = constraints.maxWidth / 7;

          return Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: week.map((day) {
                  return Expanded(
                    child: _DateCell(
                      date: day,
                      holiday: _holidayForDate(holidays, day),
                      isInCurrentMonth: day.month == monthStart.month,
                      minHeight: rowHeight,
                      canManage: canManage,
                      onTapDate: () => onTapDate(day),
                    ),
                  );
                }).toList(),
              ),
              for (final segment in segments)
                Positioned(
                  left: dayWidth * segment.startIndex + 2,
                  top:
                      _monthCellHeaderHeight +
                      segment.lane * _monthScheduleSlotHeight,
                  width: dayWidth * segment.daySpan - 4,
                  height: _monthScheduleSlotHeight - 2,
                  child: _MonthScheduleBar(
                    segment: segment,
                    color: _scheduleMemberColor(segment.schedule, memberColors),
                    canManage: canManage,
                    onTap: () => onTapSchedule(segment.schedule),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DateCell extends StatelessWidget {
  const _DateCell({
    required this.date,
    required this.holiday,
    required this.isInCurrentMonth,
    required this.minHeight,
    required this.canManage,
    required this.onTapDate,
  });

  final DateTime date;
  final KoreanHoliday? holiday;
  final bool isInCurrentMonth;
  final double minHeight;
  final bool canManage;
  final VoidCallback onTapDate;

  @override
  Widget build(BuildContext context) {
    final isToday = _dateOnly(date) == _dateOnly(DateTime.now());
    final isSpecialDay = _isWeekend(date) || holiday != null;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: canManage ? onTapDate : null,
      child: Container(
        constraints: BoxConstraints(minHeight: minHeight),
        padding: const EdgeInsets.fromLTRB(5, 5, 5, 5),
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: AppColors.darkBorder),
            bottom: BorderSide(color: AppColors.darkBorder),
          ),
          color: isInCurrentMonth
              ? AppColors.darkSurface
              : AppColors.darkSurfaceElevated.withValues(alpha: 0.42),
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 24,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isToday && !isSpecialDay
                      ? CupertinoColors.systemTeal
                      : null,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  '${date.day}',
                  style: TextStyle(
                    color: isToday && !isSpecialDay
                        ? CupertinoColors.white
                        : isSpecialDay
                        ? CupertinoColors.systemRed
                        : isInCurrentMonth
                        ? AppColors.darkTextPrimary
                        : AppColors.darkTextMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              if (holiday != null)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    holiday!.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CupertinoColors.systemRed,
                      fontSize: 8,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthScheduleBar extends StatelessWidget {
  const _MonthScheduleBar({
    required this.segment,
    required this.color,
    required this.canManage,
    required this.onTap,
  });

  final _MonthScheduleSegment segment;
  final MemberFilterColor color;
  final bool canManage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = MemberFilterColorStyle.from(color);

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: canManage || segment.schedule.travelTripId != null
          ? onTap
          : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: style.background,
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(segment.startsInWeek ? 6 : 2),
            right: Radius.circular(segment.endsInWeek ? 6 : 2),
          ),
          border: Border.all(color: style.border),
        ),
        child: Text(
          _calendarTitleLabel(segment.schedule.title),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: TextStyle(
            color: style.foreground,
            fontSize: 8,
            height: 1.15,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _ScheduleDetailScreen extends StatelessWidget {
  const _ScheduleDetailScreen({
    required this.schedule,
    required this.canManage,
  });

  final AppSchedule schedule;
  final bool canManage;

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text('일정 삭제'),
        content: Text('${schedule.title} 일정을 삭제할까요?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('취소'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      Navigator.of(context).pop('deleteConfirmed');
    }
  }

  Future<void> _callPhoneNumber(
    BuildContext context,
    EducationProgramPhoneContact contact,
  ) async {
    final phoneNumber = contact.phoneNumber.trim();

    if (phoneNumber.isEmpty) {
      return;
    }

    try {
      await _phoneChannel.invokeMethod<void>('dial', {
        'phoneNumber': phoneNumber,
      });
    } catch (_) {
      if (!context.mounted) {
        return;
      }

      await showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text('전화 연결 실패'),
          content: Text('전화 앱을 열 수 없습니다. 번호를 확인해 주세요.'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('확인'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAnniversarySchedule = schedule.anniversaryId != null;
    final canModifySchedule = canManage && !isAnniversarySchedule;
    final allDayEndsOn = _dateOnly(
      schedule.endsAt,
    ).subtract(const Duration(days: 1));
    final showsAllDayRange =
        schedule.isAllDay && allDayEndsOn.isAfter(_dateOnly(schedule.startsAt));

    return CupertinoPageScaffold(
      backgroundColor: AppColors.darkBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text('일정 상세'),
        trailing: canModifySchedule
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(context).pop('edit'),
                child: Text('수정'),
              )
            : null,
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.darkSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.darkBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isAnniversarySchedule) ...[
                    Text(
                      schedule.memberNickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: CupertinoColors.systemTeal,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    schedule.title,
                    style: TextStyle(
                      color: AppColors.darkTextPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.12,
                      letterSpacing: 0,
                    ),
                  ),
                  if (!isAnniversarySchedule && schedule.content != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      schedule.content!,
                      style: TextStyle(
                        color: AppColors.darkTextSecondary,
                        fontSize: 16,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (isAnniversarySchedule)
              _DetailSection(
                children: [
                  _DetailRow(
                    icon: CupertinoIcons.calendar,
                    label: '기념일 날짜',
                    value: _anniversaryDateDetailLabel(schedule.startsAt),
                  ),
                  _DetailDivider(),
                  _DetailRow(
                    icon: CupertinoIcons.bell,
                    label: '알림',
                    value: _anniversaryScheduleAlertLabel(
                      schedule.alertOffsetMinutes,
                    ),
                  ),
                ],
              )
            else ...[
              _DetailSection(
                children: [
                  _DetailRow(
                    icon: CupertinoIcons.person_crop_circle,
                    label: '구성원',
                    value: schedule.memberNickname,
                  ),
                  _DetailDivider(),
                  _DetailRow(
                    icon: CupertinoIcons.building_2_fill,
                    label: '반복 일정',
                    value: schedule.educationProgramName ?? '선택 안 함',
                  ),
                  if (schedule.educationProgramPhoneContacts.isNotEmpty) ...[
                    for (final contact
                        in schedule.educationProgramPhoneContacts) ...[
                      _DetailDivider(),
                      _PhoneDetailRow(
                        contact: contact,
                        onPressed: () => _callPhoneNumber(context, contact),
                      ),
                    ],
                  ],
                  _DetailDivider(),
                  if (schedule.isAllDay) ...[
                    if (showsAllDayRange) ...[
                      _DetailRow(
                        icon: CupertinoIcons.calendar,
                        label: 'From',
                        value: _dayLabel(schedule.startsAt),
                      ),
                      _DetailDivider(),
                      _DetailRow(
                        icon: CupertinoIcons.calendar,
                        label: 'To',
                        value: _dayLabel(allDayEndsOn),
                      ),
                    ] else
                      _DetailRow(
                        icon: CupertinoIcons.calendar,
                        label: '날짜',
                        value: _dayLabel(schedule.startsAt),
                      ),
                    _DetailDivider(),
                    _DetailSwitchRow(label: '종일', value: true),
                  ] else ...[
                    _DetailRow(
                      icon: CupertinoIcons.calendar,
                      label: 'From',
                      value: _fullDateTimeLabel(schedule.startsAt),
                    ),
                    _DetailDivider(),
                    _DetailSwitchRow(label: '종일', value: false),
                    _DetailDivider(),
                    _DetailRow(
                      icon: CupertinoIcons.clock,
                      label: 'To',
                      value: _fullDateTimeLabel(schedule.endsAt),
                    ),
                  ],
                  _DetailDivider(),
                  _DetailRow(
                    icon: CupertinoIcons.bell,
                    label: '알림',
                    value: alertOffsetLabel(schedule.alertOffsetMinutes),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _DetailSection(
                children: [
                  _DetailRow(
                    icon: CupertinoIcons.car_detailed,
                    label: '차량승차시각',
                    value: schedule.vehicleBoardingAt == null
                        ? '선택 안 함'
                        : _fullDateTimeLabel(schedule.vehicleBoardingAt!),
                  ),
                  _DetailDivider(),
                  _DetailRow(
                    icon: CupertinoIcons.location,
                    label: '차량하차시각',
                    value: schedule.vehicleDropoffAt == null
                        ? '선택 안 함'
                        : _fullDateTimeLabel(schedule.vehicleDropoffAt!),
                  ),
                ],
              ),
            ],
            if (canModifySchedule) ...[
              const SizedBox(height: 18),
              SizedBox(
                height: 56,
                child: CupertinoButton(
                  color: AppColors.darkSurfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  minimumSize: const Size.fromHeight(56),
                  padding: EdgeInsets.zero,
                  onPressed: () => _confirmDelete(context),
                  child: Text(
                    '일정 삭제',
                    style: TextStyle(
                      color: CupertinoColors.destructiveRed,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(children: children),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: CupertinoColors.systemTeal, size: 19),
          const SizedBox(width: 10),
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.darkTextSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: AppColors.darkTextPrimary,
                fontSize: 15,
                height: 1.35,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSwitchRow extends StatelessWidget {
  const _DetailSwitchRow({required this.label, required this.value});

  final String label;
  final bool value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.checkmark_circle,
            color: CupertinoColors.systemTeal,
            size: 19,
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.darkTextSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Spacer(),
          CupertinoSwitch(value: value, onChanged: null),
        ],
      ),
    );
  }
}

class _PhoneDetailRow extends StatelessWidget {
  const _PhoneDetailRow({required this.contact, required this.onPressed});

  final EducationProgramPhoneContact contact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.phone_fill,
              color: CupertinoColors.systemTeal,
              size: 19,
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 86,
              child: Text(
                contact.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.darkTextSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
            Expanded(
              child: Text(
                contact.phoneNumber,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: CupertinoColors.systemTeal,
                  fontSize: 15,
                  height: 1.35,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              CupertinoIcons.phone_arrow_up_right,
              color: CupertinoColors.systemTeal,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: AppColors.darkBorder);
  }
}

class _ScheduleFormScreen extends StatefulWidget {
  const _ScheduleFormScreen({
    required this.members,
    required this.educationPrograms,
    required this.initialDate,
    this.schedule,
  });

  final List<FamilyMember> members;
  final List<EducationProgram> educationPrograms;
  final DateTime initialDate;
  final AppSchedule? schedule;

  @override
  State<_ScheduleFormScreen> createState() => _ScheduleFormScreenState();
}

class _ScheduleFormScreenState extends State<_ScheduleFormScreen> {
  late String _familyMemberId;
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late DateTime _startsAt;
  late DateTime _endsAt;
  late bool _isAllDay;
  DateTime? _vehicleBoardingAt;
  DateTime? _vehicleDropoffAt;
  String? _educationProgramId;
  int? _alertOffsetMinutes;
  String? _message;

  @override
  void initState() {
    super.initState();
    final schedule = widget.schedule;
    _familyMemberId = schedule?.familyMemberId ?? widget.members.first.id;
    _titleController = TextEditingController(text: schedule?.title);
    _contentController = TextEditingController(text: schedule?.content);
    _startsAt = schedule?.startsAt ?? _defaultStartAt(widget.initialDate);
    _endsAt = schedule?.endsAt ?? _startsAt.add(const Duration(hours: 1));
    _isAllDay = schedule?.isAllDay ?? false;
    if (_isAllDay) {
      _startsAt = _dateOnly(_startsAt);
      _endsAt = _dateOnly(_endsAt);
      if (!_endsAt.isAfter(_startsAt)) {
        _endsAt = _startsAt.add(const Duration(days: 1));
      }
    }
    _vehicleBoardingAt = schedule?.vehicleBoardingAt;
    _vehicleDropoffAt = schedule?.vehicleDropoffAt;
    _educationProgramId = schedule?.educationProgramId;
    _alertOffsetMinutes = schedule?.alertOffsetMinutes;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickMember() async {
    final selectedId = await showCupertinoModalPopup<String>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: Text('그룹 구성원'),
        actions: widget.members
            .map(
              (member) => CupertinoActionSheetAction(
                isDefaultAction: member.id == _familyMemberId,
                onPressed: () => Navigator.of(popupContext).pop(member.id),
                child: Text(member.nickname),
              ),
            )
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popupContext).pop(),
          child: Text('취소'),
        ),
      ),
    );

    if (selectedId != null) {
      setState(() {
        _familyMemberId = selectedId;
        if (!_educationProgramBelongsToMember(
          _educationProgramId,
          selectedId,
        )) {
          _educationProgramId = null;
        }
      });
    }
  }

  Future<void> _pickEducationProgram() async {
    final educationPrograms = _educationProgramsForSelectedMember();

    final selectedId = await showCupertinoModalPopup<String>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: Text('반복 일정 템플릿'),
        actions: [
          CupertinoActionSheetAction(
            isDefaultAction: _educationProgramId == null,
            onPressed: () =>
                Navigator.of(popupContext).pop(_educationProgramNoneValue),
            child: Text('선택 안 함'),
          ),
          ...educationPrograms.map(
            (program) => CupertinoActionSheetAction(
              isDefaultAction: program.id == _educationProgramId,
              onPressed: () => Navigator.of(popupContext).pop(program.id),
              child: Text(program.name),
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popupContext).pop(),
          child: Text('취소'),
        ),
      ),
    );

    if (!mounted || selectedId == null) {
      return;
    }

    setState(() {
      _educationProgramId = selectedId == _educationProgramNoneValue
          ? null
          : selectedId;
    });
  }

  List<EducationProgram> _educationProgramsForSelectedMember() {
    return widget.educationPrograms
        .where((program) => program.familyMemberId == _familyMemberId)
        .toList();
  }

  bool _educationProgramBelongsToMember(
    String? educationProgramId,
    String familyMemberId,
  ) {
    if (educationProgramId == null) {
      return true;
    }

    return widget.educationPrograms.any((program) {
      return program.id == educationProgramId &&
          program.familyMemberId == familyMemberId;
    });
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final initial = isStart ? _startsAt : _endsAt;
    final picked = await _showDateTimePicker(initial);

    if (picked == null) {
      return;
    }

    setState(() {
      if (isStart) {
        final previousDuration = _endsAt.difference(_startsAt);
        _startsAt = picked;
        _endsAt = picked.add(
          previousDuration.isNegative || previousDuration.inMinutes == 0
              ? const Duration(hours: 1)
              : previousDuration,
        );
      } else {
        _endsAt = picked;
      }
    });
  }

  Future<void> _pickAllDayDate({required bool isStart}) async {
    final initial = isStart
        ? _startsAt
        : _endsAt.subtract(const Duration(days: 1));
    final picked = await _showDatePicker(initial);

    if (picked == null) {
      return;
    }

    final selectedDate = _dateOnly(picked);
    setState(() {
      if (isStart) {
        final duration = _endsAt.difference(_startsAt);
        _startsAt = selectedDate;
        _endsAt = selectedDate.add(
          duration.inDays < 1 ? const Duration(days: 1) : duration,
        );
        return;
      }

      if (selectedDate.isBefore(_startsAt)) {
        _message = '종료 날짜는 시작 날짜와 같거나 이후여야 합니다.';
        return;
      }

      _message = null;
      _endsAt = selectedDate.add(const Duration(days: 1));
    });
  }

  void _setAllDay(bool value) {
    setState(() {
      _isAllDay = value;
      if (value) {
        _startsAt = _dateOnly(_startsAt);
        _endsAt = _dateOnly(_endsAt);
        if (!_endsAt.isAfter(_startsAt)) {
          _endsAt = _startsAt.add(const Duration(days: 1));
        }
      } else {
        _endsAt = _startsAt.add(const Duration(hours: 1));
      }
    });
  }

  Future<void> _pickOptionalDateTime({required bool isBoarding}) async {
    final current = isBoarding ? _vehicleBoardingAt : _vehicleDropoffAt;
    final picked = await _showDateTimePicker(current ?? _startsAt);

    if (picked == null) {
      return;
    }

    setState(() {
      if (isBoarding) {
        _vehicleBoardingAt = picked;
      } else {
        _vehicleDropoffAt = picked;
      }
    });
  }

  Future<DateTime?> _showDateTimePicker(DateTime initial) async {
    return showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (popupContext) => _DateTimeInputSheet(
        initial: initial,
        onCancel: () => Navigator.of(popupContext).pop(),
        onDone: (value) => Navigator.of(popupContext).pop(value),
      ),
    );
  }

  Future<DateTime?> _showDatePicker(DateTime initial) async {
    return showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (popupContext) => _DateTimeInputSheet(
        initial: initial,
        showTime: false,
        onCancel: () => Navigator.of(popupContext).pop(),
        onDone: (value) => Navigator.of(popupContext).pop(value),
      ),
    );
  }

  Future<void> _pickAlertOffset() async {
    final picked = await pickAlertOffset(
      context,
      currentValue: _alertOffsetMinutes,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _alertOffsetMinutes = picked;
    });
  }

  void _submit() {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty) {
      setState(() {
        _message = '제목을 입력해 주세요.';
      });
      return;
    }

    if (_endsAt.isBefore(_startsAt)) {
      setState(() {
        _message = '종료 시각은 시작 시각 이후여야 합니다.';
      });
      return;
    }

    Navigator.of(context).pop(
      _ScheduleInput(
        familyMemberId: _familyMemberId,
        title: title,
        content: content.isEmpty ? null : content,
        startsAt: _startsAt,
        endsAt: _endsAt,
        isAllDay: _isAllDay,
        vehicleBoardingAt: _vehicleBoardingAt,
        vehicleDropoffAt: _vehicleDropoffAt,
        educationProgramId: _educationProgramId,
        alertOffsetMinutes: _alertOffsetMinutes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedMember = widget.members.firstWhere(
      (member) => member.id == _familyMemberId,
      orElse: () => widget.members.first,
    );
    final selectedMemberEducationPrograms =
        _educationProgramsForSelectedMember();
    EducationProgram? selectedEducationProgram;
    for (final program in selectedMemberEducationPrograms) {
      if (program.id == _educationProgramId) {
        selectedEducationProgram = program;
        break;
      }
    }

    return CupertinoPageScaffold(
      backgroundColor: AppColors.darkBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.schedule == null ? '일정 등록' : '일정 수정'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: Text('취소'),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _submit,
          child: Text('저장'),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            _FormSection(
              children: [
                _PickerRow(
                  label: '구성원',
                  value: selectedMember.nickname,
                  onPressed: _pickMember,
                ),
                if (selectedMemberEducationPrograms.isNotEmpty) ...[
                  _FormDivider(),
                  _PickerRow(
                    label: '반복 일정',
                    value: selectedEducationProgram?.name ?? '선택 안 함',
                    onPressed: _pickEducationProgram,
                  ),
                ],
                _FormDivider(),
                CupertinoTextField.borderless(
                  controller: _titleController,
                  placeholder: '제목',
                  maxLength: 80,
                  style: TextStyle(fontSize: 17, letterSpacing: 0),
                ),
                _FormDivider(),
                CupertinoTextField.borderless(
                  controller: _contentController,
                  placeholder: '내용',
                  maxLines: 4,
                  maxLength: 1000,
                  style: TextStyle(fontSize: 16, letterSpacing: 0),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _FormSection(
              children: [
                _ScheduleAllDayRow(value: _isAllDay, onChanged: _setAllDay),
                _FormDivider(),
                if (_isAllDay) ...[
                  _PickerRow(
                    label: '시작 날짜',
                    value: _dayLabel(_startsAt),
                    onPressed: () => _pickAllDayDate(isStart: true),
                  ),
                  _FormDivider(),
                  _PickerRow(
                    label: '종료 날짜',
                    value: _dayLabel(_endsAt.subtract(const Duration(days: 1))),
                    onPressed: () => _pickAllDayDate(isStart: false),
                  ),
                ] else ...[
                  _PickerRow(
                    label: '시작 시각',
                    value: _dateTimeLabel(_startsAt),
                    onPressed: () => _pickDateTime(isStart: true),
                  ),
                  _FormDivider(),
                  _PickerRow(
                    label: '종료 시각',
                    value: _dateTimeLabel(_endsAt),
                    onPressed: () => _pickDateTime(isStart: false),
                  ),
                ],
                _FormDivider(),
                _PickerRow(
                  label: '알림',
                  value: alertOffsetLabel(_alertOffsetMinutes),
                  onPressed: _pickAlertOffset,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _FormSection(
              children: [
                _OptionalTimeRow(
                  label: '차량승차시각',
                  value: _vehicleBoardingAt,
                  onPick: () => _pickOptionalDateTime(isBoarding: true),
                  onClear: () => setState(() => _vehicleBoardingAt = null),
                ),
                _FormDivider(),
                _OptionalTimeRow(
                  label: '차량하차시각',
                  value: _vehicleDropoffAt,
                  onPick: () => _pickOptionalDateTime(isBoarding: false),
                  onClear: () => setState(() => _vehicleDropoffAt = null),
                ),
              ],
            ),
            if (_message != null) ...[
              const SizedBox(height: 14),
              _InlineMessage(message: _message!),
            ],
          ],
        ),
      ),
    );
  }
}

class _FormSection extends StatelessWidget {
  const _FormSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(children: children),
    );
  }
}

class _FormDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: AppColors.darkBorder);
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.label,
    required this.value,
    required this.onPressed,
  });

  final String label;
  final String value;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            SizedBox(
              width: 82,
              child: Text(
                label,
                style: TextStyle(
                  color: AppColors.darkTextPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: onPressed == null
                      ? AppColors.darkTextSecondary
                      : CupertinoColors.systemBlue,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleAllDayRow extends StatelessWidget {
  const _ScheduleAllDayRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Text(
            '종일',
            style: TextStyle(
              color: AppColors.darkTextPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          CupertinoSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _OptionalTimeRow extends StatelessWidget {
  const _OptionalTimeRow({
    required this.label,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: Row(
        children: [
          Expanded(
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: onPick,
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.darkTextPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      value == null ? '선택 안 함' : _dateTimeLabel(value!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: AppColors.darkTextSecondary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (value != null)
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(28, 34),
              onPressed: onClear,
              child: const Icon(
                CupertinoIcons.xmark_circle_fill,
                color: CupertinoColors.systemGrey,
                size: 18,
              ),
            ),
        ],
      ),
    );
  }
}

class _DateTimeInputSheet extends StatefulWidget {
  const _DateTimeInputSheet({
    required this.initial,
    this.showTime = true,
    required this.onCancel,
    required this.onDone,
  });

  final DateTime initial;
  final bool showTime;
  final VoidCallback onCancel;
  final ValueChanged<DateTime> onDone;

  @override
  State<_DateTimeInputSheet> createState() => _DateTimeInputSheetState();
}

class _DateTimeInputSheetState extends State<_DateTimeInputSheet> {
  late final TextEditingController _yearController;
  late final TextEditingController _monthController;
  late final TextEditingController _dayController;
  late final TextEditingController _hourController;
  late final TextEditingController _minuteController;
  late bool _isPm;
  String? _message;

  @override
  void initState() {
    super.initState();
    final displayHour = widget.initial.hour % 12 == 0
        ? 12
        : widget.initial.hour % 12;
    _yearController = TextEditingController(text: '${widget.initial.year}');
    _monthController = TextEditingController(text: _two(widget.initial.month));
    _dayController = TextEditingController(text: _two(widget.initial.day));
    _hourController = TextEditingController(text: _two(displayHour));
    _minuteController = TextEditingController(
      text: _two(widget.initial.minute),
    );
    _isPm = widget.initial.hour >= 12;
  }

  @override
  void dispose() {
    _yearController.dispose();
    _monthController.dispose();
    _dayController.dispose();
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  void _submit() {
    final year = int.tryParse(_yearController.text);
    final month = int.tryParse(_monthController.text);
    final day = int.tryParse(_dayController.text);
    final hour = widget.showTime ? int.tryParse(_hourController.text) : 12;
    final minute = widget.showTime ? int.tryParse(_minuteController.text) : 0;

    if (year == null ||
        month == null ||
        day == null ||
        hour == null ||
        minute == null) {
      setState(() => _message = '날짜와 시각을 숫자로 입력해 주세요.');
      return;
    }

    if (month < 1 || month > 12) {
      setState(() => _message = '월은 1부터 12까지 입력해 주세요.');
      return;
    }

    if (widget.showTime && (hour < 1 || hour > 12)) {
      setState(() => _message = '시는 1부터 12까지 입력해 주세요.');
      return;
    }

    if (widget.showTime && (minute < 0 || minute > 59)) {
      setState(() => _message = '분은 0부터 59까지 입력해 주세요.');
      return;
    }

    final convertedHour = _isPm
        ? (hour == 12 ? 12 : hour + 12)
        : (hour == 12 ? 0 : hour);
    final value = DateTime(
      year,
      month,
      day,
      widget.showTime ? convertedHour : 0,
      minute,
    );
    if (value.year != year || value.month != month || value.day != day) {
      setState(() => _message = '존재하는 날짜를 입력해 주세요.');
      return;
    }

    widget.onDone(value);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.darkSurface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 14,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 52,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: widget.onCancel,
                      child: Text('취소'),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _submit,
                      child: Text('완료'),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _NumberInputField(
                      controller: _yearController,
                      placeholder: '2026',
                      suffix: '년',
                      maxLength: 4,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _NumberInputField(
                      controller: _monthController,
                      placeholder: '06',
                      suffix: '월',
                      maxLength: 2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _NumberInputField(
                      controller: _dayController,
                      placeholder: '27',
                      suffix: '일',
                      maxLength: 2,
                    ),
                  ),
                ],
              ),
              if (widget.showTime) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    CupertinoSlidingSegmentedControl<bool>(
                      groupValue: _isPm,
                      children: const {
                        false: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text('오전'),
                        ),
                        true: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text('오후'),
                        ),
                      },
                      onValueChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _isPm = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _NumberInputField(
                        controller: _hourController,
                        placeholder: '3',
                        suffix: '시',
                        maxLength: 2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _NumberInputField(
                        controller: _minuteController,
                        placeholder: '30',
                        suffix: '분',
                        maxLength: 2,
                      ),
                    ),
                  ],
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(
                  _message!,
                  style: TextStyle(
                    color: AppColors.darkDanger,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NumberInputField extends StatelessWidget {
  const _NumberInputField({
    required this.controller,
    required this.placeholder,
    required this.suffix,
    required this.maxLength,
  });

  final TextEditingController controller;
  final String placeholder;
  final String suffix;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: CupertinoTextField(
            controller: controller,
            placeholder: placeholder,
            maxLength: maxLength,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            style: TextStyle(
              color: AppColors.darkTextPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
            decoration: BoxDecoration(
              color: AppColors.darkBackground,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.darkBorder),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          suffix,
          style: TextStyle(
            color: AppColors.darkTextSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        children: [
          Icon(icon, color: CupertinoColors.systemGrey, size: 34),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.darkTextPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.darkTextSecondary,
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
          if (onPressed != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 46,
              child: CupertinoButton.filled(
                borderRadius: BorderRadius.circular(12),
                onPressed: onPressed,
                child: Text(
                  actionLabel,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
          ],
        ],
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

class _ScheduleInput {
  const _ScheduleInput({
    required this.familyMemberId,
    required this.title,
    required this.content,
    required this.startsAt,
    required this.endsAt,
    required this.isAllDay,
    required this.vehicleBoardingAt,
    required this.vehicleDropoffAt,
    required this.educationProgramId,
    required this.alertOffsetMinutes,
  });

  final String familyMemberId;
  final String title;
  final String? content;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isAllDay;
  final DateTime? vehicleBoardingAt;
  final DateTime? vehicleDropoffAt;
  final String? educationProgramId;
  final int? alertOffsetMinutes;
}

DateTime _startOfRange(DateTime date, _CalendarMode mode) {
  final day = _dateOnly(date);

  switch (mode) {
    case _CalendarMode.day:
      return day;
    case _CalendarMode.week:
      return day.subtract(Duration(days: day.weekday % 7));
    case _CalendarMode.month:
      return DateTime(day.year, day.month);
  }
}

DateTime _endOfRange(DateTime date, _CalendarMode mode) {
  switch (mode) {
    case _CalendarMode.day:
      return _startOfRange(date, mode).add(const Duration(days: 1));
    case _CalendarMode.week:
      return _startOfRange(date, mode).add(const Duration(days: 7));
    case _CalendarMode.month:
      final start = _startOfRange(date, mode);
      return DateTime(start.year, start.month + 1);
  }
}

DateTime _anchorDateForOffset(
  DateTime anchorDate,
  _CalendarMode mode,
  int offset,
) {
  switch (mode) {
    case _CalendarMode.day:
      return _dateOnly(anchorDate).add(Duration(days: offset));
    case _CalendarMode.week:
      return _dateOnly(anchorDate).add(Duration(days: 7 * offset));
    case _CalendarMode.month:
      return DateTime(anchorDate.year, anchorDate.month + offset, 1);
  }
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

bool _isWeekend(DateTime date) =>
    date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

KoreanHoliday? _holidayForDate(List<KoreanHoliday> holidays, DateTime date) {
  final target = _dateOnly(date);
  for (final holiday in holidays) {
    if (_dateOnly(holiday.date) == target) {
      return holiday;
    }
  }

  return null;
}

DateTime _defaultStartAt(DateTime initialDate) {
  if (initialDate.hour == 0 && initialDate.minute == 0) {
    return DateTime(initialDate.year, initialDate.month, initialDate.day, 15);
  }

  return initialDate;
}

BoxDecoration get _calendarDecoration => BoxDecoration(
  color: AppColors.darkSurface,
  border: Border(
    top: BorderSide(color: AppColors.darkBorder),
    bottom: BorderSide(color: AppColors.darkBorder),
  ),
);

List<_MonthScheduleSegment> _monthScheduleSegmentsForWeek(
  List<AppSchedule> schedules,
  DateTime weekStart,
) {
  final weekEnd = weekStart.add(const Duration(days: 7));
  final candidates =
      schedules
          .where(
            (schedule) =>
                schedule.startsAt.isBefore(weekEnd) &&
                schedule.endsAt.isAfter(weekStart),
          )
          .map((schedule) {
            final scheduleStart = _dateOnly(schedule.startsAt);
            final scheduleEnd = _scheduleEndDateExclusive(schedule);
            final clippedStart = scheduleStart.isBefore(weekStart)
                ? weekStart
                : scheduleStart;
            final clippedEnd = scheduleEnd.isAfter(weekEnd)
                ? weekEnd
                : scheduleEnd;
            final startIndex = clippedStart.difference(weekStart).inDays;
            final daySpan = clippedEnd
                .difference(clippedStart)
                .inDays
                .clamp(1, 7);

            return _MonthScheduleSegmentDraft(
              schedule: schedule,
              startIndex: startIndex.clamp(0, 6),
              daySpan: daySpan,
              startsInWeek: !scheduleStart.isBefore(weekStart),
              endsInWeek: !scheduleEnd.isAfter(weekEnd),
            );
          })
          .toList()
        ..sort((a, b) {
          final startCompare = a.startIndex.compareTo(b.startIndex);
          if (startCompare != 0) {
            return startCompare;
          }

          final spanCompare = b.daySpan.compareTo(a.daySpan);
          if (spanCompare != 0) {
            return spanCompare;
          }

          return a.schedule.startsAt.compareTo(b.schedule.startsAt);
        });

  final laneEnds = <int>[];
  final segments = <_MonthScheduleSegment>[];

  for (final draft in candidates) {
    var lane = laneEnds.indexWhere((endIndex) => endIndex <= draft.startIndex);
    if (lane == -1) {
      lane = laneEnds.length;
      laneEnds.add(0);
    }

    final endIndex = (draft.startIndex + draft.daySpan).clamp(1, 7);
    laneEnds[lane] = endIndex;
    segments.add(draft.toSegment(lane: lane));
  }

  return segments;
}

DateTime _scheduleEndDateExclusive(AppSchedule schedule) {
  final endDate = _dateOnly(schedule.endsAt);

  if (schedule.endsAt == endDate) {
    return endDate;
  }

  return endDate.add(const Duration(days: 1));
}

class _MonthScheduleSegmentDraft {
  const _MonthScheduleSegmentDraft({
    required this.schedule,
    required this.startIndex,
    required this.daySpan,
    required this.startsInWeek,
    required this.endsInWeek,
  });

  final AppSchedule schedule;
  final int startIndex;
  final int daySpan;
  final bool startsInWeek;
  final bool endsInWeek;

  _MonthScheduleSegment toSegment({required int lane}) {
    return _MonthScheduleSegment(
      schedule: schedule,
      startIndex: startIndex,
      daySpan: daySpan,
      lane: lane,
      startsInWeek: startsInWeek,
      endsInWeek: endsInWeek,
    );
  }
}

class _MonthScheduleSegment {
  const _MonthScheduleSegment({
    required this.schedule,
    required this.startIndex,
    required this.daySpan,
    required this.lane,
    required this.startsInWeek,
    required this.endsInWeek,
  });

  final AppSchedule schedule;
  final int startIndex;
  final int daySpan;
  final int lane;
  final bool startsInWeek;
  final bool endsInWeek;
}

Map<String, MemberFilterColor> _memberFilterColors(List<FamilyMember> members) {
  return {
    for (var index = 0; index < members.length; index++)
      members[index].id:
          MemberFilterColor.fromValue(members[index].color) ??
          MemberFilterColor.selectable[index %
              MemberFilterColor.selectable.length],
  };
}

MemberFilterColor _scheduleMemberColor(
  AppSchedule schedule,
  Map<String, MemberFilterColor> memberColors,
) {
  if (schedule.travelTripId != null) {
    return MemberFilterColor.teal;
  }

  if (schedule.anniversaryId != null) {
    return MemberFilterColor.purple;
  }

  final familyMemberId = schedule.familyMemberId;

  if (familyMemberId == null) {
    return MemberFilterColor.gray;
  }

  return memberColors[familyMemberId] ?? MemberFilterColor.gray;
}

int _initialDayHour(DateTime date, List<AppSchedule> schedules) {
  final daySchedules =
      schedules
          .where((schedule) => _dateOnly(schedule.startsAt) == _dateOnly(date))
          .toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  if (daySchedules.isEmpty) {
    return 8;
  }

  return daySchedules.first.startsAt.hour;
}

int _initialWeekHour(DateTime weekStart, List<AppSchedule> schedules) {
  final today = _dateOnly(DateTime.now());
  final weekEnd = weekStart.add(const Duration(days: 7));

  if (today.isBefore(weekStart) || !today.isBefore(weekEnd)) {
    return 8;
  }

  final todaySchedules =
      schedules
          .where((schedule) => _dateOnly(schedule.startsAt) == today)
          .toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  if (todaySchedules.isEmpty) {
    return 8;
  }

  return todaySchedules.first.startsAt.hour;
}

String _rangeLabel(DateTime start, DateTime end, _CalendarMode mode) {
  switch (mode) {
    case _CalendarMode.day:
      return _dateLabel(start);
    case _CalendarMode.week:
      final lastDay = end.subtract(const Duration(days: 1));
      return '${_monthDayLabel(start)} - ${_monthDayLabel(lastDay)}';
    case _CalendarMode.month:
      return '${start.year}년 ${start.month}월';
  }
}

String _dayLabel(DateTime date) =>
    '${_dateLabel(date)} ${_weekdayLabel(date.weekday)}';

String _dateLabel(DateTime date) =>
    '${date.year}.${_two(date.month)}.${_two(date.day)}';

String _monthDayLabel(DateTime date) => '${date.month}.${date.day}';

String _weekdayLabel(int weekday) {
  const weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  return weekdays[weekday - 1];
}

String _calendarWeekdayLabel(int index) {
  const weekdays = ['일', '월', '화', '수', '목', '금', '토'];

  return weekdays[index];
}

String _dateTimeLabel(DateTime date) {
  return '${_dateLabel(date)} ${_timeLabel(date)}';
}

String _fullDateTimeLabel(DateTime date) {
  return '${_dateLabel(date)} ${_weekdayLabel(date.weekday)} ${_timeLabel(date)}';
}

String _scheduleConflictTimeLabel(AppSchedule schedule) {
  if (schedule.isAllDay) {
    return _dayLabel(schedule.startsAt);
  }

  return '${_dateTimeLabel(schedule.startsAt)} - ${_timeLabel(schedule.endsAt)}';
}

String _travelConflictDateLabel(TravelTrip trip) {
  return '${_dateLabel(trip.startsOn)} - ${_dateLabel(trip.endsOn)}';
}

String _anniversaryDateDetailLabel(DateTime date) {
  return _dayLabel(date);
}

String _anniversaryScheduleAlertLabel(int? minutes) {
  if (minutes == null) {
    return '알림 없음';
  }

  if (minutes >= 0) {
    if (minutes == 0) {
      return '정시';
    }

    final daysBefore = (minutes + 60 * 24 - 1) ~/ (60 * 24);
    final hourMinutes = daysBefore * 60 * 24 - minutes;

    if (hourMinutes >= 0) {
      final hour = hourMinutes ~/ 60;
      final minute = hourMinutes % 60;

      if (hour >= 0 && hour <= 23) {
        final period = hour < 12 ? '오전' : '오후';
        final displayHour = hour % 12 == 0 ? 12 : hour % 12;

        if (minute == 0) {
          return '$daysBefore일 전 $period $displayHour시';
        }

        return '$daysBefore일 전 $period $displayHour시 ${_two(minute)}분';
      }
    }
  }

  return alertOffsetLabel(minutes);
}

String _calendarTitleLabel(String title) {
  final characters = title.runes.toList();

  if (characters.length <= 8) {
    return title;
  }

  return '${String.fromCharCodes(characters.take(8))}...';
}

String _timeLabel(DateTime date) {
  final isPm = date.hour >= 12;
  final displayHour = date.hour % 12 == 0 ? 12 : date.hour % 12;

  return '${isPm ? '오후' : '오전'} $displayHour:${_two(date.minute)}';
}

String _hourLabel(int hour) => '$hour시';

String _two(int value) => value.toString().padLeft(2, '0');
