/// User-visible timestamp formatting shared by every app surface (history
/// cards, task details, home tiles, check-log lines, reminder labels).
///
/// Display-only: day/month plus a 12-hour clock with an AM/PM marker. The
/// stored values stay epoch milliseconds and the instants keep the device
/// timezone - only the rendering changes.
library;

String fmtAppTime(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final ampm = t.hour < 12 ? 'AM' : 'PM';
  return '${t.day}/${t.month} $h:${t.minute.toString().padLeft(2, '0')} $ampm';
}
