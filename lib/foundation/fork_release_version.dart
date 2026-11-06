/// Fork rebuilds keep the upstream marketing version and increase the iOS
/// build number. Compare both, so a gesture fix on the same upstream version
/// still appears in manual and startup update checks.
bool isForkReleaseNewer(String remote, String installed) {
  List<int> parts(String value) {
    value = value.replaceFirst(RegExp(r'^[vV]'), '');
    final split = value.split('+');
    final version = split.first.split('-').first.split('.');
    return [
      for (var i = 0; i < 3; i++)
        i < version.length ? int.tryParse(version[i]) ?? 0 : 0,
      split.length > 1 ? int.tryParse(split[1]) ?? 0 : 0,
    ];
  }

  final a = parts(remote), b = parts(installed);
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}
