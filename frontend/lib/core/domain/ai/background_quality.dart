/// Scales Monte-Carlo equity iteration counts by how many tables remain in a
/// tournament — full resolution at the tables that matter (final table and
/// the stretch approaching it), progressively cheaper the deeper a huge field
/// still is. This is still a *real* decision at every table, just a lower-
/// resolution equity estimate when there are hundreds of tables running at
/// once; it ramps back up automatically as the field consolidates, without
/// needing a hand-count sampling trick or a fast/slow mode switch.
///
/// [tableCount] is null outside a tournament (cash table), where the answer
/// is always full resolution.
///
/// Shared by [ProfilePostflopPolicy] and [AmateurPolicy] — both spend most of
/// their per-decision cost in the same Monte-Carlo equity runout, so both
/// need the same dial. Tune the breakpoints here; each seat reads its
/// provider live, so a change in table count takes effect on that seat's very
/// next decision, mid-tournament.
double equityIterationScale(int? tableCount) {
  if (tableCount == null) return 1.0;
  if (tableCount <= 3) return 1.0; // true final table: full resolution
  if (tableCount <= 15) return 0.85; // final few hundred players
  if (tableCount <= 60) return 0.6; // low thousands remaining
  if (tableCount <= 200) return 0.4; // mid-field
  return 0.25; // huge field (thousands of tables): cheapest resolution
}
