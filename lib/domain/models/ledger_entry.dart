class LedgerEntry {
  const LedgerEntry({
    required this.timestampUtc,
    required this.amount,
    required this.reason,
    required this.balanceAfter,
  });

  final DateTime timestampUtc;
  final int amount; // negativo = gasto
  final String reason;
  final int balanceAfter;
}
