import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo animada
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10A37F).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF10A37F).withValues(alpha: 0.4),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10A37F).withValues(alpha: 0.3),
                          blurRadius: 30,
                          spreadRadius: 5,
                        )
                      ],
                    ),
                    child: const Icon(
                      Icons.calendar_month_rounded,
                      size: 65,
                      color: Color(0xFF10A37F),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Plantão Operacional',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10A37F).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF10A37F).withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Text(
                      'PRO',
                      style: TextStyle(
                        color: Color(0xFF10A37F),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Agenda inteligente para equipes e famílias',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  // Features
                  const _FeaturePill(
                    icon: Icons.share_outlined,
                    label: 'Compromissos Compartilhados',
                    color: Color(0xFF10A37F),
                  ),
                  const SizedBox(height: 12),
                  const _FeaturePill(
                    icon: Icons.auto_fix_high_rounded,
                    label: 'Gerador de Escala Automática',
                    color: Color(0xFF3949AB),
                  ),
                  const SizedBox(height: 12),
                  const _FeaturePill(
                    icon: Icons.calendar_today_rounded,
                    label: 'Google Calendar Integrado',
                    color: Color(0xFFE53935),
                  ),
                  const SizedBox(height: 12),
                  const _FeaturePill(
                    icon: Icons.sync_rounded,
                    label: 'Sincronização em Tempo Real',
                    color: Color(0xFFF57F17),
                  ),
                  const SizedBox(height: 48),

                  // Botão entrar
                  SizedBox(
                    width: double.infinity,
                    child: auth.isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF10A37F),
                            ))
                        : ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF10A37F),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 4,
                            ),
                            icon: const Icon(Icons.login_rounded, size: 22),
                            label: const Text(
                              'Entrar com Google',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            onPressed: () async {
                              final authService = context.read<AuthService>();
                              await authService.signIn();
                              if (context.mounted && authService.errorMessage != null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(authService.errorMessage!),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              }
                            },
                          ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Dados sincronizados de forma segura com Firebase',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _FeaturePill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 14),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
