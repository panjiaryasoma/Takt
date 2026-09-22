import 'package:flutter/material.dart';

const Color kNavy = Color(0xFF2D3250);
const Color kIndigo = Color(0xFF424769);
const Color kPeriwinkle = Color(0xFF676F9D);
const Color kPeach = Color(0xFFF9B17A);
const Color kWhite = Color(0xFFFFFFFF);
const Color kMuted = Color(0xFF9DA3C8);

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
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kNavy,
        colorScheme: const ColorScheme.dark(
          primary: kPeach,
          secondary: kPeach,
          surface: kIndigo,
          background: kNavy,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: kNavy,
          foregroundColor: kWhite,
          elevation: 0,
        ),
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
      backgroundColor: kNavy,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text(
                    'Takt',
                    style: TextStyle(
                      color: kWhite,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: kPeach,
                    child: Icon(Icons.person, color: kNavy, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Good morning, Stephanie',
                style: TextStyle(
                  color: kWhite,
                  fontSize: 22,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Here is your decision support overview.',
                style: TextStyle(
                  color: kMuted,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: kIndigo,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: kPeriwinkle.withOpacity(0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text(
                          'Today',
                          style: TextStyle(
                            color: kWhite,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '89% focus',
                          style: TextStyle(
                            color: kPeach,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Recommended window',
                                style: TextStyle(
                                  color: kMuted,
                                  fontSize: 12,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                '2:30 PM - 4:00 PM',
                                style: TextStyle(
                                  color: kWhite,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: kPeach,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_forward,
                            color: kNavy,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: const LinearProgressIndicator(
                        value: 0.74,
                        minHeight: 8,
                        backgroundColor: kNavy,
                        valueColor: AlwaysStoppedAnimation<Color>(kPeach),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Row(
                      children: [
                        Expanded(
                          child: _MetricTile(label: 'Capacity', value: '75%'),
                        ),
                        Expanded(
                          child: _MetricTile(label: 'Priority', value: 'High'),
                        ),
                        Expanded(
                          child: _MetricTile(label: 'Risk', value: 'Low'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: const [
                  _FilterChip(label: 'Today'),
                  SizedBox(width: 10),
                  _FilterChip(label: 'Week', selected: false),
                  SizedBox(width: 10),
                  _FilterChip(label: 'Month', selected: false),
                ],
              ),
              const SizedBox(height: 20),
              const _ActionCard(
                title: 'My Schedule',
                subtitle: 'Review fixed and flexible commitments.',
                icon: Icons.calendar_month,
                accent: kPeach,
              ),
              const SizedBox(height: 14),
              const _ActionCard(
                title: 'Analyze Competition',
                subtitle: 'Paste a URL or upload rules to build a verified brief.',
                icon: Icons.search_rounded,
                accent: kPeriwinkle,
              ),
              const SizedBox(height: 14),
              const _ActionCard(
                title: 'Saved Plans',
                subtitle: 'Review recommendations and re-evaluate decisions.',
                icon: Icons.bookmark_rounded,
                accent: kPeach,
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: kNavy,
          border: Border(top: BorderSide(color: kPeriwinkle, width: 0.4)),
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: kNavy,
          selectedItemColor: kPeach,
          unselectedItemColor: kPeriwinkle,
          showUnselectedLabels: true,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.calendar_today_rounded), label: 'Calendar'),
            BottomNavigationBarItem(icon: Icon(Icons.insights_rounded), label: 'Insights'),
            BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: kMuted, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: kWhite,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    this.selected = true,
  });

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? kPeach : kIndigo,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? kNavy : kWhite,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kIndigo,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kPeriwinkle.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: kWhite,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: kMuted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: kPeriwinkle),
        ],
      ),
    );
  }
}
