import 'package:cat_library_demo/core/sync/identity_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IdentityGuard.check', () {
    test('a first installation with no identity history may create an owner', () {
      expect(IdentityGuard.check(null), isNull);
    });

    test('an existing active owner is accepted before any cache is written', () {
      expect(IdentityGuard.check('member-a'), 'member-a');
    });

    test('a restored session keeps the remembered owner', () {
      expect(
        IdentityGuard.check('member-a', rememberedOwner: 'member-a'),
        'member-a',
      );
    });

    test('an expired session cannot create a replacement for a remembered owner',
        () {
      expect(
        () => IdentityGuard.check(null, rememberedOwner: 'member-a'),
        throwsStateError,
      );
    });

    test('cached assets prevent anonymous identity creation without preferences',
        () {
      expect(
        () => IdentityGuard.check(null, cachedOwners: ['member-a']),
        throwsStateError,
      );
    });

    test('multiple cached owners still prevent anonymous identity creation', () {
      expect(
        () => IdentityGuard.check(
          null,
          cachedOwners: ['member-a', 'member-b'],
        ),
        throwsStateError,
      );
    });

    test('a retry cannot silently switch away from the remembered owner', () {
      expect(
        () => IdentityGuard.check('member-b', rememberedOwner: 'member-a'),
        throwsStateError,
      );
    });

    test('a cached second account does not override the remembered owner', () {
      expect(
        () => IdentityGuard.check(
          'member-b',
          rememberedOwner: 'member-a',
          cachedOwners: ['member-a', 'member-b'],
        ),
        throwsStateError,
      );
    });

    test('an active owner may recover from its single cache without preferences',
        () {
      expect(
        IdentityGuard.check('member-a', cachedOwners: ['member-a']),
        'member-a',
      );
    });

    test('an active owner may recover from multiple caches without preferences',
        () {
      expect(
        IdentityGuard.check(
          'member-b',
          cachedOwners: ['member-a', 'member-b'],
        ),
        'member-b',
      );
    });

    test('an unfamiliar active owner cannot claim assets from another cache', () {
      expect(
        () => IdentityGuard.check(
          'member-c',
          cachedOwners: ['member-a', 'member-b'],
        ),
        throwsStateError,
      );
    });

    test('checking recovery preserves every cached owner', () {
      final cachedOwners = ['member-a', 'member-b'];

      final recoveredOwner = IdentityGuard.check(
        'member-b',
        cachedOwners: cachedOwners,
      );

      expect(recoveredOwner, 'member-b');
      expect(cachedOwners, ['member-a', 'member-b']);
      expect(
        IdentityGuard.check('member-a', cachedOwners: cachedOwners),
        'member-a',
      );
    });
  });
}
