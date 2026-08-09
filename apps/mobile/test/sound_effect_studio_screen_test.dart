import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai_editing/ai_edit_sound_effects.dart';
import 'package:postdee_mobile/features/ai_editing/sound_effect_studio_screen.dart';

void main() {
  testWidgets('shows the catalog with an accessible disabled preview button',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SoundEffectStudioScreen(durationSeconds: 12),
      ),
    );

    expect(
      find.byKey(const ValueKey('sound-effect-studio-screen')),
      findsOneWidget,
    );
    expect(find.text('ใส่เอฟเฟกต์เสียง'), findsOneWidget);
    expect(find.text('คลังเสียง PostDee'), findsOneWidget);

    const previewKey = ValueKey('sound-effect-preview-soft_pop');
    const addKey = ValueKey('sound-effect-add-soft_pop');
    final previewSemantics = tester.widget<Semantics>(
      find.byKey(previewKey),
    );
    final addSemantics = tester.widget<Semantics>(find.byKey(addKey));

    expect(previewSemantics.properties.label, 'ฟังเสียง ป๊อปนุ่ม');
    expect(previewSemantics.properties.enabled, isFalse);
    expect(previewSemantics.properties.onTap, isNull);
    expect(addSemantics.properties.label, 'เพิ่มเสียง ป๊อปนุ่ม ที่ 0.0 วินาที');
    expect(addSemantics.properties.enabled, isTrue);
    expect(addSemantics.properties.onTap, isNotNull);
    expect(tester.getSize(find.byKey(previewKey)).height,
        greaterThanOrEqualTo(44));
    expect(tester.getSize(find.byKey(addKey)).height, greaterThanOrEqualTo(44));

    await tester.scrollUntilVisible(
      find.text('ยังไม่ได้ใส่เอฟเฟกต์เสียง'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('ยังไม่ได้ใส่เอฟเฟกต์เสียง'), findsOneWidget);
  });

  testWidgets('adds a catalog sound at the selected timeline position',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SoundEffectStudioScreen(durationSeconds: 12),
      ),
    );

    final currentTime = find.byKey(
      const ValueKey('sound-effect-current-time'),
    );
    tester
        .widget<Slider>(
          find.descendant(of: currentTime, matching: find.byType(Slider)),
        )
        .onChanged!(3.2);
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('sound-effect-add-soft_pop')),
    );
    await tester.pump();

    final placement = find.byKey(
      const ValueKey('sound-effect-placement-0'),
    );
    await tester.scrollUntilVisible(
      placement,
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(placement, findsOneWidget);
    expect(find.text('เสียงที่ใส่แล้ว (1/8)'), findsOneWidget);
    expect(
      find.descendant(
          of: placement, matching: find.text('เริ่มที่ 3.2 วินาที')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: placement, matching: find.text('25%')),
      findsOneWidget,
    );

    final decrement = find.byKey(
      const ValueKey('sound-effect-time-decrement-0'),
    );
    final increment = find.byKey(
      const ValueKey('sound-effect-time-increment-0'),
    );
    expect(tester.getSize(decrement).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(increment).height, greaterThanOrEqualTo(44));
  });

  testWidgets('previews a sound only when a preview callback is supplied',
      (tester) async {
    AiEditSoundEffectDefinition? previewed;

    await tester.pumpWidget(
      MaterialApp(
        home: SoundEffectStudioScreen(
          durationSeconds: 12,
          onPreview: (soundEffect) async {
            previewed = soundEffect;
          },
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('sound-effect-preview-soft_pop')),
    );
    await tester.pump();

    expect(previewed?.id, 'soft_pop');
  });

  testWidgets('edits time and volume, then returns validated placements',
      (tester) async {
    Future<List<AiEditSoundEffectPlacement>?>? resultFuture;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const ValueKey('open-studio'),
                onPressed: () {
                  resultFuture = Navigator.of(context)
                      .push<List<AiEditSoundEffectPlacement>>(
                    MaterialPageRoute(
                      builder: (_) => const SoundEffectStudioScreen(
                        durationSeconds: 10,
                        initialPlacements: [
                          AiEditSoundEffectPlacement(
                            soundId: 'soft_pop',
                            startSeconds: 2,
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: const Text('เปิด'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-studio')));
    await tester.pumpAndSettle();

    final timeSlider = find.byKey(const ValueKey('sound-effect-time-0'));
    final volumeSlider = find.byKey(const ValueKey('sound-effect-volume-0'));
    await tester.scrollUntilVisible(
      timeSlider,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    tester
        .widget<Slider>(
          find.descendant(of: timeSlider, matching: find.byType(Slider)),
        )
        .onChanged!(4.5);
    tester
        .widget<Slider>(
          find.descendant(of: volumeSlider, matching: find.byType(Slider)),
        )
        .onChanged!(0.6);
    await tester.pump();

    expect(
      tester
          .widget<Semantics>(find.byKey(const ValueKey('sound-effect-time-0')))
          .properties
          .value,
      'เริ่มที่ 4.5 วินาที',
    );
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('sound-effect-volume-0')),
          )
          .properties
          .value,
      '60 เปอร์เซ็นต์',
    );

    await tester.tap(find.byKey(const ValueKey('sound-effect-finish')));
    await tester.pumpAndSettle();

    final result = await resultFuture;
    expect(result, hasLength(1));
    expect(result!.single.soundId, 'soft_pop');
    expect(result.single.startSeconds, closeTo(4.5, 0.001));
    expect(result.single.volume, closeTo(0.6, 0.001));
  });

  testWidgets('removes a placement and cancel returns no replacement list',
      (tester) async {
    Future<List<AiEditSoundEffectPlacement>?>? resultFuture;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const ValueKey('open-studio'),
                onPressed: () {
                  resultFuture = Navigator.of(context)
                      .push<List<AiEditSoundEffectPlacement>>(
                    MaterialPageRoute(
                      builder: (_) => const SoundEffectStudioScreen(
                        durationSeconds: 10,
                        initialPlacements: [
                          AiEditSoundEffectPlacement(
                            soundId: 'clean_tap',
                            startSeconds: 1,
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: const Text('เปิด'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-studio')));
    await tester.pumpAndSettle();

    final remove = find.byKey(const ValueKey('sound-effect-remove-0'));
    await tester.scrollUntilVisible(
      remove,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester.widget<Semantics>(remove).properties.label,
      'ลบเสียง แตะเบา',
    );
    tester.widget<Semantics>(remove).properties.onTap!.call();
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('ยังไม่ได้ใส่เอฟเฟกต์เสียง'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('ยังไม่ได้ใส่เอฟเฟกต์เสียง'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sound-effect-cancel')));
    await tester.pumpAndSettle();

    expect(await resultFuture, isNull);
  });

  testWidgets('accepts a valid initial placement very close to the clip end',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SoundEffectStudioScreen(
          durationSeconds: 10,
          initialPlacements: [
            AiEditSoundEffectPlacement(
              soundId: 'soft_pop',
              startSeconds: 9.999,
            ),
          ],
        ),
      ),
    );

    final timeControl = find.byKey(
      const ValueKey('sound-effect-time-0'),
    );
    await tester.scrollUntilVisible(
      timeControl,
      400,
      scrollable: find.byType(Scrollable).first,
    );

    expect(tester.takeException(), isNull);
    final slider = tester.widget<Slider>(
      find.descendant(of: timeControl, matching: find.byType(Slider)),
    );
    expect(slider.value, closeTo(9.999, 0.0001));
    expect(slider.max, 10);
  });

  testWidgets('warns at eight placements and prevents adding another sound',
      (tester) async {
    final initialPlacements = List<AiEditSoundEffectPlacement>.generate(
      maxAiEditSoundEffectsPerVideo,
      (index) => AiEditSoundEffectPlacement(
        soundId: postDeeSoundEffectCatalog[index].id,
        startSeconds: index.toDouble(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SoundEffectStudioScreen(
          durationSeconds: 10,
          initialPlacements: initialPlacements,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('sound-effect-limit-warning')),
      findsOneWidget,
    );
    expect(
      find.text('ใส่เอฟเฟกต์เสียงได้ไม่เกิน 8 จุดต่อคลิป'),
      findsOneWidget,
    );

    final add = tester.widget<Semantics>(
      find.byKey(const ValueKey('sound-effect-add-soft_pop')),
    );
    expect(add.properties.enabled, isFalse);
    expect(add.properties.onTap, isNull);
  });
}
