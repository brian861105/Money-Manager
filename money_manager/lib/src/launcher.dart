import 'launcher_stub.dart'
    if (dart.library.html) 'launcher_web.dart'
    as platform;

abstract class UrlLauncher {
  void open(String url);
}

UrlLauncher createUrlLauncher() => platform.createUrlLauncher();
