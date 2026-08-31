package com.pluseight8.fedorashell.bridge;

import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.media.AudioManager;
import android.os.BatteryManager;
import android.os.Binder;
import android.os.Build;
import android.os.Bundle;
import android.os.IBinder;
import android.os.VibrationEffect;
import android.os.Vibrator;

import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

/**
 * In-process Android API surface for future UI adapters. It is not exported,
 * does not open a socket, and deliberately does not pretend to be a Linux
 * hardware device. Termux:API remains the current Linux-side transport.
 */
public class AndroidBridgeService extends Service {
    private final IBinder binder = new LocalBinder();

    public final class LocalBinder extends Binder {
        public AndroidBridgeService getService() {
            return AndroidBridgeService.this;
        }
    }

    public static final class BatterySnapshot {
        public final int percentage;
        public final int status;
        public final int temperatureTenthsC;

        public BatterySnapshot(int percentage, int status, int temperatureTenthsC) {
            this.percentage = percentage;
            this.status = status;
            this.temperatureTenthsC = temperatureTenthsC;
        }
    }

    private static final Map<String, String> APP_PACKAGES;

    static {
        Map<String, String> apps = new HashMap<>();
        apps.put("samsung-notes", "com.samsung.android.app.notes");
        apps.put("gallery", "com.sec.android.gallery3d");
        apps.put("camera", "com.sec.android.app.camera");
        apps.put("chrome", "com.android.chrome");
        apps.put("youtube", "com.google.android.youtube");
        apps.put("play-store", "com.android.vending");
        apps.put("android-settings", "com.android.settings");
        apps.put("my-files", "com.sec.android.app.myfiles");
        APP_PACKAGES = Collections.unmodifiableMap(apps);
    }

    @Override
    public IBinder onBind(Intent intent) {
        return binder;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        // No externally exported command protocol is implemented yet.
        stopSelf(startId);
        return START_NOT_STICKY;
    }

    public BatterySnapshot getBattery() {
        Intent battery = registerReceiver(null, new android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED));
        if (battery == null) {
            return new BatterySnapshot(-1, BatteryManager.BATTERY_STATUS_UNKNOWN, -1);
        }
        int level = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
        int scale = battery.getIntExtra(BatteryManager.EXTRA_SCALE, 100);
        int percentage = (level >= 0 && scale > 0) ? (level * 100 / scale) : -1;
        int status = battery.getIntExtra(BatteryManager.EXTRA_STATUS, BatteryManager.BATTERY_STATUS_UNKNOWN);
        int temperature = battery.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1);
        return new BatterySnapshot(percentage, status, temperature);
    }

    public boolean launchAndroidApp(String appId) {
        String packageName = APP_PACKAGES.get(appId);
        if (packageName == null) {
            return false;
        }
        Intent launch = getPackageManager().getLaunchIntentForPackage(packageName);
        if (launch == null) {
            return false;
        }
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        startActivity(launch);
        return true;
    }

    public void openAndroidSettings() {
        Intent settings = new Intent(android.provider.Settings.ACTION_SETTINGS);
        settings.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        startActivity(settings);
    }

    public boolean setMediaVolume(int volume) {
        AudioManager audio = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
        if (audio == null) {
            return false;
        }
        int max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
        if (volume < 0 || volume > max) {
            return false;
        }
        audio.setStreamVolume(AudioManager.STREAM_MUSIC, volume, 0);
        return true;
    }

    public void vibrate(long milliseconds) {
        if (milliseconds < 0 || milliseconds > 10000) {
            return;
        }
        Vibrator vibrator = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
        if (vibrator == null || !vibrator.hasVibrator()) {
            return;
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createOneShot(milliseconds, VibrationEffect.DEFAULT_AMPLITUDE));
        } else {
            vibrator.vibrate(milliseconds);
        }
    }
}
