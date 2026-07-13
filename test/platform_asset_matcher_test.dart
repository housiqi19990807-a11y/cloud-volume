// Asset matching prioritizes the running architecture over universal builds.
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/services/app_update_service.dart';
import 'package:remote_storage/services/platform_asset_matcher.dart';

ReleaseAsset _asset(String name, {int size = 1000}) => ReleaseAsset(
  name: name,
  downloadUrl: 'https://github.com/x/$name',
  size: size,
);
void main() {
  test('macOS arm64 prefers arm64 DMG over universal', () {
    final assets = [
      _asset('yunjuan-macos-universal.dmg'),
      _asset('yunjuan-macos-universal.zip'),
      _asset('yunjuan-macos-arm64.dmg'),
      _asset('yunjuan-macos-arm64.zip'),
      _asset('yunjuan-macos-amd64.dmg'),
    ];
    final match = matchPlatformAsset(
      assets,
      runtimeArchitecture: 'arm64',
      runtimePlatform: 'macos',
    );
    expect(match, isNotNull);
    expect(match!.asset.name, 'yunjuan-macos-arm64.dmg');
    expect(match.installerType, 'dmg');
  });
  test('macOS amd64 prefers amd64 DMG over universal', () {
    final assets = [
      _asset('yunjuan-macos-universal.dmg'),
      _asset('yunjuan-macos-amd64.dmg'),
      _asset('yunjuan-macos-arm64.dmg'),
    ];
    final match = matchPlatformAsset(
      assets,
      runtimeArchitecture: 'amd64',
      runtimePlatform: 'macos',
    );
    expect(match, isNotNull);
    expect(match!.asset.name, 'yunjuan-macos-amd64.dmg');
  });
  test('macOS falls back to universal when arch-specific absent', () {
    final assets = [
      _asset('yunjuan-macos-universal.dmg'),
      _asset('yunjuan-macos-amd64.dmg'),
    ];
    final match = matchPlatformAsset(
      assets,
      runtimeArchitecture: 'arm64',
      runtimePlatform: 'macos',
    );
    expect(match, isNotNull);
    expect(match!.asset.name, 'yunjuan-macos-universal.dmg');
  });
  test('macOS with unknown arch tries universal then all arches', () {
    final assets = [_asset('yunjuan-macos-amd64.dmg')];
    final match = matchPlatformAsset(
      assets,
      runtimeArchitecture: '',
      runtimePlatform: 'macos',
    );
    expect(match, isNotNull);
    expect(match!.asset.name, 'yunjuan-macos-amd64.dmg');
  });

  test('Windows arm64 prefers native package over amd64 fallback', () {
    final assets = [
      _asset('yunjuan-windows-amd64.zip'),
      _asset('yunjuan-windows-arm64-installer.exe'),
    ];
    final match = matchPlatformAsset(
      assets,
      runtimeArchitecture: 'arm64',
      runtimePlatform: 'windows',
    );
    expect(match, isNotNull);
    expect(match!.asset.name, 'yunjuan-windows-arm64-installer.exe');
    expect(match.installerType, 'exe');
  });

  test('Windows arm64 falls back to amd64 package', () {
    final match = matchPlatformAsset(
      [_asset('yunjuan-windows-amd64.zip')],
      runtimeArchitecture: 'arm64',
      runtimePlatform: 'windows',
    );
    expect(match, isNotNull);
    expect(match!.asset.name, 'yunjuan-windows-amd64.zip');
  });
}
