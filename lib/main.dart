import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VaultApp());
}

class VaultApp extends StatelessWidget {
  const VaultApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Message Board Vault',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6654B5)),
      useMaterial3: true,
    ),
    home: const StartupScreen(),
  );
}

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});
  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  late Future<FirebaseApp> initialization;
  @override
  void initState() {
    super.initState();
    initialization = Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<FirebaseApp>(
    future: initialization,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Firebase could not start.'),
                ElevatedButton(
                  onPressed: () => setState(
                    () => initialization = Firebase.initializeApp(
                      options: DefaultFirebaseOptions.currentPlatform,
                    ),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      if (snapshot.connectionState != ConnectionState.done)
        return const Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 76),
                SizedBox(height: 16),
                Text(
                  'Message Board Vault',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 24),
                CircularProgressIndicator(),
              ],
            ),
          ),
        );
      return const AuthGate();
    },
  );
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;
  Future<void> register({
    required String email,
    required String password,
    required String first,
    required String last,
  }) async {
    final result = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = result.user!;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'firstName': first.trim(),
      'lastName': last.trim(),
      'role': 'member',
      'registrationDateTime': FieldValue.serverTimestamp(),
    });
    await user.updateDisplayName('${first.trim()} ${last.trim()}');
  }

  Future<void> signIn(String email, String password) async =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
  Future<void> signOut() async => _auth.signOut();
}

class BoardService {
  final CollectionReference<Map<String, dynamic>> _messages = FirebaseFirestore
      .instance
      .collection('messages');
  Stream<QuerySnapshot<Map<String, dynamic>>> watchMessages() =>
      _messages.orderBy('createdAt', descending: true).snapshots();
  Future<void> create(String text) async {
    final user = FirebaseAuth.instance.currentUser!;
    await _messages.add({
      'text': text.trim(),
      'authorUid': user.uid,
      'authorName': user.displayName ?? user.email ?? 'Member',
      'createdAt': FieldValue.serverTimestamp(),
      'editedAt': null,
    });
  }

  Future<void> update(String id, String text) async => _messages.doc(id).update(
    {'text': text.trim(), 'editedAt': FieldValue.serverTimestamp()},
  );
  Future<void> delete(String id) async => _messages.doc(id).delete();
  Future<void> testOtherUserUpdate(String id) async =>
      _messages.doc(id).update({'text': 'Unauthorized edit attempt'});
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: AuthService().authStateChanges,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting)
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      return snapshot.data == null ? const LoginScreen() : const BoardScreen();
    },
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  final first = TextEditingController();
  final last = TextEditingController();
  bool register = false;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    first.dispose();
    last.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate() || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (register) {
        await AuthService().register(
          email: email.text,
          password: password.text,
          first: first.text,
          last: last.text,
        );
      } else {
        await AuthService().signIn(email.text, password.text);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => error = e.message ?? e.code);
    } catch (e) {
      if (mounted) setState(() => error = 'Could not complete request: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.forum_rounded,
                  size: 72,
                  color: Color(0xFF6654B5),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Message Board Vault',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  register
                      ? 'Create your account'
                      : 'Sign in to join the conversation',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (register) ...[
                  TextFormField(
                    controller: first,
                    decoration: const InputDecoration(
                      labelText: 'First name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? 'Enter your first name'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: last,
                    decoration: const InputDecoration(
                      labelText: 'Last name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? 'Enter your last name'
                        : null,
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v ?? '').contains('@') && (v ?? '').contains('.')
                      ? null
                      : 'Enter a valid email',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v ?? '').length < 6 ? 'Use at least 6 characters' : null,
                ),
                const SizedBox(height: 12),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: busy ? null : submit,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      busy
                          ? 'Please wait...'
                          : register
                          ? 'Register'
                          : 'Sign in',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          register = !register;
                          error = null;
                        }),
                  child: Text(
                    register
                        ? 'Already have an account? Sign in'
                        : 'New here? Create an account',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key});
  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  final service = BoardService();
  final textController = TextEditingController();
  bool posting = false;
  String? error;
  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  Future<void> post() async {
    if (posting || textController.text.trim().isEmpty) return;
    setState(() {
      posting = true;
      error = null;
    });
    try {
      await service.create(textController.text);
      textController.clear();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => posting = false);
    }
  }

  Future<void> editMessage(String id, String original) async {
    final edit = TextEditingController(text: original);
    final replacement = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit your message'),
        content: TextField(
          controller: edit,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Message'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, edit.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    edit.dispose();
    if (replacement == null || replacement.isEmpty || replacement == original)
      return;
    try {
      await service.update(id, replacement);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Edit failed: $e')));
    }
  }

  Future<void> deleteMessage(String id) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await service.delete(id);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Message Board Vault'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async => AuthService().signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: textController,
                  maxLines: 2,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Write a message',
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: posting ? null : post,
                    icon: const Icon(Icons.send),
                    label: Text(posting ? 'Posting...' : 'Post message'),
                  ),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: service.watchMessages(),
              builder: (context, snapshot) {
                if (snapshot.hasError)
                  return Center(
                    child: Text(
                      'Could not load messages: ${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  );
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());
                final docs = snapshot.data!.docs;
                if (docs.isEmpty)
                  return const Center(
                    child: Text('No messages yet. Be the first to post!'),
                  );
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final data = doc.data();
                    final own = data['authorUid'] == uid;
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      child: ListTile(
                        title: Text(
                          '${data['authorName'] ?? 'Member'}${own ? ' (you)' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('${data['text'] ?? ''}'),
                        ),
                        trailing: own
                            ? PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit')
                                    editMessage(
                                      doc.id,
                                      '${data['text'] ?? ''}',
                                    );
                                  if (value == 'delete') deleteMessage(doc.id);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                              )
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
