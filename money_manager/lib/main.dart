import 'package:flutter/material.dart';

import 'src/api.dart';
import 'src/auth.dart';
import 'src/google_auth_provider.dart';
import 'src/ledger.dart';
import 'src/launcher.dart';

void main() {
  runApp(const MoneyManagerApp());
}

class MoneyManagerApp extends StatelessWidget {
  const MoneyManagerApp({
    super.key,
    MicroLedgerApi? api,
    UrlLauncher? launcher,
    GoogleAuthProvider? googleAuthProvider,
  }) : _api = api,
       _launcher = launcher,
       _googleAuthProvider = googleAuthProvider;

  final MicroLedgerApi? _api;
  final UrlLauncher? _launcher;
  final GoogleAuthProvider? _googleAuthProvider;

  @override
  Widget build(BuildContext context) {
    final api = _api ?? MicroLedgerApi();
    final launcher = _launcher ?? createUrlLauncher();
    return MaterialApp(
      title: 'Money Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
        useMaterial3: true,
      ),
      home: AuthShell(
        authController: AuthController(
          api: api,
          googleAuthProvider:
              _googleAuthProvider ?? createGoogleAuthProvider(launcher),
        ),
        ledgerController: LedgerController(api: api),
      ),
    );
  }
}

class AuthShell extends StatefulWidget {
  const AuthShell({
    required this.authController,
    required this.ledgerController,
    super.key,
  });

  final AuthController authController;
  final LedgerController ledgerController;

  @override
  State<AuthShell> createState() => _AuthShellState();
}

class _AuthShellState extends State<AuthShell> {
  @override
  void initState() {
    super.initState();
    widget.authController.addListener(_handleAuthChanged);
    widget.authController.loadCurrentSession();
  }

  @override
  void dispose() {
    widget.authController.removeListener(_handleAuthChanged);
    widget.authController.dispose();
    widget.ledgerController.dispose();
    super.dispose();
  }

  void _handleAuthChanged() {
    if (widget.authController.session == null) {
      if (widget.ledgerController.hasLoaded) {
        widget.ledgerController.clear();
      }
      return;
    }
    if (!widget.ledgerController.hasLoaded) {
      widget.ledgerController.loadInitialData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.authController,
        widget.ledgerController,
      ]),
      builder: (context, _) {
        final auth = widget.authController;
        if (auth.loading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final session = auth.session;
        if (session == null) {
          return SignedOutPage(
            error: auth.error,
            signingIn: auth.signingIn,
            onLogin: auth.loginWithGoogle,
          );
        }

        return LedgerHomePage(
          session: session,
          authController: auth,
          ledgerController: widget.ledgerController,
        );
      },
    );
  }
}

class SignedOutPage extends StatelessWidget {
  const SignedOutPage({
    required this.error,
    required this.signingIn,
    required this.onLogin,
    super.key,
  });

  final String? error;
  final bool signingIn;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Money Manager',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Sign in to manage your micro-ledger.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: signingIn ? null : onLogin,
                    icon: signingIn
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: const Text('Sign in with Google'),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LedgerHomePage extends StatefulWidget {
  const LedgerHomePage({
    required this.session,
    required this.authController,
    required this.ledgerController,
    super.key,
  });

  final AuthSession session;
  final AuthController authController;
  final LedgerController ledgerController;

  @override
  State<LedgerHomePage> createState() => _LedgerHomePageState();
}

class _LedgerHomePageState extends State<LedgerHomePage> {
  final _categoryController = TextEditingController(text: 'food');
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();

  @override
  void dispose() {
    _categoryController.dispose();
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _createRecord() async {
    await widget.ledgerController.createRecord(
      category: _categoryController.text.trim(),
      description: _descriptionController.text.trim(),
      amountText: _amountController.text,
    );
    if (mounted && widget.ledgerController.error == null) {
      _descriptionController.clear();
      _amountController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.ledgerController;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Money Manager'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: controller.loading ? null : controller.loadInitialData,
            icon: const Icon(Icons.refresh),
          ),
          AccountMenu(
            email: widget.session.email,
            loggingOut: widget.authController.loggingOut,
            onLogout: widget.authController.logout,
            onSwitchAccount: widget.authController.switchAccount,
          ),
        ],
      ),
      body: SafeArea(
        child: controller.loading && controller.activeLedger == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: controller.loadInitialData,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _ConnectionPanel(error: controller.error),
                    const SizedBox(height: 16),
                    _LedgerPanel(
                      activeLedger: controller.activeLedger,
                      ledgers: controller.ledgers,
                      onChanged: controller.loading
                          ? null
                          : controller.selectLedger,
                    ),
                    const SizedBox(height: 16),
                    _RecordList(records: controller.records),
                    const SizedBox(height: 16),
                    _CreateRecordPanel(
                      categoryController: _categoryController,
                      descriptionController: _descriptionController,
                      amountController: _amountController,
                      saving: controller.saving,
                      onSubmit: controller.saving ? null : _createRecord,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class AccountMenu extends StatelessWidget {
  const AccountMenu({
    required this.email,
    required this.loggingOut,
    required this.onLogout,
    required this.onSwitchAccount,
    super.key,
  });

  final String email;
  final bool loggingOut;
  final VoidCallback onLogout;
  final VoidCallback onSwitchAccount;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Account',
      icon: const Icon(Icons.account_circle),
      onSelected: (value) {
        if (value == 'logout') {
          onLogout();
        } else if (value == 'switch') {
          onSwitchAccount();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(enabled: false, child: Text(email)),
        PopupMenuItem(
          value: 'switch',
          enabled: !loggingOut,
          child: const Row(
            children: [
              Icon(Icons.switch_account),
              SizedBox(width: 12),
              Text('Switch account'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'logout',
          enabled: !loggingOut,
          child: Row(
            children: [
              if (loggingOut)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.logout),
              const SizedBox(width: 12),
              const Text('Sign out'),
            ],
          ),
        ),
      ],
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
            Text('Auth mode: ${ApiConfig.authMode.label}'),
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
                helperText: 'Examples: -120, 500, NT\$1,200',
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
