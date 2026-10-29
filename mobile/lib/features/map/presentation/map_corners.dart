import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'widgets/map_action_rail.dart';

/// Coins libres de part et d'autre de la barre d'actions : le « i » de Mapbox
/// à gauche, la règle à droite, chacun centré dans son coin et sur l'axe de
/// la barre. Le logo se pose juste au-dessus du « i ».
abstract final class MapCorners {
  /// Marge de Flutter sous un bouton flottant, en plus de la zone sûre.
  static const _floatingMargin = 16.0;

  /// Tailles natives de Mapbox (SDK iOS et Android 11.30).
  static const _logoWidth = 85.0;
  static const _logoGap = 6.0;

  /// iOS : bouton de 44 pt, icône de 22 pt calée en bas et centrée.
  static const _iosButton = 44.0;
  static const _iosIcon = 22.0;

  /// Android : l'icône remplit la vue de 21 dp.
  static const _androidIcon = 21.0;

  /// Distance entre le bas de l'écran et l'axe de la barre d'actions.
  static double railAxis(double viewPaddingBottom) =>
      viewPaddingBottom + _floatingMargin + MapActionRail.height / 2;

  /// Largeur d'un coin, entre le bord de l'écran et la barre.
  static double cornerWidth(double screenWidth, int actions) =>
      (screenWidth - MapActionRail.widthFor(actions)) / 2;

  /// Marges du logo et du « i » en bas à gauche. Sur iOS, Mapbox les compte
  /// depuis la zone sûre ; sur Android, depuis le bord de la carte.
  static ({LogoSettings logo, AttributionSettings attribution}) ornaments({
    required double screenWidth,
    required double viewPaddingBottom,
    required int actions,
    required bool ios,
  }) {
    final center = cornerWidth(screenWidth, actions) / 2;
    final axis = railAxis(viewPaddingBottom) - (ios ? viewPaddingBottom : 0);
    final icon = ios ? _iosIcon : _androidIcon;
    final box = ios ? _iosButton : _androidIcon;
    final iconBottom = axis - icon / 2;
    return (
      logo: LogoSettings(
        position: OrnamentPosition.BOTTOM_LEFT,
        marginLeft: (center - _logoWidth / 2).clamp(4, double.infinity),
        marginBottom: iconBottom + icon + _logoGap,
      ),
      attribution: AttributionSettings(
        position: OrnamentPosition.BOTTOM_LEFT,
        marginLeft: center - box / 2,
        marginBottom: iconBottom,
        iconColor: 0x99FFFFFF,
      ),
    );
  }
}
