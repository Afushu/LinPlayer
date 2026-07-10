import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_preferences.dart';
import 'sync_providers.dart';
import '../services/sync/calendar_models.dart';
import '../services/sync/sync_models.dart';

const String _calendarSourceKey = 'linplayer_calendar_source';

/// 追剧日历的数据来源（trakt / bangumi），持久化。
final calendarSourceProvider =
    StateNotifierProvider<PreferenceNotifier<String>, String>((ref) {
  return PreferenceNotifier<String>(
    defaultValue: SyncService.trakt.name,
    readValue: (prefs) => prefs.getString(_calendarSourceKey),
    writeValue: (prefs, value) async {
      await prefs.setString(_calendarSourceKey, value);
    },
  );
});

/// 当前选择的来源枚举。
SyncService calendarSourceOf(String name) =>
    name == SyncService.bangumi.name ? SyncService.bangumi : SyncService.trakt;

/// 按来源拉取的追剧日历（autoDispose：每次进入重新拉取）。
final calendarEntriesProvider = FutureProvider.autoDispose
    .family<List<CalendarEntry>, SyncService>((ref, source) {
  return ref.read(syncControllerProvider.notifier).fetchCalendar(source);
});
