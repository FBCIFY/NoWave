import 'package:blueway/features/map/presentation/map_intro_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'sans carte pour préparer l’arrivée, l’onboarding s’efface tout de suite',
    () {
      final intro = MapIntroController();
      addTearDown(intro.dispose);
      var notifications = 0;
      intro.addListener(() => notifications++);

      expect(intro.covered, isTrue);
      intro.start();
      expect(intro.phase, MapIntroPhase.revealed);
      expect(intro.covered, isFalse);
      expect(notifications, 1);
    },
  );

  test('avec une carte : l’onboarding reste jusqu’à son signal', () {
    final intro = MapIntroController()..attach();
    addTearDown(intro.dispose);
    var notifications = 0;
    intro.addListener(() => notifications++);

    intro.start();
    expect(intro.phase, MapIntroPhase.starting);
    expect(intro.covered, isTrue);

    intro.reveal();
    expect(intro.phase, MapIntroPhase.revealed);
    expect(intro.covered, isFalse);

    // Un second appui ou un second signal ne relance rien.
    intro
      ..start()
      ..reveal();
    expect(notifications, 2);
  });

  test('une carte partie avant la fin laisse l’onboarding s’effacer', () {
    final intro = MapIntroController()
      ..attach()
      ..detach();
    addTearDown(intro.dispose);

    intro.start();
    expect(intro.phase, MapIntroPhase.revealed);
  });
}
