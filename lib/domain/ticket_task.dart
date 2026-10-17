/// Ticket fares need show identity and availability, not retail stock/JSON-LD.
/// This capability is deliberately unavailable until that evaluator exists.
class TicketTaskPolicy {
  static bool isPriceTask(String task) {
    // A literal text watch is not a promise to evaluate ticket prices.
    if (RegExp(
      r'\b(?:contains|shows|mentions)\s+["“][^"”]+["”]\s*$',
      caseSensitive: false,
    ).hasMatch(task.trim())) {
      return false;
    }
    if (RegExp(
      r'\b(?:ticket printer|ticket holder|ticket to ride|ticket machine)\b',
      caseSensitive: false,
    ).hasMatch(task)) {
      return false;
    }
    final ticket = RegExp(
      r'\b(?:tickets?|cinema|cineplex|theatre|theater|box office|admission)\b',
      caseSensitive: false,
    ).hasMatch(task);
    final price = RegExp(
      r'\b(?:price|cost|fare|cheaper|below|under|less than|above|more than)\b',
      caseSensitive: false,
    ).hasMatch(task);
    return ticket && price;
  }

  static const title = 'Ticket-price monitoring is not supported yet';
  static const limitation =
      'Lookout cannot yet discover and verify a live ticket fare for the exact event, venue, date, showtime and seat class. A retail product price or search snippet is not ticket-price evidence. No ticket price was verified; automatic monitoring is unavailable.';
  static const requirements =
      'A ticket checker needs a confirmed event and venue, an explicit date or date range, a showtime or any-show choice, and a seat class or any-class choice. It must also distinguish available seats and ticket fare from booking fees.';
  static const transport =
      'The experimental BookMyShow reader can sometimes read category prices from an exact show link. It does not verify available seats or match your intended event, show and class. Pasting a link alone does not make ticket monitoring reliable.';
}
