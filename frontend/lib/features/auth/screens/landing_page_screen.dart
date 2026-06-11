import 'package:flutter/material.dart';
import 'package:tonten/features/auth/screens/login_screen.dart';

class LandingPageScreen extends StatefulWidget {
  const LandingPageScreen({super.key});

  @override
  State<LandingPageScreen> createState() => _LandingPageScreenState();
}

class _LandingPageScreenState extends State<LandingPageScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isScrolled = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.offset > 50 && !_isScrolled) {
        setState(() => _isScrolled = true);
      } else if (_scrollController.offset <= 50 && _isScrolled) {
        setState(() => _isScrolled = false);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSection(GlobalKey key) {
    Scrollable.ensureVisible(
      key.currentContext!,
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
    );
  }

  final _heroKey = GlobalKey();
  final _howItWorksKey = GlobalKey();
  final _pricingKey = GlobalKey();
  final _aboutKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: colorScheme.surface,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(colorScheme),
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          children: [
            _buildHeroSection(key: _heroKey, colorScheme: colorScheme),
            _buildHowItWorksSection(key: _howItWorksKey, colorScheme: colorScheme),
            _buildPricingSection(key: _pricingKey, colorScheme: colorScheme),
            _buildAboutSection(key: _aboutKey, colorScheme: colorScheme),
            _buildFooter(colorScheme),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ColorScheme colorScheme) {
    return AppBar(
      // Kiedy przeskrolujemy, tło to surface (lekkie krycie)
      backgroundColor: _isScrolled ? colorScheme.surface.withOpacity(0.95) : Colors.transparent,
      elevation: _isScrolled ? 4 : 0,
      title: Row(
        children: [
          Icon(Icons.analytics, color: colorScheme.primary, size: 32),
          const SizedBox(width: 12),
          Text(
            'e-ROCH',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
              fontSize: 24,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 48),
          _NavBarItem(title: 'Jak to działa?', onTap: () => _scrollToSection(_howItWorksKey), colorScheme: colorScheme),
          _NavBarItem(title: 'Pakiety', onTap: () => _scrollToSection(_pricingKey), colorScheme: colorScheme),
          _NavBarItem(title: 'O nas', onTap: () => _scrollToSection(_aboutKey), colorScheme: colorScheme),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
          },
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.onSurface,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          ),
          child: const Text('Zaloguj się', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen(initialTabIndex: 1)));
          },
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Załóż konto', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 24),
      ],
    );
  }

  Widget _buildHeroSection({required GlobalKey key, required ColorScheme colorScheme}) {
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 160, 24, 120),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colorScheme.surface, colorScheme.surfaceContainerHigh],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colorScheme.primary.withOpacity(0.2)),
            ),
            child: Text(
              'Automatyzacja E-commerce nowej generacji',
              style: TextStyle(color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.w600, letterSpacing: 0.5),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Monitoruj ceny konkurencji.\nZwiększaj zyski automatycznie.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 64,
              fontWeight: FontWeight.w900,
              height: 1.1,
              color: colorScheme.onSurface,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Nasz zespół ekspertów buduje scrapery dla Twojej konkurencji,\nanalizuje rynek i rekomenduje optymalne ceny dla Twoich produktów.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              color: colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 48),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen(initialTabIndex: 1)));
                },
                icon: const Icon(Icons.rocket_launch),
                label: const Text('Rozpocznij darmowy test', style: TextStyle(fontSize: 18)),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorksSection({required GlobalKey key, required ColorScheme colorScheme}) {
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 120, horizontal: 24),
      color: colorScheme.surfaceContainer,
      child: Column(
        children: [
          Text(
            'Jak to działa?',
            style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
          ),
          const SizedBox(height: 16),
          Text(
            'Uruchomienie automatyzacji w 3 prostych krokach',
            style: TextStyle(fontSize: 20, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 64),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStepCard(
                icon: Icons.person_add,
                title: '1. Rejestracja',
                description: 'Podajesz adresy stron swojej konkurencji. Resztą zajmuje się nasz doświadczony zespół analityków.',
                color: Colors.blueAccent,
                colorScheme: colorScheme,
              ),
              const SizedBox(width: 24),
              _buildStepCard(
                icon: Icons.upload_file,
                title: '2. Wgranie produktów',
                description: 'Przesyłasz listę swoich produktów (plik lub URL). My automatycznie łączymy je z produktami u konkurencji.',
                color: Colors.purpleAccent,
                colorScheme: colorScheme,
              ),
              const SizedBox(width: 24),
              _buildStepCard(
                icon: Icons.insights,
                title: '3. Zyski',
                description: 'Codziennie rano otrzymujesz gotowe raporty z rekomendacjami cen, które maksymalizują Twoją marżę.',
                color: Colors.greenAccent,
                colorScheme: colorScheme,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard({required IconData icon, required String title, required String description, required Color color, required ColorScheme colorScheme}) {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.05), blurRadius: 24, offset: const Offset(0, 12)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 48, color: color),
          ),
          const SizedBox(height: 24),
          Text(title, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
          const SizedBox(height: 16),
          Text(description, style: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant, height: 1.5)),
        ],
      ),
    );
  }

  Widget _buildPricingSection({required GlobalKey key, required ColorScheme colorScheme}) {
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 120, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colorScheme.surfaceContainerHigh, colorScheme.surface],
        ),
      ),
      child: Column(
        children: [
          Text(
            'Proste i przejrzyste pakiety',
            style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
          ),
          const SizedBox(height: 16),
          Text(
            'Wybierz plan idealnie dopasowany do potrzeb Twojego biznesu',
            style: TextStyle(fontSize: 20, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 64),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildPricingCard(
                title: 'Basic',
                price: '300 zł',
                period: '/ miesiąc',
                features: ['Codzienna aktualizacja cen konkurencji'],
                buttonText: 'Wybierz Basic',
                isHighlighted: false,
                colorScheme: colorScheme,
              ),
              const SizedBox(width: 32),
              _buildPricingCard(
                title: 'Pro',
                price: '400 zł',
                period: '/ miesiąc',
                features: ['Codzienna aktualizacja cen konkurencji', 'Historia cen konkurencji'],
                buttonText: 'Wybierz Pro',
                isHighlighted: true,
                colorScheme: colorScheme,
              ),
              const SizedBox(width: 32),
              _buildPricingCard(
                title: 'Enterprise',
                price: '500 zł',
                period: '/ miesiąc',
                features: ['Codzienna aktualizacja cen konkurencji', 'Historia cen konkurencji', 'Inteligentna rekomendacja cen'],
                buttonText: 'Wybierz Enterprise',
                isHighlighted: false,
                colorScheme: colorScheme,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPricingCard({
    required String title,
    required String price,
    required String period,
    required List<String> features,
    required String buttonText,
    required bool isHighlighted,
    required ColorScheme colorScheme,
  }) {
    return Container(
      width: 350,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: isHighlighted ? colorScheme.surfaceContainerHighest : colorScheme.surface,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: isHighlighted ? colorScheme.primary : colorScheme.outlineVariant,
          width: isHighlighted ? 2 : 1,
        ),
        boxShadow: isHighlighted
            ? [BoxShadow(color: colorScheme.primary.withOpacity(0.2), blurRadius: 32, offset: const Offset(0, 16))]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isHighlighted)
            Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('NAJCZĘŚCIEJ WYBIERANY', style: TextStyle(color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
            ),
          Text(title, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(price, style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
              const SizedBox(width: 8),
              Text(period, style: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 32),
          Divider(color: colorScheme.outlineVariant),
          const SizedBox(height: 32),
          ...features.map((feature) => Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: colorScheme.primary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Text(feature, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 16))),
                  ],
                ),
              )),
          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen(initialTabIndex: 1)));
              },
              style: FilledButton.styleFrom(
                backgroundColor: isHighlighted ? colorScheme.primary : colorScheme.surfaceContainerHighest,
                foregroundColor: isHighlighted ? colorScheme.onPrimary : colorScheme.onSurface,
                padding: const EdgeInsets.symmetric(vertical: 24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(buttonText, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutSection({required GlobalKey key, required ColorScheme colorScheme}) {
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 120, horizontal: 24),
      color: colorScheme.surfaceContainer,
      child: Center(
        child: Container(
          width: 800,
          padding: const EdgeInsets.all(64),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              const Icon(Icons.lightbulb_outline, size: 64, color: Colors.amberAccent),
              const SizedBox(height: 32),
              Text(
                'O nas - innowacja od studentów dla biznesu',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
              ),
              const SizedBox(height: 32),
              Text(
                'e-ROCH to nowoczesny startup stworzony przez zespół ambitnych studentów.\n\nNasze narzędzie jest idealnie dostosowane do potrzeb małych i średnich firm e-commerce. Dzięki nam nie będziesz musiał już ręcznie wchodzić na strony konkurencji, aby sprawdzić, czy cena produktu się nie zmieniła – wszystko to znajdziesz na jednej, specjalnie do tego przeznaczonej platformie. \n\nZapewniamy wnikliwą analizę największych różnic cenowych oraz inteligentne rekomendacje cen, które pomogą Ci zmaksymalizować zyski. Dodatkowo oferujemy możliwość śledzenia pełnej historii zmian cen danych produktów u Twoich konkurentów. Z nami zyskujesz przewagę na rynku!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: colorScheme.onSurfaceVariant, height: 1.8),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(48),
      color: colorScheme.surface,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.security, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text('Bezpieczeństwo gwarantowane. Twoje dane są szyfrowane.', style: TextStyle(color: colorScheme.onSurfaceVariant)),
              const SizedBox(width: 32),
              Icon(Icons.support_agent, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text('Wsparcie techniczne 24/7', style: TextStyle(color: colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 24),
          Divider(color: colorScheme.outlineVariant),
          const SizedBox(height: 24),
          Text('© 2026 e-ROCH Startup. Wszelkie prawa zastrzeżone.', style: TextStyle(color: colorScheme.onSurfaceVariant.withOpacity(0.5))),
        ],
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final String title;
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  const _NavBarItem({required this.title, required this.onTap, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.onSurface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
    );
  }
}