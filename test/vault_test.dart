import 'package:flutter_test/flutter_test.dart';
import 'package:wave/models.dart';
import 'package:wave/services/vault.dart';
import 'package:wave/storage.dart';

import 'helpers.dart';

void main() {
  setUp(setupTestEnv);

  test('vault encrypts and round-trips entries', () async {
    final vault = VaultService();
    await vault.restore();
    await vault.ensureKey();
    await vault.upsert(VaultEntry(
        id: 'e1', origin: 'https://a.dev', username: 'u', password: 'p'));
    expect(vault.entries.single.password, 'p');

    // Persisted blob must not contain the plaintext.
    final sealed = Storage.read(Storage.vault, 'entries')!;
    expect(sealed.contains('https://a.dev'), isFalse);
    expect(sealed.contains('s3cret') || sealed.contains('"p"'), isFalse);

    // A fresh instance decrypts back.
    final vault2 = VaultService();
    await vault2.restore();
    expect(vault2.entries.single.username, 'u');
  });

  test('master password locks and unlocks', () async {
    final vault = VaultService();
    await vault.restore();
    await vault.ensureKey();
    await vault.upsert(VaultEntry(
        id: 'e1', origin: 'https://a.dev', username: 'u', password: 'p'));
    await vault.setMasterPassword('hunter2');
    vault.lock();
    expect(vault.locked, isTrue);
    expect(vault.entries, isEmpty);

    final wrong = await vault.unlock('wrong');
    expect(wrong, isFalse);
    expect(vault.locked, isTrue);

    final right = await vault.unlock('hunter2');
    expect(right, isTrue);
    expect(vault.entries.single.password, 'p');
  });

  test('forOrigin matches host', () async {
    final vault = VaultService();
    await vault.restore();
    await vault.ensureKey();
    await vault.upsert(VaultEntry(
        id: 'e1',
        origin: 'https://github.com',
        username: 'a',
        password: 'x'));
    expect(vault.forOrigin('https://github.com/login'), isNotEmpty);
    expect(vault.forOrigin('https://other.dev'), isEmpty);
  });

  test('remove entry', () async {
    final vault = VaultService();
    await vault.restore();
    await vault.ensureKey();
    await vault.upsert(VaultEntry(
        id: 'e1', origin: 'https://a.dev', username: 'u', password: 'p'));
    await vault.remove('e1');
    expect(vault.entries, isEmpty);
  });

  test('generatePassword hits all classes', () {
    final p = VaultService.generatePassword();
    expect(p.length, 18);
    expect(p.contains(RegExp(r'[A-Z]')), isTrue);
    expect(p.contains(RegExp(r'[a-z]')), isTrue);
    expect(p.contains(RegExp(r'[0-9]')), isTrue);
    expect(p.contains(RegExp(r'[!@#%^&*()_+=-]')), isTrue);
  });

  test('unlockWithAccount requires no master password', () async {
    final vault = VaultService();
    await vault.restore();
    expect(await vault.unlockWithAccount(), isTrue);
    await vault.setMasterPassword('pw');
    final vault2 = VaultService();
    await vault2.restore();
    expect(vault2.hasMasterPassword, isTrue);
    expect(await vault2.unlockWithAccount(), isFalse);
  });
}
