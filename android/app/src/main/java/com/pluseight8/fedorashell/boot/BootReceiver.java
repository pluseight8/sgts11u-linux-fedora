package com.pluseight8.fedorashell.boot;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.app.role.RoleManager;
import android.os.Build;

/**
 * Boot observer/no-op. The preference is retained for UI compatibility, but
 * this receiver never starts Termux/Fedora from the background: the Home
 * activity performs the visible, user-session launch after Android has brought
 * the selected Home app to the foreground.
 */
public class BootReceiver extends BroadcastReceiver {
    public static final String PREFS = "fedora_shell_preferences";
    public static final String AUTO_START = "auto_start_on_boot";
    public static final String SETUP_COMPLETE = "initial_gui_setup_complete";
    public static final String PROFILE = "linux_mode_profile";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (!Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) {
            return;
        }
        android.content.SharedPreferences preferences = context.getSharedPreferences(
                PREFS, Context.MODE_PRIVATE);
        boolean enabled = preferences.getBoolean(AUTO_START, false);
        boolean setupComplete = preferences.getBoolean(SETUP_COMPLETE, false);
        // A boot receiver can run while the app is not the user's Home app.
        // Do not start an invisible Fedora/Termux workload in that case. This
        // is a read-only role check; Android Settings remains the authority.
        if (!(enabled && setupComplete && isSelectedHome(context))) {
            return;
        }
        // Android 12+ may reject a background Activity launch while still
        // allowing a service command to run. Starting Termux here would
        // therefore create an invisible Fedora workload and waste RAM.
        // MainActivity.maybeAutoResume() runs the fixed command only once this
        // app is the visible Home activity. This receiver intentionally ends
        // here and performs no Android or Termux mutation.
    }

    private boolean isSelectedHome(Context context) {
        if (Build.VERSION.SDK_INT < 29) {
            // RoleManager is unavailable on older Android releases. The
            // receiver is observer-only on every API, so fail closed rather
            // than allowing an invisible boot-time workload.
            return false;
        }
        try {
            RoleManager roleManager = context.getSystemService(RoleManager.class);
            return roleManager != null
                    && roleManager.isRoleAvailable(RoleManager.ROLE_HOME)
                    && roleManager.isRoleHeld(RoleManager.ROLE_HOME);
        } catch (RuntimeException error) {
            // If Android cannot confirm the Home role, avoid a background
            // launch that cannot produce a visible Termux:X11 surface.
            return false;
        }
    }
}
