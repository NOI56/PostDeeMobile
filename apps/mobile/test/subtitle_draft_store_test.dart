import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_draft_store.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_project.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory =
        await Directory.systemTemp.createTemp('subtitle-draft-store-');
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  test('saves and loads one versioned project', () async {
    final store = FileSubtitleDraftStore(rootDirectory: tempDirectory);
    final project = validProject();

    await store.saveDraft(project);

    expect(
      (await store.loadDraft(project.projectId))?.toJson(),
      project.toJson(),
    );
  });

  test('returns null for a corrupt draft without deleting it', () async {
    final store = FileSubtitleDraftStore(rootDirectory: tempDirectory);
    final file = store.fileForProject('project-1');
    await file.parent.create(recursive: true);
    await file.writeAsString('{broken');

    expect(await store.loadDraft('project-1'), isNull);
    expect(await file.exists(), isTrue);
  });

  test(
      'returns null for a draft with an unsupported schema without deleting it',
      () async {
    final store = FileSubtitleDraftStore(rootDirectory: tempDirectory);
    final file = store.fileForProject('project-1');
    final json = validProject().toJson()..['schemaVersion'] = 99;
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(json));

    expect(await store.loadDraft('project-1'), isNull);
    expect(await file.exists(), isTrue);
  });

  test('uses an encoded filename for unsafe project ids', () {
    final store = FileSubtitleDraftStore(rootDirectory: tempDirectory);
    final file = store.fileForProject('../other');

    expect(file.parent.path, tempDirectory.path);
    expect(file.path, isNot(contains('..')));
  });

  test('keeps case-colliding project ids in separate draft files', () async {
    final store = FileSubtitleDraftStore(rootDirectory: tempDirectory);
    const firstId = '  @';
    const secondId = '  Z';
    final firstFile = store.fileForProject(firstId);
    final secondFile = store.fileForProject(secondId);
    final firstProject = projectWithId(firstId);
    final secondProject = projectWithId(secondId).copyWith(revision: 1);

    expect(firstFile.path.toLowerCase(), isNot(secondFile.path.toLowerCase()));

    await store.saveDraft(firstProject);
    await store.saveDraft(secondProject);

    expect((await store.loadDraft(firstId))?.toJson(), firstProject.toJson());
    expect((await store.loadDraft(secondId))?.toJson(), secondProject.toJson());

    await store.deleteDraft(firstId);

    expect(await store.loadDraft(firstId), isNull);
    expect((await store.loadDraft(secondId))?.toJson(), secondProject.toJson());
  });

  test('bounds project ids by UTF-8 bytes before writing draft files',
      () async {
    final store = FileSubtitleDraftStore(rootDirectory: tempDirectory);
    final supportedId = List.filled(30, 'ก').join();
    final rejectedId = '$supportedIdก';
    final supportedProject = projectWithId(supportedId);

    await store.saveDraft(supportedProject);
    final entriesBefore = (await tempDirectory.list().toList())
        .map((entry) => entry.path)
        .toSet();

    expect((await store.loadDraft(supportedId))?.toJson(),
        supportedProject.toJson());
    expect(
      () => store.fileForProject(rejectedId),
      throwsA(isA<SubtitleProjectValidationException>()),
    );
    await expectLater(
      store.saveDraft(projectWithId(rejectedId)),
      throwsA(isA<SubtitleProjectValidationException>()),
    );

    expect(
      (await tempDirectory.list().toList()).map((entry) => entry.path).toSet(),
      entriesBefore,
    );
  });

  test('delete removes only the requested project draft and its siblings',
      () async {
    final store = FileSubtitleDraftStore(rootDirectory: tempDirectory);
    await store.saveDraft(projectWithId('one'));
    await store.saveDraft(projectWithId('two'));
    final one = store.fileForProject('one');
    await File('${one.path}.next').writeAsString('interrupted write');
    await File('${one.path}.backup').writeAsString('previous draft');

    await store.deleteDraft('one');

    expect(await store.loadDraft('one'), isNull);
    expect(await File('${one.path}.next').exists(), isFalse);
    expect(await File('${one.path}.backup').exists(), isFalse);
    expect(await store.loadDraft('two'), isNotNull);
  });

  test('replaces a saved draft without leaving atomic-operation siblings',
      () async {
    final store = FileSubtitleDraftStore(rootDirectory: tempDirectory);
    final original = projectWithId('project-1');
    final updated = original.copyWith(revision: 1);

    await store.saveDraft(original);
    await store.saveDraft(updated);

    final file = store.fileForProject(updated.projectId);
    expect(
        (await store.loadDraft(updated.projectId))?.toJson(), updated.toJson());
    expect(await File('${file.path}.next').exists(), isFalse);
    expect(await File('${file.path}.backup').exists(), isFalse);
  });

  test('recovers the newest valid next draft when target is absent', () async {
    final store = FileSubtitleDraftStore(rootDirectory: tempDirectory);
    final target = store.fileForProject('project-1');
    final next = File('${target.path}.next');
    final backup = File('${target.path}.backup');
    await next.writeAsString(
        jsonEncode(validProject().copyWith(revision: 2).toJson()));
    await backup.writeAsString(
        jsonEncode(validProject().copyWith(revision: 1).toJson()));

    final recovered = await store.loadDraft('project-1');

    expect(recovered?.revision, 2);
    expect(await target.exists(), isTrue);
    expect(await next.exists(), isFalse);
    expect(await backup.exists(), isFalse);
  });

  test('recovers a valid backup when target is absent and next is invalid',
      () async {
    final store = FileSubtitleDraftStore(rootDirectory: tempDirectory);
    final target = store.fileForProject('project-1');
    final next = File('${target.path}.next');
    final backup = File('${target.path}.backup');
    await next.writeAsString('{broken');
    await backup.writeAsString(jsonEncode(validProject().toJson()));

    final recovered = await store.loadDraft('project-1');

    expect(recovered?.toJson(), validProject().toJson());
    expect(await target.exists(), isTrue);
    expect(await backup.exists(), isFalse);
  });

  test('does not recover malformed or cross-project remnants', () async {
    final store = FileSubtitleDraftStore(rootDirectory: tempDirectory);
    final target = store.fileForProject('project-1');
    final next = File('${target.path}.next');
    final backup = File('${target.path}.backup');
    await next.writeAsString('{broken');
    await backup.writeAsString(jsonEncode(projectWithId('other').toJson()));

    expect(await store.loadDraft('project-1'), isNull);
    expect(await target.exists(), isFalse);
    expect(await next.exists(), isTrue);
    expect(await backup.exists(), isTrue);
  });

  test('does not replace a corrupt existing target while loading remnants',
      () async {
    final store = FileSubtitleDraftStore(rootDirectory: tempDirectory);
    final target = store.fileForProject('project-1');
    final next = File('${target.path}.next');
    final backup = File('${target.path}.backup');
    await target.writeAsString('{broken');
    await next.writeAsString(
        jsonEncode(validProject().copyWith(revision: 2).toJson()));
    await backup.writeAsString(jsonEncode(validProject().toJson()));

    expect(await store.loadDraft('project-1'), isNull);
    expect(await target.readAsString(), '{broken');
    expect(await next.exists(), isTrue);
    expect(await backup.exists(), isTrue);
  });

  test('serializes concurrent saves for the same project in call order',
      () async {
    final firstReachedPromotion = Completer<void>();
    final releaseFirstSave = Completer<void>();
    var startedOperations = 0;
    final store = FileSubtitleDraftStore(
      rootDirectory: tempDirectory,
      onOperationStart: () => startedOperations += 1,
      beforePromotion: () async {
        if (!firstReachedPromotion.isCompleted) {
          firstReachedPromotion.complete();
          await releaseFirstSave.future;
        }
      },
    );
    final first = validProject();
    final second = first.copyWith(revision: 1);

    final firstSave = store.saveDraft(first);
    await firstReachedPromotion.future;
    final secondSave = store.saveDraft(second);
    await Future<void>.delayed(Duration.zero);

    expect(startedOperations, 1);

    releaseFirstSave.complete();
    await firstSave;
    await secondSave;

    final target = store.fileForProject(first.projectId);
    expect((await store.loadDraft(first.projectId))?.revision, 1);
    expect(await File('${target.path}.next').exists(), isFalse);
    expect(await File('${target.path}.backup').exists(), isFalse);
  });
}

SubtitleProject validProject() => projectWithId('project-1');

SubtitleProject projectWithId(String projectId) => SubtitleProject(
      schemaVersion: 1,
      projectId: projectId,
      sourceFingerprint: 'source-1',
      sourceDurationMs: 5000,
      language: 'th',
      cues: [
        SubtitleCue(
          cueId: 'cue-1',
          sourceStartMs: 100,
          sourceEndMs: 1200,
          text: 'สวัสดีค่ะ',
          timingMode: SubtitleTimingMode.segment,
        ),
      ],
      defaultStyle: SubtitleStyle.defaults,
      cutRanges: const [],
      revision: 0,
      createdAt: DateTime.utc(2026, 7, 20),
      updatedAt: DateTime.utc(2026, 7, 20),
    );
