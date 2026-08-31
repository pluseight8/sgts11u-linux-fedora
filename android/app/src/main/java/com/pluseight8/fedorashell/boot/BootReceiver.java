package com.pluseight8.fedorashell.boot;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

import com.pluseight8.fedorashell.bridge.BridgeClient;

/**
 * Optional best-effort boot hook. It is disabled until the user checks the
 * setting in Fedora Shell; Android/Samsung background policy can still defer
 * or reject the Termux command.
 */
public class BootReceiver extends BroadcastReceiver {
    public static final String PREFS = "fedora_shell_preferences";
    public static final String AUTO_START = "auto_start_on_boot";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (!Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())
                && !Intent.ACTION_LOCKED_BOOT_COMPLETED.equals(intent.getAction())) {
            return;
        }
        boolean enabled = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean(AUTO_START, false);
        if (enabled) {
            BridgeClient.runProjectScript(context, "start.sh", true);
        }
    }
}
