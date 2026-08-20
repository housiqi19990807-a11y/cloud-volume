package com.example.remote_storage

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.sharedpreferences.SharedPreferencesPlugin
import dev.fluttercommunity.plus.device_info.DeviceInfoPlusPlugin
import com.mr.flutter.plugin.filepicker.FilePickerPlugin
import io.flutter.plugins.flutter_plugin_android_lifecycle.FlutterAndroidLifecyclePlugin
import com.github.dart_lang.jni.JniPlugin
import com.github.dart_lang.jni_flutter.JniFlutterPlugin
import io.flutter.plugins.urllauncher.UrlLauncherPlugin

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // UI preview does not use desktop window/native drag plugins. Register only
        // Android-safe plugins so one failing desktop native library cannot prevent
        // the shared Flutter UI from starting.
        flutterEngine.plugins.add(DeviceInfoPlusPlugin())
        flutterEngine.plugins.add(FilePickerPlugin())
        flutterEngine.plugins.add(FlutterAndroidLifecyclePlugin())
        flutterEngine.plugins.add(JniPlugin())
        flutterEngine.plugins.add(JniFlutterPlugin())
        flutterEngine.plugins.add(SharedPreferencesPlugin())
        flutterEngine.plugins.add(UrlLauncherPlugin())
    }
}
