import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MoneyManagerApp());
}

class MoneyManagerApp extends StatelessWidget {
  const MoneyManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Money Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
        useMaterial3: true,
      ),
      home: const LedgerHomePage(),
    );
  }
}

class ApiConfig {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );
  static const devEmail = String.fromEnvironment(
    'API_DEV_EMAIL',
    defaultValue: 'you@example.com',
  );
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.code, this.message);

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => '$statusCode $code: $message';
}

class Ledger {
  const Ledger({
    required this.id,
    required this.name,
    required this.type,
    required this.ownerEmail,
  });

  factory Ledger.fromJson(Map<String, dynamic> json) {
    return Ledger(
      id: json['id'] as int,
      name: json['name'] as String,
      type: json['type'] as String,
      ownerEmail: json['owner_email'] as String,
    );
  }

  final int id;
  final String name;
  final String type;
  final String ownerEmail;
}

class LedgerRecord {
  const LedgerRecord({
    required this.id,
    required this.ledgerId,
    required this.creatorEmail,
    required this.date,
    required this.category,
    required this.description,
    required this.amountCents,
  });

  factory LedgerRecord.fromJson(Map<String, dynamic> json) {
    return LedgerRecord(
      id: json['id'] as int,
      ledgerId: json['ledger_id'] as int,
      creatorEmail: json['creator_email'] as String,
      date: DateTime.parse(json['date'] as String),
      category: json['category'] as String,
      description: json['description'] as String? ?? '',
      amountCents: json['amount_cents'] as int,
    );
  }

  final int id;
  final int ledgerId;
  final String creatorEmail;
  final DateTime date;
  final String category;
  final String description;
  final int amountCents;
}

class MicroLedgerApi {
  MicroLedgerApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<Ledger> getActiveLedger() async {
    final json = await _send('GET', '/api/context/active-ledger');
    return Ledger.fromJson(json['ledger'] as Map<String, dynamic>);
  }

  Future<Ledger> setActiveLedger(int ledgerId) async {
    final json = await _send(
      'PUT',
      '/api/context/active-ledger',
      body: {'ledger_id': ledgerId},
    );
    return Ledger.fromJson(json['ledger'] as Map<String, dynamic>);
  }

  Future<List<Ledger>> listLedgers() async {
    final json = await _send('GET', '/api/ledgers');
    final items = json['ledgers'] as List<dynamic>;
    return items
        .map((item) => Ledger.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<LedgerRecord>> listRecords() async {
    final json = await _send('GET', '/api/records?limit=100');
    final items = json['records'] as List<dynamic>;
    return items
        .map((item) => LedgerRecord.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<LedgerRecord> createRecord({
    required String category,
    required String description,
    required int amountCents,
  }) async {
    final json = await _send(
      'POST',
      '/api/records',
      body: {
        'date': DateTime.now().toUtc().toIso8601String(),
        'category': category,
        'description': description,
        'amount_cents': amountCents,
      },
    );
    return LedgerRecord.fromJson(json['record'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final request = http.Request(
      method,
      Uri.parse('${ApiConfig.baseUrl}$path'),
    );
    request.headers.addAll({
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'X-Goog-Authenticated-User-Email':
          'accounts.google.com:${ApiConfig.devEmail}',
    });
    if (body != null) {
      request.body = jsonEncode(body);
    }

    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    if (response.statusCode == 204) {
      return <String, dynamic>{};
    }

    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'] as Map<String, dynamic>?;
      throw ApiException(
        response.statusCode,
        error?['code'] as String? ?? 'request_failed',
        error?['message'] as String? ?? 'request failed',
      );
    }
    return decoded;
  }

  void close() {
    _client.close();
  }
}

class LedgerHomePage extends StatefulWidget {
  const LedgerHomePage({super.key});

  @override
  State<LedgerHomePage> createState() => _LedgerHomePageState();
}

class _LedgerHomePageState extends State<LedgerHomePage> {
  final _api = MicroLedgerApi();
  final _categoryController = TextEditingController(text: 'food');
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  Ledger? _activeLedger;
  List<Ledger> _ledgers = const [];
  List<LedgerRecord> _records = const [];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _api.close();
    _categoryController.dispose();
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final activeLedger = await _api.getActiveLedger();
      final ledgers = await _api.listLedgers();
      final records = await _api.listRecords();
      if (!mounted) {
        return;
      }
      setState(() {
        _activeLedger = activeLedger;
        _ledgers = ledgers;
        _records = records;
      });
    } catch (err) {
      if (!mounted) {
        return;
      }
      setState(() => _error = err.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _selectLedger(int ledgerId) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final activeLedger = await _api.setActiveLedger(ledgerId);
      final records = await _api.listRecords();
      if (!mounted) {
        return;
      }
      setState(() {
        _activeLedger = activeLedger;
        _records = records;
      });
    } catch (err) {
      if (mounted) {
        setState(() => _error = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _createRecord() async {
    final amountText = _amountController.text.trim();
    final parsedAmount = double.tryParse(amountText);
    if (parsedAmount == null) {
      setState(() => _error = 'Amount must be a number.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api.createRecord(
        category: _categoryController.text.trim(),
        description: _descriptionController.text.trim(),
        amountCents: (parsedAmount * 100).round(),
      );
      final records = await _api.listRecords();
      if (!mounted) {
        return;
      }
      setState(() {
        _records = records;
        _descriptionController.clear();
        _amountController.clear();
      });
    } catch (err) {
      if (mounted) {
        setState(() => _error = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Money Manager'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadInitialData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading && _activeLedger == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadInitialData,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _ConnectionPanel(error: _error),
                    const SizedBox(height: 16),
                    _LedgerPanel(
                      activeLedger: _activeLedger,
                      ledgers: _ledgers,
                      onChanged: _loading ? null : _selectLedger,
                    ),
                    const SizedBox(height: 16),
                    _CreateRecordPanel(
                      categoryController: _categoryController,
                      descriptionController: _descriptionController,
                      amountController: _amountController,
                      saving: _saving,
                      onSubmit: _saving ? null : _createRecord,
                    ),
                    const SizedBox(height: 16),
                    _RecordList(records: _records),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ConnectionPanel extends StatelessWidget {
  const _ConnectionPanel({required this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Backend', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(ApiConfig.baseUrl),
            Text('Local user: ${ApiConfig.devEmail}'),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}

class _LedgerPanel extends StatelessWidget {
  const _LedgerPanel({
    required this.activeLedger,
    required this.ledgers,
    required this.onChanged,
  });

  final Ledger? activeLedger;
  final List<Ledger> ledgers;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Active ledger',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: activeLedger?.id,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Ledger',
              ),
              items: ledgers
                  .map(
                    (ledger) => DropdownMenuItem(
                      value: ledger.id,
                      child: Text('${ledger.name} (${ledger.type})'),
                    ),
                  )
                  .toList(),
              onChanged: onChanged == null
                  ? null
                  : (value) {
                      if (value != null) {
                        onChanged!(value);
                      }
                    },
            ),
            if (activeLedger != null) ...[
              const SizedBox(height: 8),
              Text('Owner: ${activeLedger!.ownerEmail}'),
            ],
          ],
        ),
      ),
    );
  }
}

class _CreateRecordPanel extends StatelessWidget {
  const _CreateRecordPanel({
    required this.categoryController,
    required this.descriptionController,
    required this.amountController,
    required this.saving,
    required this.onSubmit,
  });

  final TextEditingController categoryController;
  final TextEditingController descriptionController;
  final TextEditingController amountController;
  final bool saving;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New record', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: categoryController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Category',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Description',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Amount',
                helperText: 'Example: -120.00 for expense, 500.00 for income',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onSubmit,
              icon: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
              label: const Text('Add record'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordList extends StatelessWidget {
  const _RecordList({required this.records});

  final List<LedgerRecord> records;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Records', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (records.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No records yet')),
              )
            else
              ...records.map((record) => _RecordTile(record: record)),
          ],
        ),
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});

  final LedgerRecord record;

  @override
  Widget build(BuildContext context) {
    final amount = record.amountCents / 100;
    final amountColor = amount < 0
        ? Colors.red.shade700
        : Colors.green.shade700;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        record.description.isEmpty ? record.category : record.description,
      ),
      subtitle: Text('${record.category} · ${record.date.toLocal()}'),
      trailing: Text(
        amount.toStringAsFixed(2),
        style: TextStyle(color: amountColor, fontWeight: FontWeight.w700),
      ),
    );
  }
}
