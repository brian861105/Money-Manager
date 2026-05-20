import 'package:flutter/foundation.dart';

import 'api.dart';

class LedgerController extends ChangeNotifier {
  LedgerController({required MicroLedgerApi api}) : _api = api;

  final MicroLedgerApi _api;

  bool loading = false;
  bool saving = false;
  bool hasLoaded = false;
  String? error;
  Ledger? activeLedger;
  List<Ledger> ledgers = const [];
  List<LedgerRecord> records = const [];

  void clear() {
    loading = false;
    saving = false;
    hasLoaded = false;
    error = null;
    activeLedger = null;
    ledgers = const [];
    records = const [];
    notifyListeners();
  }

  Future<void> loadInitialData() async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      final nextActiveLedger = await _api.getActiveLedger();
      final nextLedgers = await _api.listLedgers();
      final nextRecords = await _api.listRecords(ledgerId: nextActiveLedger.id);
      activeLedger = nextActiveLedger;
      ledgers = nextLedgers;
      records = nextRecords;
      hasLoaded = true;
    } catch (err) {
      error = err.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> selectLedger(int ledgerId) async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      activeLedger = await _api.setActiveLedger(ledgerId);
      records = await _api.listRecords(ledgerId: ledgerId);
    } catch (err) {
      error = err.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> createRecord({
    required String category,
    required String description,
    required String amountText,
  }) async {
    final ledger = activeLedger;
    if (ledger == null) {
      error = 'Select a ledger before adding a record.';
      notifyListeners();
      return;
    }

    final parsedAmount = _parseAmount(amountText);
    if (parsedAmount == null) {
      error = 'Amount must be a valid number, like -120 or 500.';
      notifyListeners();
      return;
    }

    saving = true;
    error = null;
    notifyListeners();

    try {
      await _api.createRecord(
        ledgerId: ledger.id,
        category: category,
        description: description,
        amountCents: (parsedAmount * 100).round(),
      );
      records = await _api.listRecords(ledgerId: ledger.id);
    } catch (err) {
      error = err.toString();
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  double? _parseAmount(String value) {
    final normalized = value
        .trim()
        .replaceAll(',', '')
        .replaceAll(' ', '')
        .replaceAll('NT\$', '')
        .replaceAll('\$', '')
        .replaceAll('元', '');
    if (normalized.isEmpty) {
      return null;
    }
    return double.tryParse(normalized);
  }
}
