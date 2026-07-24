// Unit tests for config-backup decryption error detection.
// Keeps the retry-loop gate honest: only actual decryption failures should
// trigger the password prompt; network/parse failures must not.

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/utils/bridge_error_text.dart';

void main() {
  group('isConfigBackupDecryptionError', () {
    test('matches Go "无法解密配置备份" wrapper', () {
      expect(
        isConfigBackupDecryptionError(
          Exception('无法解密配置备份：cipher: message authentication failed'),
        ),
        isTrue,
      );
    });

    test('matches Go "此备份已加密" missing-password error', () {
      expect(
        isConfigBackupDecryptionError(Exception('此备份已加密，请先设置加密密码')),
        isTrue,
      );
    });

    test('matches bridge-prefixed message authentication failure', () {
      expect(
        isConfigBackupDecryptionError(
          'RemoteStorageBridgeException: 无法解密配置备份：cipher: message authentication failed',
        ),
        isTrue,
      );
    });

    test('does not match generic "加密" text in unrelated errors', () {
      expect(
        isConfigBackupDecryptionError(Exception('已加密保存到指定存储')),
        isFalse,
      );
      expect(
        isConfigBackupDecryptionError(Exception('备份已加密上传完成')),
        isFalse,
      );
    });

    test('does not match network errors containing decrypt/cipher substrings',
        () {
      expect(
        isConfigBackupDecryptionError(
          Exception('connection refused while reading cipher config'),
        ),
        isFalse,
      );
      expect(
        isConfigBackupDecryptionError(
          Exception('tls handshake timeout: decrypt certificate'),
        ),
        isFalse,
      );
    });

    test('does not match empty or unrelated errors', () {
      expect(isConfigBackupDecryptionError(Exception('')), isFalse);
      expect(isConfigBackupDecryptionError(Exception('NoSuchBucket')), isFalse);
      expect(isConfigBackupDecryptionError(Exception('AccessDenied')), isFalse);
    });
  });
}

