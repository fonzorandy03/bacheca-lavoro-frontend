import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import 'api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.i.init();
  runApp(const BachecaApp());
}

class BachecaApp extends StatelessWidget {
  const BachecaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bacheca Lavoro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1565C0),
        useMaterial3: true,
        inputDecorationTheme:
            const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      home: const JobListScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Utilità
// ---------------------------------------------------------------------------
void snack(BuildContext c, String msg) => ScaffoldMessenger.of(c)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(msg)));

String fmtDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return '';
  String t(int n) => n.toString().padLeft(2, '0');
  return '${t(d.day)}/${t(d.month)}/${d.year} ${t(d.hour)}:${t(d.minute)}';
}

/// Carica dati asincroni e mostra caricamento / errore / contenuto.
class AsyncList<T> extends StatelessWidget {
  final Future<List<T>> future;
  final Widget Function(T) item;
  final String empty;
  final Future<void> Function() onRefresh;
  const AsyncList(
      {super.key,
      required this.future,
      required this.item,
      required this.empty,
      required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<T>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
              child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${snap.error}', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: onRefresh, child: const Text('Riprova')),
            ]),
          ));
        }
        final data = snap.data!;
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: data.isEmpty
              ? ListView(children: [
                  Padding(
                      padding: const EdgeInsets.all(48),
                      child: Center(child: Text(empty)))
                ])
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: data.length,
                  itemBuilder: (_, i) => item(data[i])),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Area pubblica: bacheca
// ---------------------------------------------------------------------------
class JobListScreen extends StatefulWidget {
  const JobListScreen({super.key});
  @override
  State<JobListScreen> createState() => _JobListScreenState();
}

class _JobListScreenState extends State<JobListScreen> {
  late Future<List<Map<String, dynamic>>> _f = Api.i.jobs();

  Future<void> _reload() async {
    setState(() => _f = Api.i.jobs());
    await _f.catchError((_) => <Map<String, dynamic>>[]);
  }

  Future<void> _serverDialog() async {
    final ctrl = TextEditingController(text: Api.i.baseUrl);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Indirizzo server'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
              hintText: 'http://192.168.1.10:8090',
              helperText: 'Emulatore: http://10.0.2.2:8090'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annulla')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Salva')),
        ],
      ),
    );
    if (ok == true) {
      await Api.i.setBaseUrl(ctrl.text);
      _reload();
    }
  }

  void _company() {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => Api.i.loggedIn
                ? const CompanyHomeScreen()
                : const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bacheca annunci'),
        actions: [
          IconButton(
              tooltip: 'Server',
              onPressed: _serverDialog,
              icon: const Icon(Icons.settings_ethernet)),
          TextButton.icon(
              onPressed: _company,
              icon: const Icon(Icons.business),
              label: const Text('Area azienda')),
        ],
      ),
      body: AsyncList<Map<String, dynamic>>(
        future: _f,
        onRefresh: _reload,
        empty: 'Nessun annuncio pubblicato',
        item: (j) => Card(
          child: ListTile(
            title: Text(j['title'],
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
                '${j['companyName']}${(j['location'] as String).isEmpty ? '' : ' · ${j['location']}'}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => JobDetailScreen(job: j))),
          ),
        ),
      ),
    );
  }
}

class JobDetailScreen extends StatelessWidget {
  final Map<String, dynamic> job;
  const JobDetailScreen({super.key, required this.job});

  @override
  Widget build(BuildContext context) {
    final loc = job['location'] as String;
    return Scaffold(
      appBar: AppBar(title: const Text('Dettaglio annuncio')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(job['title'], style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(job['companyName'],
            style: Theme.of(context).textTheme.titleMedium),
        if (loc.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.place, size: 18),
            const SizedBox(width: 4),
            Text(loc)
          ]),
        ],
        const SizedBox(height: 4),
        Text('Pubblicato il ${fmtDate(job['createdAt'])}',
            style: Theme.of(context).textTheme.bodySmall),
        const Divider(height: 32),
        Text(job['description']),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            icon: const Icon(Icons.send),
            label: const Text('Candidati'),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => ApplyScreen(job: job))),
          ),
        ),
      ),
    );
  }
}

class ApplyScreen extends StatefulWidget {
  final Map<String, dynamic> job;
  const ApplyScreen({super.key, required this.job});
  @override
  State<ApplyScreen> createState() => _ApplyScreenState();
}

class _ApplyScreenState extends State<ApplyScreen> {
  final _form = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _msg = TextEditingController();
  PlatformFile? _cv;
  bool _cvError = false;
  bool _busy = false;

  Future<void> _pick() async {
    final r = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx'],
        withData: false);
    if (r != null) {
      setState(() {
        _cv = r.files.single;
        _cvError = false;
      });
    }
  }

  Future<void> _submit() async {
    final valid = _form.currentState!.validate();
    setState(() => _cvError = _cv == null);
    if (!valid || _cv == null) return;
    setState(() => _busy = true);
    try {
      await Api.i.apply(
          widget.job['id'],
          {
            'firstName': _first.text.trim(),
            'lastName': _last.text.trim(),
            'email': _email.text.trim(),
            'phone': _phone.text.trim(),
            'message': _msg.text.trim(),
          },
          _cv!);
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title: const Text('Candidatura inviata'),
          content: Text(
              'La tua candidatura per "${widget.job['title']}" è stata registrata.'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(c), child: const Text('OK'))
          ],
        ),
      );
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      if (mounted) snack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _req(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Campo obbligatorio' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Candidatura')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(widget.job['title'],
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextFormField(
              controller: _first,
              decoration: const InputDecoration(labelText: 'Nome'),
              validator: _req),
          const SizedBox(height: 12),
          TextFormField(
              controller: _last,
              decoration: const InputDecoration(labelText: 'Cognome'),
              validator: _req),
          const SizedBox(height: 12),
          TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) =>
                  (v == null || !v.contains('@')) ? 'Email non valida' : null),
          const SizedBox(height: 12),
          TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Telefono (facoltativo)')),
          const SizedBox(height: 12),
          TextFormField(
              controller: _msg,
              maxLines: 3,
              decoration:
                  const InputDecoration(labelText: 'Messaggio (facoltativo)')),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.attach_file),
            label: Text(_cv == null ? 'Allega curriculum' : _cv!.name),
          ),
          if (_cvError)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 12),
              child: Text('Allega il curriculum',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error, fontSize: 12)),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Invia candidatura'),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Azienda: login / registrazione
// ---------------------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pw = TextEditingController();
  bool _busy = false;

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await Api.i.login(_email.text.trim(), _pw.text);
      if (!mounted) return;
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const CompanyHomeScreen()));
    } on ApiException catch (e) {
      if (mounted) snack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login azienda')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const SizedBox(height: 16),
          TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) =>
                  (v == null || !v.contains('@')) ? 'Email non valida' : null),
          const SizedBox(height: 12),
          TextFormField(
              controller: _pw,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Campo obbligatorio' : null),
          const SizedBox(height: 24),
          FilledButton(
              onPressed: _busy ? null : _login, child: const Text('Accedi')),
          TextButton(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const RegisterScreen())),
              child: const Text('Non hai un account? Registrati')),
        ]),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pw = TextEditingController();
  bool _busy = false;

  Future<void> _register() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await Api.i.register(_name.text.trim(), _email.text.trim(), _pw.text);
      if (!mounted) return;
      snack(context, 'Account creato. Ora puoi accedere.');
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) snack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrazione azienda')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const SizedBox(height: 16),
          TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nome azienda'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Campo obbligatorio' : null),
          const SizedBox(height: 12),
          TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) =>
                  (v == null || !v.contains('@')) ? 'Email non valida' : null),
          const SizedBox(height: 12),
          TextFormField(
              controller: _pw,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password (min. 4)'),
              validator: (v) =>
                  (v == null || v.length < 4) ? 'Almeno 4 caratteri' : null),
          const SizedBox(height: 24),
          FilledButton(
              onPressed: _busy ? null : _register,
              child: const Text('Registra')),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Area riservata azienda
// ---------------------------------------------------------------------------
class CompanyHomeScreen extends StatefulWidget {
  const CompanyHomeScreen({super.key});
  @override
  State<CompanyHomeScreen> createState() => _CompanyHomeScreenState();
}

class _CompanyHomeScreenState extends State<CompanyHomeScreen> {
  late Future<List<Map<String, dynamic>>> _f = Api.i.myJobs();

  Future<void> _reload() async {
    setState(() => _f = Api.i.myJobs());
    await _f.catchError((_) => <Map<String, dynamic>>[]);
  }

  Future<void> _logout() async {
    await Api.i.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const JobListScreen()),
        (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(Api.i.companyName ?? 'Area azienda'),
        actions: [
          IconButton(
              tooltip: 'Logout',
              onPressed: _logout,
              icon: const Icon(Icons.logout)),
        ],
      ),
      body: AsyncList<Map<String, dynamic>>(
        future: _f,
        onRefresh: _reload,
        empty: 'Non hai ancora pubblicato annunci',
        item: (j) => Card(
          child: ListTile(
            title: Text(j['title'],
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${j['applicationsCount']} candidature'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ApplicationsScreen(job: j))),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Nuovo annuncio'),
        onPressed: () async {
          final created = await Navigator.push<bool>(context,
              MaterialPageRoute(builder: (_) => const NewJobScreen()));
          if (created == true) _reload();
        },
      ),
    );
  }
}

class NewJobScreen extends StatefulWidget {
  const NewJobScreen({super.key});
  @override
  State<NewJobScreen> createState() => _NewJobScreenState();
}

class _NewJobScreenState extends State<NewJobScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _loc = TextEditingController();
  bool _busy = false;

  Future<void> _publish() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await Api.i.createJob(
          _title.text.trim(), _desc.text.trim(), _loc.text.trim());
      if (!mounted) return;
      snack(context, 'Annuncio pubblicato');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) snack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _req(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Campo obbligatorio' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuovo annuncio')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Titolo'),
              validator: _req),
          const SizedBox(height: 12),
          TextFormField(
              controller: _loc,
              decoration:
                  const InputDecoration(labelText: 'Sede (facoltativa)')),
          const SizedBox(height: 12),
          TextFormField(
              controller: _desc,
              maxLines: 8,
              decoration: const InputDecoration(
                  labelText: 'Descrizione', alignLabelWithHint: true),
              validator: _req),
          const SizedBox(height: 24),
          FilledButton(
              onPressed: _busy ? null : _publish,
              child: const Text('Pubblica')),
        ]),
      ),
    );
  }
}

class ApplicationsScreen extends StatefulWidget {
  final Map<String, dynamic> job;
  const ApplicationsScreen({super.key, required this.job});
  @override
  State<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

class _ApplicationsScreenState extends State<ApplicationsScreen> {
  late Future<List<Map<String, dynamic>>> _f =
      Api.i.applications(widget.job['id']);

  Future<void> _reload() async {
    setState(() => _f = Api.i.applications(widget.job['id']));
    await _f.catchError((_) => <Map<String, dynamic>>[]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.job['title'])),
      body: AsyncList<Map<String, dynamic>>(
        future: _f,
        onRefresh: _reload,
        empty: 'Nessuna candidatura ricevuta',
        item: (a) => Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text('${a['firstName']} ${a['lastName']}'),
            subtitle: Text(fmtDate(a['createdAt'])),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ApplicationDetailScreen(app: a))),
          ),
        ),
      ),
    );
  }
}

class ApplicationDetailScreen extends StatefulWidget {
  final Map<String, dynamic> app;
  const ApplicationDetailScreen({super.key, required this.app});
  @override
  State<ApplicationDetailScreen> createState() =>
      _ApplicationDetailScreenState();
}

class _ApplicationDetailScreenState extends State<ApplicationDetailScreen> {
  bool _busy = false;

  Future<void> _openCv() async {
    setState(() => _busy = true);
    try {
      final path = await Api.i.downloadCv(widget.app['id'], widget.app['cvName']);
      final r = await OpenFilex.open(path);
      if (r.type != ResultType.done && mounted) {
        snack(context, 'Impossibile aprire il file: ${r.message}');
      }
    } on ApiException catch (e) {
      if (mounted) snack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _row(IconData i, String label, String v) => ListTile(
        leading: Icon(i),
        title: Text(v.isEmpty ? '—' : v),
        subtitle: Text(label),
      );

  @override
  Widget build(BuildContext context) {
    final a = widget.app;
    return Scaffold(
      appBar: AppBar(title: const Text('Candidatura')),
      body: ListView(children: [
        _row(Icons.person, 'Nome', a['firstName']),
        _row(Icons.person_outline, 'Cognome', a['lastName']),
        _row(Icons.email, 'Email', a['email']),
        _row(Icons.phone, 'Telefono', a['phone']),
        _row(Icons.message, 'Messaggio', a['message']),
        _row(Icons.schedule, 'Inviata il', fmtDate(a['createdAt'])),
        _row(Icons.description, 'Curriculum', a['cvName']),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _busy ? null : _openCv,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Apri curriculum'),
          ),
        ),
      ]),
    );
  }
}
