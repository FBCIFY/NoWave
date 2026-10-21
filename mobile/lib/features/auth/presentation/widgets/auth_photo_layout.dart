import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme.dart';

/// Fonds photo des écrans d'authentification et de création de profil.
abstract final class AuthBackgrounds {
  static const all = [
    'assets/images/auth/auth_wave.jpg',
    'assets/images/auth/auth_sunset.jpg',
    'assets/images/auth/auth_open_sea.jpg',
  ];

  /// Fond tiré au hasard une seule fois par lancement de l'app : le même sur
  /// tous les écrans pendant la session (la photo ne change pas en passant de
  /// la connexion à l'inscription), un autre au lancement suivant.
  static final current = all[math.Random().nextInt(all.length)];
}

/// Mise en page des écrans d'authentification et de création de profil :
/// photo plein écran ([AuthBackgrounds.current]), logo en haut, titre et
/// formulaire en bas sur un voile sombre.
///
/// La photo reste fixe quand le clavier s'ouvre : seul le contenu remonte et
/// défile. Le voile suit le formulaire, qui reste donc lisible même quand il
/// remonte sur la partie claire de la photo.
class AuthPhotoLayout extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final bool showBackButton;
  final VoidCallback? onBack;

  /// Affiché au-dessus du titre (progression d'un parcours). Il ne glisse
  /// pas avec les pages.
  final Widget? header;

  /// Page affichée d'un parcours en plusieurs pages. Quand elle change, le
  /// titre et le formulaire glissent depuis la droite, ou depuis la gauche en
  /// revenant en arrière ; la photo et le logo ne bougent pas.
  final int? page;

  const AuthPhotoLayout({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.showBackButton = false,
    this.onBack,
    this.header,
    this.page,
  });

  /// Hauteur du fondu en haut de la zone qui défile.
  static const _edgeFade = 24.0;

  @override
  Widget build(BuildContext context) {
    // Petits écrans (iPhone SE) : logo réduit pour que le formulaire tienne
    // sans défiler. Calculé sur la taille de l'écran, et non sur la place
    // restante, pour que le logo ne change pas de taille quand le clavier
    // s'ouvre.
    final isCompact = MediaQuery.sizeOf(context).height < 700;

    // Le haut des photos est un ciel clair : icônes de la barre d'état
    // sombres.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            AuthBackgrounds.current,
            fit: BoxFit.cover,
            // Évite un flash blanc pendant le décodage de la photo.
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) =>
                const ColoredBox(color: AppColors.slate900),
          ),
          // Clavier ouvert, la zone qui défile s'arrête en haut du clavier et
          // coupe le voile du formulaire : il continue ici derrière le
          // clavier, translucide sur iOS, pour que la photo claire ne
          // réapparaisse pas en dessous.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: MediaQuery.viewInsetsOf(context).bottom,
            child: ColoredBox(color: _FormScrimPainter.bottomColor),
          ),
          Scaffold(
            resizeToAvoidBottomInset: true,
            backgroundColor: Colors.transparent,
            body: SafeArea(
              // La marge du bas est ajoutée dans la zone qui défile : le voile
              // du formulaire descend ainsi jusqu'au bas de l'écran (ou
              // jusqu'au clavier).
              bottom: false,
              child: Column(
                children: [
                  SizedBox(
                    height: 52,
                    child: showBackButton
                        ? Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: IconButton(
                                onPressed:
                                    onBack ?? () => Navigator.of(context).pop(),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.white.withValues(
                                    alpha: 0.75,
                                  ),
                                  foregroundColor: AppColors.slate900,
                                  fixedSize: const Size(44, 44),
                                ),
                                icon: const Icon(Icons.arrow_back, size: 22),
                                tooltip: 'Retour',
                              ),
                            ),
                          )
                        : null,
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final bottomPadding = math.max(
                          16.0,
                          MediaQuery.paddingOf(context).bottom,
                        );

                        // Fondu en haut de la zone qui défile : quand le
                        // contenu remonte (clavier ouvert, petit écran), lui
                        // et son voile disparaissent en douceur au lieu d'être
                        // coupés net.
                        return ShaderMask(
                          blendMode: BlendMode.dstIn,
                          shaderCallback: (bounds) => LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: [
                              0,
                              (_edgeFade / bounds.height).clamp(0.0, 1.0),
                            ],
                            colors: const [Colors.transparent, Colors.white],
                          ).createShader(bounds),
                          child: SingleChildScrollView(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: constraints.maxHeight,
                              ),
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                  24,
                                  _edgeFade,
                                  24,
                                  bottomPadding,
                                ),
                                // Logo en haut, formulaire en bas : l'espace
                                // restant va entre les deux. La colonne est
                                // remplie de bas en haut : le formulaire est
                                // peint en premier, son voile passe donc sous
                                // le logo.
                                child: Column(
                                  verticalDirection: VerticalDirection.up,
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    CustomPaint(
                                      painter: const _FormScrimPainter(),
                                      child: Center(
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 480,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              if (header != null) ...[
                                                header!,
                                                const SizedBox(height: 14),
                                              ],
                                              if (page case final page?)
                                                _PageSwitcher(
                                                  page: page,
                                                  child: _buildContent(),
                                                )
                                              else
                                                _buildContent(),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: EdgeInsets.only(
                                        bottom: isCompact ? 16 : 24,
                                      ),
                                      child: Center(
                                        child: Image.asset(
                                          'assets/images/brand/nowave_logo.png',
                                          width: isCompact ? 150 : 200,
                                          semanticLabel: 'NoWave',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.15,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: 16),
        child,
      ],
    );
  }
}

/// Fait glisser le contenu d'une page à l'autre, comme [FlowTransition] mais
/// dans le formulaire : la hauteur s'adapte en douceur à la nouvelle page.
class _PageSwitcher extends StatefulWidget {
  final int page;
  final Widget child;

  const _PageSwitcher({required this.page, required this.child});

  @override
  State<_PageSwitcher> createState() => _PageSwitcherState();
}

class _PageSwitcherState extends State<_PageSwitcher> {
  static const _duration = Duration(milliseconds: 300);

  bool _forward = true;

  @override
  void didUpdateWidget(_PageSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.page != oldWidget.page) {
      _forward = widget.page > oldWidget.page;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: _duration,
      curve: Curves.easeInOut,
      alignment: Alignment.bottomCenter,
      // Le contenu qui glisse sort du formulaire jusqu'au bord de l'écran.
      clipBehavior: Clip.none,
      child: AnimatedSwitcher(
        duration: _duration,
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: Alignment.bottomCenter,
          children: [...previousChildren, ?currentChild],
        ),
        transitionBuilder: (child, animation) => AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) {
            final offset = 1 - animation.value;
            final entering = animation.status != AnimationStatus.reverse;
            final direction = _forward ? 1.0 : -1.0;
            // Un peu plus que la largeur du formulaire : il sort entièrement
            // de l'écran malgré les marges.
            return FractionalTranslation(
              translation: Offset(
                (entering ? direction : -direction) * offset * 1.2,
                0,
              ),
              child: child,
            );
          },
        ),
        child: KeyedSubtree(key: ValueKey(widget.page), child: widget.child),
      ),
    );
  }
}

/// Voile sombre derrière le formulaire, sur toute la largeur de l'écran.
/// Il commence en fondu un peu au-dessus du titre et continue sous le
/// formulaire jusqu'au bas de l'écran.
class _FormScrimPainter extends CustomPainter {
  const _FormScrimPainter();

  /// Hauteur du fondu au-dessus du titre.
  static const _fade = 140.0;

  /// Teinte du voile sous le formulaire, reprise derrière le clavier.
  static final bottomColor = AppColors.slate900.withValues(alpha: 0.92);

  @override
  void paint(Canvas canvas, Size size) {
    // Déborde largement sur les côtés et en bas : la zone qui défile coupe
    // ce qui sort de l'écran.
    final rect = Rect.fromLTRB(
      -size.width,
      -_fade,
      size.width * 2,
      size.height + 400,
    );
    // Teinte finale atteinte au bas du formulaire, puis constante : même
    // teinte que le voile derrière le clavier, sans marche entre les deux.
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: [
          0,
          (_fade - 16) / rect.height,
          (_fade + 160) / rect.height,
          ((_fade + size.height) / rect.height).clamp(
            (_fade + 160) / rect.height,
            1.0,
          ),
        ],
        colors: [
          AppColors.slate900.withValues(alpha: 0),
          AppColors.slate900.withValues(alpha: 0.55),
          AppColors.slate900.withValues(alpha: 0.85),
          bottomColor,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(_FormScrimPainter oldDelegate) => false;
}
