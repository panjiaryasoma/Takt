import 'package:flutter/material.dart';

void main() {
  runApp(const TaktApp());
}

class TaktApp extends StatelessWidget {
  const TaktApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Takt',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5A3FFF)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Takt')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Competition decision support',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Understand the opportunity, compare it with your real calendar, '
            'then choose what to do. Suggestions are not commitments.',
          ),
          const SizedBox(height: 24),
          const _ActionCard(
            title: 'My Schedule',
            subtitle: 'Review fixed and flexible commitments.',
          ),
          const _ActionCard(
            title: 'Analyze Competition',
            subtitle: 'Paste a URL or upload rules to build a verified brief.',
          ),
          const _ActionCard(
            title: 'Saved Plans',
            subtitle: 'Review recommendations, progress, and re-evaluate.',
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
