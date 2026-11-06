import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/uploader/clip_group_caption_selector.dart';
import 'package:postdee_mobile/features/uploader/clip_group_draft.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';

final _now = DateTime.utc(2026, 11, 5);

PublishDraft _draft(String id,
        {String owner = 'seller', bool backup = false}) =>
    PublishDraft(
      version: publishDraftManifestVersion,
      id: id,
      ownerUserId: owner,
      submissionRequestId: 'request-$id',
      createdAt: _now,
      updatedAt: _now,
      videoPath: '/$id.mp4',
      videoName: '$id.mp4',
      videoSizeBytes: 10,
      caption: '',
      aiGuidance: '',
      watermarkEnabled: false,
      platformApiValues: const {'FACEBOOK_REELS'},
      clipGroupId: 'set',
      isClipGroupSource: backup,
    );

ClipGroupItem _item(String id, int index, double start, double end,
        {Set<String> platforms = const {'FACEBOOK_REELS'}}) =>
    ClipGroupItem(
      draftId: id,
      index: index,
      sourceStartSeconds: start,
      sourceEndSeconds: end,
      platformApiValues: platforms,
    );

ClipGroupDraft _group({List<ClipGroupItem>? items}) => ClipGroupDraft(
      id: 'set',
      ownerUserId: 'seller',
      sourceDraftId: 'backup',
      title: 'Seller video',
      sharedCaption: '',
      deliveryMode: ClipGroupDeliveryMode.immediate,
      createdAt: _now,
      updatedAt: _now,
      items: items ??
          [
            _item('second', 2, 90, 180),
            _item('full', 1, 0, 180, platforms: {'TIKTOK', 'YOUTUBE_SHORTS'}),
            _item('first', 0, 0, 90),
          ],
    );

Map<String, PublishDraft> _drafts(ClipGroupDraft group) => {
      'backup': _draft('backup', backup: true),
      for (final item in group.items) item.draftId: _draft(item.draftId),
    };

Widget _app(Widget body,
        {String language = 'th', bool dark = false, double scale = 1}) =>
    MaterialApp(
      locale: Locale(language),
      supportedLocales: PostDeeLocalizations.supportedLocales,
      localizationsDelegates: const [
        PostDeeLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: AppTheme.screenPadding, child: body),
        ),
      ),
    );

Finder _key(String key) => find.byKey(ValueKey(key));

void main() {
  test('full copy is distinct from backup and does not consume a part number',
      () {
    final group = _group();
    final scopes = clipGroupCaptionScopes(group, _drafts(group),
        sourceDurationSeconds: 180);
    expect(scopes.map((scope) => scope.draftId),
        [null, 'full', 'first', 'second']);
    expect(scopes.map((scope) => scope.index), [0, 0, 1, 2]);
    expect(scopes.map((scope) => scope.isFull), [false, true, false, false]);
    expect(scopes.first.platformApiValues,
        {'TIKTOK', 'YOUTUBE_SHORTS', 'FACEBOOK_REELS'});
    expect(scopes[1].platformApiValues, {'TIKTOK', 'YOUTUBE_SHORTS'});
    expect(scopes[2].durationSeconds, 90);
    expect(scopes.any((scope) => scope.draftId == 'backup'), isFalse);
  });

  test('custom ranges never infer full source length from the last endpoint',
      () {
    final group = _group(items: [_item('trimmed', 0, 0, 150)]);
    final scopes = clipGroupCaptionScopes(group, _drafts(group),
        sourceDurationSeconds: 180);
    expect(scopes.last.isFull, isFalse);
    expect(scopes.last.index, 1);
    expect(scopes.last.durationSeconds, 150);
    expect(clipGroupCaptionScopes(group, _drafts(group)).last.isFull, isFalse);
  });

  test('full classification requires an owned backup and valid measured length',
      () {
    final group = _group();
    for (final duration in [null, 0.0, double.nan, double.infinity]) {
      expect(
          clipGroupCaptionScopes(group, _drafts(group),
                  sourceDurationSeconds: duration)
              .where((scope) => scope.isFull),
          isEmpty);
    }
    for (final drafts in [
      _drafts(group)..remove('backup'),
      _drafts(group)..['backup'] = _draft('backup', owner: 'another'),
    ]) {
      expect(
          clipGroupCaptionScopes(group, drafts, sourceDurationSeconds: 180)
              .where((scope) => scope.isFull),
          isEmpty);
    }
    expect(
        clipGroupCaptionScopes(group, _drafts(group),
                sourceDurationSeconds: 180.0005)
            .singleWhere((scope) => scope.draftId == 'full')
            .isFull,
        isTrue);
  });

  test('unavailable, foreign and backup-tagged members are never choices', () {
    final group = _group();
    final drafts = _drafts(group)
      ..remove('second')
      ..['full'] = _draft('full', owner: 'another')
      ..['first'] = _draft('first', backup: true);
    final scopes =
        clipGroupCaptionScopes(group, drafts, sourceDurationSeconds: 180);
    expect(scopes.map((scope) => scope.draftId), [null]);
    expect(scopes.single.platformApiValues, isEmpty);
    expect(drafts['backup']!.isClipGroupSource, isTrue);
    expect(group.items, hasLength(3));
  });

  testWidgets(
      'compact choices select All or a member and show its destinations',
      (tester) async {
    final group = _group();
    final selected = <String?>[];
    await tester.pumpWidget(_app(
      ClipGroupCaptionSelector(
        group: group,
        draftsById: _drafts(group),
        selectedDraftId: 'full',
        sourceDurationSeconds: 180,
        onSelected: selected.add,
      ),
      language: 'en',
    ));
    await tester.pumpAndSettle();
    expect(_key('clip-group-caption-scopes'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(4));
    expect(find.text('Full clip'), findsOneWidget);
    expect(find.text('Part 1'), findsOneWidget);
    expect(find.text('Part 2'), findsOneWidget);
    expect(
        tester
            .widget<ChoiceChip>(_key('clip-group-caption-scope-full'))
            .selected,
        isTrue);
    final destinations =
        tester.widget<Text>(_key('clip-group-caption-scope-platforms')).data!;
    expect(destinations, 'TikTok · YouTube Shorts');
    expect(destinations, isNot(contains('Facebook')));
    await tester.tap(_key('clip-group-caption-scope-first'));
    await tester.tap(_key('clip-group-caption-scope-all'));
    expect(selected, ['first', null]);
  });

  testWidgets('more than four choices use a controlled accessible dropdown',
      (tester) async {
    final group = _group(items: [
      for (var i = 0; i < 5; i++) _item('part-$i', i, i * 10.0, (i + 1) * 10.0),
    ]);
    final selected = <String?>[];
    await tester.pumpWidget(_app(
        ClipGroupCaptionSelector(
          group: group,
          draftsById: _drafts(group),
          selectedDraftId: 'part-2',
          sourceDurationSeconds: 180,
          onSelected: selected.add,
        ),
        language: 'en'));
    await tester.pumpAndSettle();
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(DropdownButton<String>), findsOneWidget);
    expect(find.text('Part 3'), findsOneWidget);
    await tester.tap(_key('clip-group-caption-scope-picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Part 5').last);
    await tester.pumpAndSettle();
    expect(selected, ['part-4']);
    await tester.tap(_key('clip-group-caption-scope-picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All').last);
    await tester.pumpAndSettle();
    expect(selected, ['part-4', null]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stale selection falls back to All without changing input', (
    tester,
  ) async {
    final group = _group();
    final selected = <String?>[];
    await tester.pumpWidget(
      _app(
        ClipGroupCaptionSelector(
          group: group,
          draftsById: _drafts(group),
          selectedDraftId: 'missing-member',
          sourceDurationSeconds: 180,
          onSelected: selected.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<ChoiceChip>(_key('clip-group-caption-scope-all')).selected,
      isTrue,
    );
    expect(selected, isEmpty);
    expect(group.sharedCaption, isEmpty);
  });

  testWidgets('a disabled dropdown cannot change the caption target', (
    tester,
  ) async {
    final group = _group(
      items: [
        for (var i = 0; i < 5; i++)
          _item('part-$i', i, i * 10.0, (i + 1) * 10.0),
      ],
    );
    var selections = 0;
    await tester.pumpWidget(
      _app(
        ClipGroupCaptionSelector(
          group: group,
          draftsById: _drafts(group),
          selectedDraftId: null,
          sourceDurationSeconds: 180,
          enabled: false,
          onSelected: (_) => selections++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButton<String>>(
            _key('clip-group-caption-scope-picker'),
          )
          .onChanged,
      isNull,
    );
    await tester.tap(_key('clip-group-caption-scope-picker'));
    await tester.pumpAndSettle();
    expect(selections, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled scopes do not dispatch selection callbacks',
      (tester) async {
    final group = _group();
    var selections = 0;
    await tester.pumpWidget(_app(ClipGroupCaptionSelector(
      group: group,
      draftsById: _drafts(group),
      selectedDraftId: null,
      sourceDurationSeconds: 180,
      enabled: false,
      onSelected: (_) => selections++,
    )));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ChoiceChip>(_key('clip-group-caption-scope-full'))
            .onSelected,
        isNull);
    await tester.tap(_key('clip-group-caption-scope-full'));
    expect(selections, 0);
  });

  for (final language in ['th', 'en']) {
    for (final many in [false, true]) {
      testWidgets('320dp large text stays usable $language dropdown=$many',
          (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final group = many
            ? _group(items: [
                for (var i = 0; i < 5; i++)
                  _item('part-$i', i, i * 10.0, (i + 1) * 10.0),
              ])
            : _group();
        await tester.pumpWidget(_app(
          ClipGroupCaptionSelector(
            group: group,
            draftsById: _drafts(group),
            selectedDraftId: null,
            sourceDurationSeconds: 180,
            onSelected: (_) {},
          ),
          language: language,
          dark: true,
          scale: 2,
        ));
        await tester.pumpAndSettle();
        expect(find.text(language == 'th' ? 'ทั้งหมด' : 'All'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
