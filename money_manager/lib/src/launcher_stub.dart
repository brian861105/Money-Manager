import 'launcher.dart';

UrlLauncher createUrlLauncher() => const NoopUrlLauncher();

class NoopUrlLauncher implements UrlLauncher {
  const NoopUrlLauncher();

  @override
  void open(String url) {}
}
