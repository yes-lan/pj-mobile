import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const XynpoApp());
}

class XynpoApp extends StatelessWidget {
  const XynpoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Xynpo',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D6EFD)),
      ),
      home: const LoginPage(),
      onGenerateRoute: (settings) {
        // Fallback to default behavior; we primarily use Navigator.push with our helper
        return null;
      },
    );
  }
}

// Helper to push a new page with a fade + slide animation
Future<T?> pushAnimated<T>(BuildContext context, Widget page) {
  return Navigator.of(context).push<T>(PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final tween = Tween<Offset>(begin: const Offset(0.0, 0.04), end: Offset.zero);
      final fade = Tween<double>(begin: 0.0, end: 1.0);
      return SlideTransition(
        position: animation.drive(CurveTween(curve: Curves.easeOut)).drive(tween),
        child: FadeTransition(opacity: animation.drive(fade), child: child),
      );
    },
  ));
}

Future<T?> pushReplacementAnimated<T>(BuildContext context, Widget page) {
  return Navigator.of(context).pushReplacement<T, T>(PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final tween = Tween<Offset>(begin: const Offset(0.0, 0.04), end: Offset.zero);
      final fade = Tween<double>(begin: 0.0, end: 1.0);
      return SlideTransition(
        position: animation.drive(CurveTween(curve: Curves.easeOut)).drive(tween),
        child: FadeTransition(opacity: animation.drive(fade), child: child),
      );
    },
  ));
}

class ApiConfig {
  static const String baseUrl = 'https://std41.beaupeyrat.com';
}

// Custom HTTP client that accepts ngrok certificates
class _NgrokHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final httpClient = HttpClient()
      ..badCertificateCallback = (_, __, ___) => true; // Accept all certificates for development
    
    HttpClientRequest httpClientRequest;
    try {
      httpClientRequest = await httpClient.openUrl(request.method, request.url);
    } catch (e) {
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"message":"Connection error"}')),
        500,
      );
    }
    
    request.headers.forEach((name, value) {
      httpClientRequest.headers.set(name, value);
    });

    await httpClientRequest.addStream(request.finalize());
    
    final httpClientResponse = await httpClientRequest.close();
    final responseHeaders = <String, String>{};
    httpClientResponse.headers.forEach((name, values) {
      responseHeaders[name] = values.join(', ');
    });
    
    return http.StreamedResponse(
      httpClientResponse.cast<List<int>>(),
      httpClientResponse.statusCode,
      contentLength: httpClientResponse.contentLength,
      request: request,
      headers: responseHeaders,
      isRedirect: httpClientResponse.isRedirect,
    );
  }
}

class MobileApiClient {
  MobileApiClient({required this.baseUrl}) : _httpClient = _NgrokHttpClient();

  final String baseUrl;
  final http.Client _httpClient;
  String? _token;

  bool get isAuthenticated => _token != null;

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final loginPayload = {'email': email, 'password': password};
    http.Response response;

    try {
      response = await _postJsonWithRedirect(
        '/api/login',
        loginPayload,
      ).timeout(const Duration(seconds: 20));
    } on SocketException catch (error) {
      throw ApiException('Erreur réseau (DNS/connexion): ${error.message}');
    } on HandshakeException catch (error) {
      throw ApiException('Erreur TLS/SSL: ${error.message}');
    } on TimeoutException {
      throw ApiException('Timeout réseau: l’API ne répond pas.');
    }

    final json = _decodeBody(response.body);
    if (response.statusCode >= 400) {
      throw ApiException(json['message']?.toString() ?? 'Erreur de connexion.');
    }

    _token = json['token']?.toString();
    if (_token == null || _token!.isEmpty) {
      final contentType = response.headers['content-type'] ?? 'unknown';
      final location = response.headers['location'];
      final rawBody = json['raw']?.toString() ?? response.body;
      final preview =
          rawBody.length > 220 ? '${rawBody.substring(0, 220)}...' : rawBody;
      final message =
          json['message']?.toString() ??
          json['error']?.toString() ??
        'Réponse login invalide (${response.statusCode}, $contentType${location != null ? ', location: $location' : ''}): $preview';
      throw ApiException(message);
    }

    return json;
  }

  Future<http.Response> _postJsonWithRedirect(
    String path,
    Map<String, dynamic> payload,
  ) async {
    var uri = Uri.parse('$baseUrl$path');
    final body = jsonEncode(payload);

    for (var i = 0; i < 5; i++) {
      final request = http.Request('POST', uri)
        ..followRedirects = false
        ..headers.addAll(_defaultHeaders(contentType: 'application/json'))
        ..body = body;

      final streamed = await _httpClient.send(request);
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode != 301 &&
          response.statusCode != 302 &&
          response.statusCode != 307 &&
          response.statusCode != 308) {
        return response;
      }

      final locationHeader = response.headers['location'];
      if (locationHeader != null && locationHeader.isNotEmpty) {
        final redirectUri = Uri.parse(locationHeader);
        final resolved = redirectUri.hasScheme
            ? redirectUri
            : uri.resolveUri(redirectUri);

        if (resolved.host == 'localhost' || resolved.host == '127.0.0.1') {
          final baseUri = Uri.parse(baseUrl);
          uri = resolved.replace(
            scheme: baseUri.scheme,
            host: baseUri.host,
            port: baseUri.hasPort ? baseUri.port : resolved.port,
          );
        } else {
          uri = resolved;
        }
        continue;
      }

      if (!uri.path.endsWith('/')) {
        uri = uri.replace(path: '${uri.path}/');
        continue;
      }

      return response;
    }

    return http.Response(
      '{"message":"Trop de redirections login."}',
      508,
      headers: {'content-type': 'application/json'},
    );
  }

  Future<List<PatientSummary>> fetchPatients() async {
    final response = await _httpClient.get(
      Uri.parse('$baseUrl/api/mobile/patients'),
      headers: _authHeaders(),
    );

    final json = _decodeBody(response.body);
    if (response.statusCode >= 400) {
      throw ApiException(
        json['message']?.toString() ?? 'Impossible de récupérer les patients.',
      );
    }

    final patients = (json['patients'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PatientSummary.fromJson)
        .toList();
    return patients;
  }

  Future<List<PatientSummary>> searchPatients(String query) async {
    if (query.trim().isEmpty) {
      return fetchPatients();
    }

    final response = await _httpClient.get(
      Uri.parse('$baseUrl/api/mobile/patients?q=${Uri.encodeQueryComponent(query)}'),
      headers: _authHeaders(),
    );

    final json = _decodeBody(response.body);
    if (response.statusCode >= 400) {
      throw ApiException(
        json['message']?.toString() ?? 'Erreur lors de la recherche.',
      );
    }

    final patients = (json['patients'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PatientSummary.fromJson)
        .toList();
    return patients;
  }

  Future<PatientDetail> fetchPatientDetail(int patientId) async {
    final response = await _httpClient.get(
      Uri.parse('$baseUrl/api/mobile/patients/$patientId'),
      headers: _authHeaders(),
    );

    final json = _decodeBody(response.body);
    if (response.statusCode >= 400) {
      throw ApiException(
        json['message']?.toString() ??
            'Impossible de récupérer la fiche patient.',
      );
    }

    final patient = json['patient'];
    if (patient is! Map<String, dynamic>) {
      throw ApiException('Format de réponse invalide.');
    }

    return PatientDetail.fromJson(patient);
  }

  Future<List<NoteItem>> fetchPatientNotes(int patientId) async {
    final response = await _httpClient.get(
      Uri.parse('$baseUrl/api/mobile/patients/$patientId/notes'),
      headers: _authHeaders(),
    );

    final json = _decodeBody(response.body);
    if (response.statusCode >= 400) {
      throw ApiException(
        json['message']?.toString() ??
            'Impossible de récupérer les notes.',
      );
    }

    final notesList = json['notes'] as List<dynamic>? ?? [];
    return notesList
        .whereType<Map<String, dynamic>>()
        .map(NoteItem.fromJson)
        .toList();
  }

  Future<void> addPatientNote(int patientId, String content) async {
    final response = await _httpClient.post(
      Uri.parse('$baseUrl/api/mobile/patients/$patientId/notes'),
      headers: _authHeaders()..['Content-Type'] = 'application/json',
      body: jsonEncode({'content': content}),
    );

    final json = _decodeBody(response.body);
    if (response.statusCode >= 400) {
      throw ApiException(
        json['message']?.toString() ?? 'Erreur lors de l\'ajout de la note.',
      );
    }
  }

  Map<String, String> _authHeaders() {
    if (_token == null) {
      throw ApiException('Session non authentifiée.');
    }

    return _defaultHeaders(authorization: 'Bearer $_token');
  }

  Map<String, String> _defaultHeaders({
    String? authorization,
    String? contentType,
  }) {
    final headers = <String, String>{
      'Accept': 'application/json',
      'ngrok-skip-browser-warning': 'true',
      'User-Agent': 'XynpoMobile/1.0',
    };

    if (authorization != null && authorization.isNotEmpty) {
      headers['Authorization'] = authorization;
    }

    if (contentType != null && contentType.isNotEmpty) {
      headers['Content-Type'] = contentType;
    }

    return headers;
  }

  Map<String, dynamic> _decodeBody(String body) {
    if (body.isEmpty) {
      return <String, dynamic>{};
    }
    try {
      final data = jsonDecode(body);
      if (data is Map<String, dynamic>) {
        return data;
      }
    } catch (_) {
      return <String, dynamic>{'raw': body};
    }

    return <String, dynamic>{};
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _client = MobileApiClient(baseUrl: ApiConfig.baseUrl);

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _client.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) {
        return;
      }
      await pushReplacementAnimated(context, HomePage(client: _client));
    } on ApiException catch (error) {
      setState(() {
        _error = error.message;
      });
    } catch (error) {
      setState(() {
        _error = 'Erreur réseau: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Xynpo • Connexion API')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'API: ${ApiConfig.baseUrl}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Email requis';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'Mot de passe'),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Mot de passe requis';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Se connecter'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.client});

  final MobileApiClient client;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<PatientSummary>> _patientsFuture;
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<PatientSummary> _allPatients = [];
  List<PatientSummary>? _serverPatients;
  String _currentQuery = '';
  bool _searchLoading = false;
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _patientsFuture = widget.client.fetchPatients();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();

    _searchDebounce?.cancel();

    if (query.isEmpty) {
      setState(() {
        _currentQuery = '';
        _serverPatients = null;
        _searchLoading = false;
        _searchError = null;
      });
      return;
    }

    setState(() {
      _currentQuery = query;
      _searchLoading = true;
      _searchError = null;
    });

    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _runServerSearch(query);
    });
  }

  Future<void> _runServerSearch(String query) async {
    try {
      final patients = await widget.client.searchPatients(query);
      if (!mounted || query != _currentQuery) {
        return;
      }
      setState(() {
        _serverPatients = patients;
        _searchLoading = false;
      });
    } on ApiException catch (error) {
      if (!mounted || query != _currentQuery) {
        return;
      }
      setState(() {
        _searchError = error.message;
        _searchLoading = false;
      });
    } catch (_) {
      if (!mounted || query != _currentQuery) {
        return;
      }
      setState(() {
        _searchError = 'Erreur lors de la recherche distante.';
        _searchLoading = false;
      });
    }
  }

  List<PatientSummary> _getFilteredPatients(List<PatientSummary> patients) {
    final source = _serverPatients ?? patients;

    if (_currentQuery.isEmpty) {
      return source;
    }
    
    final lowerQuery = _currentQuery.toLowerCase();
    return source
        .where((p) =>
            p.fullName.toLowerCase().contains(lowerQuery) ||
            p.city.toLowerCase().contains(lowerQuery))
        .toList();
  }

  Future<void> _reload() async {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _currentQuery = '';
      _serverPatients = null;
      _searchLoading = false;
      _searchError = null;
      _patientsFuture = widget.client.fetchPatients();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Xynpo • Patients'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Rechercher un patient...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          if (_searchLoading) const LinearProgressIndicator(minHeight: 2),
          if (_searchError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Text(
                _searchError!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          Expanded(
            child: FutureBuilder<List<PatientSummary>>(
              future: _patientsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  final message = snapshot.error is ApiException
                      ? (snapshot.error as ApiException).message
                      : 'Erreur lors du chargement des patients.';
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(message, textAlign: TextAlign.center),
                    ),
                  );
                }

                _allPatients = snapshot.data ?? const <PatientSummary>[];
                final filteredPatients = _getFilteredPatients(_allPatients);

                if (_allPatients.isEmpty) {
                  return const Center(child: Text('Aucun patient disponible.'));
                }

                if (filteredPatients.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text('Aucun patient ne correspond à "$_currentQuery"',
                          textAlign: TextAlign.center),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView.separated(
                    itemCount: filteredPatients.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final patient = filteredPatients[index];
                      return ListTile(
                        title: Text(patient.fullName),
                        subtitle: Text(
                          '${!patient.alive ? '⚠️ Décédé • ' : ''}Ville: ${patient.city} • Greffes: ${patient.greffesCount} • Opérations: ${patient.operationsCount}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          pushAnimated(
                            context,
                            PatientDetailPage(
                              client: widget.client,
                              patient: patient,
                            ),
                          );
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class PatientDetailPage extends StatefulWidget {
  const PatientDetailPage({
    super.key,
    required this.client,
    required this.patient,
  });

  final MobileApiClient client;
  final PatientSummary patient;

  @override
  State<PatientDetailPage> createState() => _PatientDetailPageState();
}

class _PatientDetailPageState extends State<PatientDetailPage> {
  late Future<PatientDetail> _detailFuture;
  late Future<List<NoteItem>> _notesFuture;
  final _noteController = TextEditingController();
  bool _isAddingNote = false;

  @override
  void initState() {
    super.initState();
    _detailFuture = widget.client.fetchPatientDetail(widget.patient.id);
    _notesFuture = widget.client.fetchPatientNotes(widget.patient.id);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _refreshNotes() {
    setState(() {
      _notesFuture = widget.client.fetchPatientNotes(widget.patient.id);
    });
  }

  Future<void> _addNote() async {
    if (_noteController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez entrer une note.')),
      );
      return;
    }

    setState(() => _isAddingNote = true);
    try {
      await widget.client.addPatientNote(
        widget.patient.id,
        _noteController.text.trim(),
      );
      _noteController.clear();
      _refreshNotes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Note ajoutée avec succès.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException ? e.message : 'Erreur lors de l\'ajout de la note.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAddingNote = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Fiche • ${widget.patient.fullName}')),
      body: FutureBuilder<PatientDetail>(
        future: _detailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            final message = snapshot.error is ApiException
                ? (snapshot.error as ApiException).message
                : 'Erreur lors du chargement de la fiche patient.';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(message, textAlign: TextAlign.center),
              ),
            );
          }

          final detail = snapshot.data;
          if (detail == null) {
            return const Center(child: Text('Aucune donnée patient.'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        detail.fullName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text('Ville: ${detail.city}'),
                      Text('Email: ${detail.email ?? '—'}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Rendez-vous (${detail.rdv.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (detail.rdv.isEmpty)
                const Text('Aucun rendez-vous.')
              else
                ...detail.rdv.map(
                  (item) => Card(
                    child: ListTile(
                      title: Text(item.title),
                      subtitle: Text(
                        '${item.scheduledAtDisplay}\n${item.location ?? 'Sans lieu'}',
                      ),
                      isThreeLine: true,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                'Photos (${detail.photos.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (detail.photos.isEmpty)
                const Text('Aucune photo.')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: detail.photos
                      .map(
                        (photo) => ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            photo.url,
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                                  width: 100,
                                  height: 100,
                                  color: Colors.grey.shade200,
                                  child: const Icon(
                                    Icons.broken_image_outlined,
                                  ),
                                ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              const SizedBox(height: 12),
              Text(
                'Rapports (${detail.rapports.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (detail.rapports.isEmpty)
                const Text('Aucun rapport.')
              else
                ...detail.rapports.map(
                  (rapport) => Card(
                    child: ListTile(
                      title: Text(rapport.title),
                      subtitle: Text(rapport.text ?? ''),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                'Notes de consultation',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<NoteItem>>(
                future: _notesFuture,
                builder: (context, notesSnapshot) {
                  if (notesSnapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (notesSnapshot.hasError) {
                    final message = notesSnapshot.error is ApiException
                        ? (notesSnapshot.error as ApiException).message
                        : 'Erreur lors du chargement des notes.';
                    return Text('Erreur: $message');
                  }

                  final notes = notesSnapshot.data ?? [];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (notes.isEmpty)
                        const Text('Aucune note.')
                      else
                        ...notes.map(
                          (note) => Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    note.createdBy.name,
                                    style:
                                        Theme.of(context).textTheme.labelMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(note.content),
                                  const SizedBox(height: 8),
                                  Text(
                                    note.createdAt,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Colors.grey[600],
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Text(
                        'Ajouter une note',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _noteController,
                        decoration: InputDecoration(
                          hintText: 'Entrez votre note...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                        maxLines: 3,
                        enabled: !_isAddingNote,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isAddingNote ? null : _addNote,
                          icon: _isAddingNote
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.add),
                          label: Text(
                            _isAddingNote
                                ? 'Ajout en cours...'
                                : 'Ajouter la note',
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class PatientSummary {
  const PatientSummary({
    required this.id,
    required this.fullName,
    required this.name,
    required this.firstName,
    required this.city,
    required this.alive,
    required this.greffesCount,
    required this.operationsCount,
  });

  final int id;
  final String fullName;
  final String name;
  final String firstName;
  final String city;
  final bool alive;
  final int greffesCount;
  final int operationsCount;

  factory PatientSummary.fromJson(Map<String, dynamic> json) {
    return PatientSummary(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      firstName: json['firstName']?.toString() ?? '',
      fullName: (json['fullName']?.toString().trim().isNotEmpty ?? false)
          ? json['fullName'].toString()
          : '${json['name'] ?? ''} ${json['firstName'] ?? ''}'.trim(),
      city: json['city']?.toString() ?? '—',
      alive: json['alive'] as bool? ?? true,
      greffesCount: (json['greffesCount'] as num?)?.toInt() ?? 0,
      operationsCount: (json['operationsCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class PatientDetail {
  const PatientDetail({
    required this.id,
    required this.fullName,
    required this.city,
    required this.email,
    required this.rdv,
    required this.photos,
    required this.rapports,
  });

  final int id;
  final String fullName;
  final String city;
  final String? email;
  final List<RdvItem> rdv;
  final List<PhotoItem> photos;
  final List<RapportItem> rapports;

  factory PatientDetail.fromJson(Map<String, dynamic> json) {
    final rdvRaw = (json['rdv'] as List<dynamic>? ?? const []);
    final photosRaw = (json['photos'] as List<dynamic>? ?? const []);
    final rapportsRaw = (json['rapports'] as List<dynamic>? ?? const []);

    return PatientDetail(
      id: (json['id'] as num?)?.toInt() ?? 0,
      fullName: (json['fullName']?.toString().trim().isNotEmpty ?? false)
          ? json['fullName'].toString()
          : '${json['name'] ?? ''} ${json['firstName'] ?? ''}'.trim(),
      city: json['city']?.toString() ?? '—',
      email: json['email']?.toString(),
      rdv: rdvRaw
          .whereType<Map<String, dynamic>>()
          .map(RdvItem.fromJson)
          .toList(),
      photos: photosRaw
          .whereType<Map<String, dynamic>>()
          .map(PhotoItem.fromJson)
          .toList(),
      rapports: rapportsRaw
          .whereType<Map<String, dynamic>>()
          .map(RapportItem.fromJson)
          .toList(),
    );
  }
}

class RdvItem {
  const RdvItem({
    required this.title,
    required this.scheduledAtDisplay,
    required this.location,
  });

  final String title;
  final String scheduledAtDisplay;
  final String? location;

  factory RdvItem.fromJson(Map<String, dynamic> json) {
    final raw = json['scheduledAt']?.toString();
    final parsed = raw == null ? null : DateTime.tryParse(raw);
    return RdvItem(
      title: json['title']?.toString() ?? 'RDV',
      scheduledAtDisplay: parsed == null
          ? (raw ?? 'Date inconnue')
          : '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year} ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}',
      location: json['location']?.toString(),
    );
  }
}

class PhotoItem {
  const PhotoItem({required this.url});

  final String url;

  factory PhotoItem.fromJson(Map<String, dynamic> json) {
    return PhotoItem(url: json['url']?.toString() ?? '');
  }
}

class RapportItem {
  const RapportItem({required this.title, required this.text});

  final String title;
  final String? text;

  factory RapportItem.fromJson(Map<String, dynamic> json) {
    return RapportItem(
      title: json['title']?.toString() ?? 'Rapport',
      text: json['text']?.toString(),
    );
  }
}

class NoteItem {
  const NoteItem({
    required this.id,
    required this.content,
    required this.createdBy,
    required this.createdAt,
  });

  final int id;
  final String content;
  final UserInfo createdBy;
  final String createdAt;

  factory NoteItem.fromJson(Map<String, dynamic> json) {
    final createdByData = json['createdBy'] as Map<String, dynamic>? ?? {};
    return NoteItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      content: json['content']?.toString() ?? '',
      createdBy: UserInfo.fromJson(createdByData),
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }
}

class UserInfo {
  const UserInfo({
    required this.id,
    required this.email,
    required this.name,
  });

  final int id;
  final String email;
  final String name;

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      id: (json['id'] as num?)?.toInt() ?? 0,
      email: json['email']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }
}

class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
