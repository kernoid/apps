// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:kernoid/app/format.dart';
import 'package:kernoid/pages/compose.dart';
import 'package:kernoid/widgets/e2e.dart';
import 'package:kernoid/src/rust/api/kernoid.dart';

void main() {
  test('people are named by name, else by address', () {
    expect(person(const Address(name: 'Alice', email: 'a@x.example')), 'Alice');
    expect(person(const Address(name: '  ', email: 'b@x.example')), 'b@x.example');
    expect(people(const [Address(email: 'a@x'), Address(name: 'Bob', email: 'b@x')]), 'a@x, Bob');
  });

  test('sizes are short', () {
    expect(bytes(512), '512 B');
    expect(bytes(1500), '1.5 KB');
    expect(bytes(25000000), '25 MB');
  });

  test('a message date is RFC 5322 in English with the zone', () {
    final at = DateTime(2026, 10, 30, 17, 5, 9);
    expect(rfc5322Date(at), matches(RegExp(r'^Fri, 30 Oct 2026 17:05:09 [+-]\d{4}$')));
  });

  test('fingerprints are grouped by four', () {
    expect(groupedFingerprint('abcd1234ef'), 'ABCD 1234 EF');
  });
}
