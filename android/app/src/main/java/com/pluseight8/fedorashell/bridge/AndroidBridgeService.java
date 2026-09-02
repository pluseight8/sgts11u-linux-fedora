package com.pluseight8.fedorashell.bridge;

import android.app.Service;
import android.content.Intent;
import android.os.BatteryManager;
import android.os.Binder;
import android.os.IBinder;

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

    public void openAndroidSettings() {
        Intent settings = new Intent(android.provider.Settings.ACTION_SETTINGS);
        settings.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        startActivity(settings);
    }

}
