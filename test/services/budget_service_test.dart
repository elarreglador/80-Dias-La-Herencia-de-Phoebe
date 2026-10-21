import 'package:flutter_test/flutter_test.dart';

import 'package:pf/services/budget_service.dart';

void main() {
  test('BudgetService gasta y registra', () {
    final budget = BudgetService(initial: 100);
    final entry = budget.spend(30, 'test');
    expect(budget.balance, 70);
    expect(entry.balanceAfter, 70);
    expect(entry.amount, -30);
    expect(budget.ledger.length, 1);
  });

  test('BudgetService lanza si saldo insuficiente', () {
    final budget = BudgetService(initial: 10);
    expect(() => budget.spend(20, 'test'), throwsA(isA<InsufficientBudgetException>()));
    expect(budget.balance, 10);
  });

  test('BudgetService canAfford', () {
    final budget = BudgetService(initial: 50);
    expect(budget.canAfford(50), isTrue);
    expect(budget.canAfford(51), isFalse);
  });
}
