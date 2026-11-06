import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/fork_release_version.dart';

void main() {
  test('same-upstream fork rebuilds are updates', () {
    expect(isForkReleaseNewer('v2.3.10+10002', '2.3.10+10001'), isTrue);
    expect(isForkReleaseNewer('v2.3.10+10001', '2.3.10+10001'), isFalse);
    expect(isForkReleaseNewer('v2.3.10+10000', '2.3.10+10001'), isFalse);
  });

  test('upstream version takes priority over the build number', () {
    expect(isForkReleaseNewer('v2.3.11+253', '2.3.10+10001'), isTrue);
    expect(isForkReleaseNewer('v2.3.9+10002', '2.3.10+10001'), isFalse);
    expect(isForkReleaseNewer('v2.3.10+10001', '2.3.10'), isTrue);
  });
}
