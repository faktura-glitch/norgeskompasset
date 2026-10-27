import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/auth_service.dart';
import '../widgets/common.dart';

import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// Full-screen sign-in with a Norges Kompasset photo backdrop.
/// Supports login, account creation and password reset — all through
/// Firebase Auth.
class LoginScreen extends StatefulWidget {
  /// Shown when Firebase hasn't been configured yet (missing keys).
  final String? configError;
  const LoginScreen({super.key, this.configError});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _auth = AuthService();
  bool _registerMode = false;
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_registerMode) {
        await _auth.register(_email.text, _password.text);
      } else {
        await _auth.signIn(_email.text, _password.text);
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Noe gikk galt – prøv igjen om et øyeblikk.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Shared handler for the social providers — same error surface as
  /// [_submit]. A cancelled picker leaves the user signed out (null)
  /// without an error.
  Future<void> _social(Future<void> Function() fn) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fn();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Noe gikk galt – prøv igjen om et øyeblikk.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The google_sign_in and sign_in_with_apple plugins have no Windows
  /// implementation — the buttons stay hidden there rather than
  /// offering a flow that can only fail.
  bool get _socialSupported =>
      kIsWeb || defaultTargetPlatform != TargetPlatform.windows;

  Future<void> _forgotPassword() async {
    final ctrl = TextEditingController(text: _email.text);
    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tilbakestill passord'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Skriv inn e-posten din, så sender vi en lenke for å sette nytt passord.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'E-post',
                prefixIcon: Icon(Icons.mail_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await _auth.sendPasswordReset(ctrl.text);
                if (ctx.mounted) Navigator.pop(ctx, true);
              } on AuthException catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx)
                      .showSnackBar(SnackBar(content: Text(e.message)));
                }
              }
            },
            child: const Text('Send lenke'),
          ),
        ],
      ),
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lenke sendt – sjekk innboksen (og søppelpost).'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = context.isWide;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-bleed photo from norgeskompasset.no with silhouette fallback
          CachedNetworkImage(
            imageUrl: NkImages.nkTrail,
            fit: BoxFit.cover,
            placeholder: (ctx, _) =>
                const ColoredBox(color: NkColors.primaryBlueDark),
            errorWidget: (ctx, _, _) =>
                const ColoredBox(color: NkColors.primaryBlueDark),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  NkColors.primaryBlueDark.withValues(alpha: 0.55),
                  Colors.black.withValues(alpha: 0.75),
                ],
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 420 : 380),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.explore, color: Colors.white, size: 52),
                    const SizedBox(height: 10),
                    const Text(
                      'NorgesKompasset',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Text(
                      'Planlegg · Pakk · Gå · Lær',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 26),
                    Card(
                      elevation: 10,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _registerMode ? 'Opprett konto' : 'Logg inn',
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Konto gir tilgang til turdeling og synkronisering. '
                                'Last ned kart før du drar uten dekning.',
                              ),
                              const SizedBox(height: 12),
                              if (widget.configError != null)
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: NkColors.warningAmber.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    widget.configError!,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              TextFormField(
                                controller: _email,
                                autofillHints: const [
                                  AutofillHints.username,
                                  AutofillHints.email,
                                ],
                                textInputAction: TextInputAction.next,
                                keyboardType: TextInputType.emailAddress,
                                autocorrect: false,
                                decoration: const InputDecoration(
                                  labelText: 'E-post',
                                  prefixIcon: Icon(Icons.mail_outline),
                                ),
                                validator: (v) =>
                                    (v == null || !v.contains('@'))
                                    ? 'Oppgi en gyldig e-post'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _password,
                                autofillHints: [
                                  _registerMode
                                      ? AutofillHints.newPassword
                                      : AutofillHints.password,
                                ],
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) {
                                  if (!_busy) _submit();
                                },
                                obscureText: _obscure,
                                decoration: InputDecoration(
                                  labelText: 'Passord',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    tooltip: _obscure
                                        ? 'Vis passord'
                                        : 'Skjul passord',
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                  ),
                                ),
                                validator: (v) => (v == null || v.length < 6)
                                    ? 'Minst 6 tegn'
                                    : null,
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _busy ? null : _forgotPassword,
                                  child: const Text(
                                    'Glemt passord?',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                              if (_error != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: NkColors.dangerRed,
                                      fontSize: 13,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              FilledButton(
                                onPressed: (_busy || widget.configError != null)
                                    ? null
                                    : _submit,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                child: _busy
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        _registerMode
                                            ? 'Opprett konto'
                                            : 'Logg inn',
                                      ),
                              ),
                              if (_socialSupported) ...[
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    const Expanded(child: Divider()),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      child: Text(
                                        'eller',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: NkColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                    const Expanded(child: Divider()),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  onPressed:
                                      (_busy || widget.configError != null)
                                      ? null
                                      : () => _social(
                                          () => _auth.signInWithGoogle(),
                                        ),
                                  icon: const Icon(
                                    Icons.g_mobiledata,
                                    size: 26,
                                  ),
                                  label: const Text('Fortsett med Google'),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed:
                                      (_busy || widget.configError != null)
                                      ? null
                                      : () => _social(
                                          () => _auth.signInWithApple(),
                                        ),
                                  icon: const Icon(Icons.apple, size: 20),
                                  label: const Text('Fortsett med Apple'),
                                ),
                              ],
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => context
                                          .read<AppState>()
                                          .useLocalMode(true),
                                child: const Text('Fortsett lokalt uten konto'),
                              ),
                              const Text(
                                'Lokal modus bruker turene på denne enheten. '
                                'Innlogging kreves for sky, turkoder og publisering.',
                              ),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                        _registerMode = !_registerMode;
                                        _error = null;
                                      }),
                                child: Text(
                                  _registerMode
                                      ? 'Har du konto? Logg inn'
                                      : 'Ny bruker? Opprett konto',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Foto: norgeskompasset.no',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
