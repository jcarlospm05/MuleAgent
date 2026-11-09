import 'package:mule_profiles/mule_profiles.dart';
import 'package:test/test.dart';

class MemoryProfileStorage implements ProfileStorage {
  String? value;
  bool fail = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    if (fail) throw StateError('storage unavailable');
    this.value = value;
  }
}

void main() {
  late MemoryProfileStorage storage;
  late ProfileRepository profiles;
  setUp(() {
    storage = MemoryProfileStorage();
    profiles = ProfileRepository(storage);
  });
  test('unconfigured installation cannot receive', () async {
    expect(await profiles.load(), isNull);
    await expectLater(profiles.requireAdministrator(), throwsStateError);
  });
  test(
    'Supervisor remains Supervisor after restart and cannot reconfigure or elevate',
    () async {
      await profiles.configure(AppRole.supervisor);
      final restarted = ProfileRepository(storage);
      expect((await restarted.load())!.activeRole, AppRole.supervisor);
      expect((await restarted.load())!.canSwitchRoles, isFalse);
      await expectLater(
        restarted.switchTo(AppRole.administrator),
        throwsStateError,
      );
      await expectLater(
        restarted.configure(AppRole.administrator),
        throwsStateError,
      );
      await expectLater(restarted.requireAdministrator(), throwsStateError);
    },
  );
  test(
    'Administrator can switch both ways while installation capability persists',
    () async {
      await profiles.configure(AppRole.administrator);
      await profiles.requireAdministrator();
      await profiles.switchTo(AppRole.supervisor);
      final restarted = ProfileRepository(storage);
      expect((await restarted.load())!.canSwitchRoles, isTrue);
      await expectLater(restarted.requireAdministrator(), throwsStateError);
      await restarted.switchTo(AppRole.administrator);
      await restarted.requireAdministrator();
    },
  );
  test(
    'damaged or unsupported saved profiles fail closed, never reset privileges',
    () async {
      for (final raw in [
        '{}',
        'not-json',
        '{"version":2,"installed_as":"administrator","active_role":"administrator"}',
        '{"version":1,"installed_as":"supervisor","active_role":"administrator"}',
      ]) {
        storage.value = raw;
        await expectLater(profiles.load(), throwsFormatException);
        await expectLater(
          profiles.configure(AppRole.administrator),
          throwsStateError,
        );
        expect(storage.value, raw);
      }
    },
  );
  test('failed write preserves previous active role', () async {
    await profiles.configure(AppRole.administrator);
    storage.fail = true;
    await expectLater(profiles.switchTo(AppRole.supervisor), throwsStateError);
    expect((await profiles.load())!.activeRole, AppRole.administrator);
  });
  test('concurrent initial choices cannot overwrite each other', () async {
    final outcomes = await Future.wait([
      profiles
          .configure(AppRole.supervisor)
          .then((_) => true, onError: (Object _) => false),
      profiles
          .configure(AppRole.administrator)
          .then((_) => true, onError: (Object _) => false),
    ]);
    expect(outcomes.where((success) => success), hasLength(1));
    expect((await profiles.load())!.installedAs, AppRole.supervisor);
  });
}
