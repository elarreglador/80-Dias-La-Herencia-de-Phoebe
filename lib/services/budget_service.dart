import 'dart:async';

import '../domain/models/ledger_entry.dart';

class InsufficientBudgetException implements Exception {
  const InsufficientBudgetException(this.requested, this.balance);

  final int requested;
  final int balance;

  @override
  String toString() =>
      'InsufficientBudgetException(requested: $requested, balance: $balance)';
}

class BudgetService {
  BudgetService({int initial = 1000000})
      : _balance = initial {
    _balanceController.add(_balance);
  }

  int _balance;
  final List<LedgerEntry> _ledger = [];
  final StreamController<int> _balanceController =
      StreamController<int>.broadcast();
  final StreamController<LedgerEntry> _ledgerController =
      StreamController<LedgerEntry>.broadcast();

  int get balance => _balance;

  List<LedgerEntry> get ledger => List.unmodifiable(_ledger);

  Stream<int> get balanceStream => _balanceController.stream;

  Stream<LedgerEntry> get ledgerStream => _ledgerController.stream;

  bool canAfford(int price) => price <= _balance;

  LedgerEntry spend(int price, String reason) {
    if (price > _balance) {
      throw InsufficientBudgetException(price, _balance);
    }
    _balance -= price;
    final entry = LedgerEntry(
      timestampUtc: DateTime.now().toUtc(),
      amount: -price,
      reason: reason,
      balanceAfter: _balance,
    );
    _ledger.add(entry);
    _balanceController.add(_balance);
    _ledgerController.add(entry);
    return entry;
  }

  void dispose() {
    _balanceController.close();
    _ledgerController.close();
  }
}
