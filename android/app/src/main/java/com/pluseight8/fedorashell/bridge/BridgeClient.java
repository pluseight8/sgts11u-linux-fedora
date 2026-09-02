package com.pluseight8.fedorashell.bridge;

import android.app.PendingIntent;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.util.Log;

/**
 * Small client for Termux's documented RUN_COMMAND intent. Only fixed project
 * scripts can be requested; callers cannot pass arbitrary shell commands.
 */
public final class BridgeClient {
    private static final String TAG = "FedoraShellBridge";
    private static final String TERMUX_PACKAGE = "com.termux";
    private static final String RUN_COMMAND_ACTION = "com.termux.RUN_COMMAND";
    private static final String RUN_COMMAND_SERVICE = "com.termux.app.RunCommandService";
    private static final String TERMUX_PREFIX = "/data/data/com.termux/files/usr";
    private static final String TERMUX_HOME = "/data/data/com.termux/files/home";
    private static int nextResultRequestCode = 1000;

    private BridgeClient() {
    }

    public static boolean runProjectScript(Context context, String script, boolean background) {
        return runProjectScript(context, script, background, new String[0]);
    }

    public static boolean runProjectScript(Context context, String script, boolean background,
                                           String... arguments) {
        return runProjectScriptInternal(context, script, background, false, null, arguments) != null;
    }

    /**
     * Ask one small Linux Mode status command for a result. This is used for
     * crash recovery UI; it does not create a general output tunnel.
     */
    public static boolean requestModeStatus(Context context) {
        return requestModeStatusToken(context) != null;
    }

    /**
     * Same status request, returning the callback token so a delayed callback
     * from an older Home visit cannot satisfy a newer probe.
     */
    public static String requestModeStatusToken(Context context) {
        return runProjectScriptInternal(context, "linux-mode.sh", true, true, "status",
                new String[]{"status"});
    }

    /**
     * Ask for one bounded, read-only memory report and return it to the visible
     * controller. The command still runs through the same finite allowlist.
     */
    public static boolean requestMemory(Context context) {
        return requestMemoryToken(context) != null;
    }

    /** Return the one-shot callback token for a memory report request. */
    public static String requestMemoryToken(Context context) {
        return runProjectScriptInternal(context, "linux-mode.sh", true, true, "memory",
                new String[]{"memory"});
    }

    /**
     * Refresh the Fedora-side Android application catalog. The command is
     * intentionally fire-and-forget: the visible GNOME session reports the
     * number of entries, while this controller only needs to confirm that the
     * fixed Termux command was accepted.
     */
    public static boolean syncAndroidApps(Context context) {
        return runProjectScript(context, "android-apps.sh", true);
    }

    private static String runProjectScriptInternal(Context context, String script,
                                                   boolean background, boolean returnResult,
                                                   String requestKind,
                                                   String... arguments) {
        if (!isAllowedScript(script)) {
            Log.e(TAG, "Rejected non-allowlisted script: " + script);
            return null;
        }
        if (!areAllowedArguments(script, arguments)) {
            Log.e(TAG, "Rejected arguments for script: " + script);
            return null;
        }

        Intent intent = new Intent(RUN_COMMAND_ACTION);
        intent.setComponent(new ComponentName(TERMUX_PACKAGE, RUN_COMMAND_SERVICE));
        intent.putExtra("com.termux.RUN_COMMAND_PATH", TERMUX_PREFIX + "/bin/bash");
        StringBuilder command = new StringBuilder("config=\"$HOME/.fedora-shell/config.env\"; "
                + "if [ -r \"$config\" ]; then . \"$config\"; fi; "
                + "root=\"${FEDORA_INSTALL_ROOT:-$HOME/.local/share/fedora-shell}\"; "
                // Invoke through Termux bash so a Git checkout that lost
                // executable mode bits cannot strand the Android controller.
                // The script name is still fixed by isAllowedScript().
                + "exec \"" + TERMUX_PREFIX + "/bin/bash\" \"$root/scripts/" + script + "\"");
        for (String argument : arguments) {
            command.append(' ').append(shellQuote(argument));
        }
        intent.putExtra("com.termux.RUN_COMMAND_ARGUMENTS", new String[]{"-lc", command.toString()});
        intent.putExtra("com.termux.RUN_COMMAND_WORKDIR", TERMUX_HOME);
        intent.putExtra("com.termux.RUN_COMMAND_BACKGROUND", background);
        intent.putExtra("com.termux.RUN_COMMAND_SESSION_ACTION", "0");
        intent.putExtra("com.termux.RUN_COMMAND_COMMAND_LABEL", "Fedora Shell: " + script);
        intent.putExtra("com.termux.RUN_COMMAND_COMMAND_DESCRIPTION", "Run the Fedora Shell project action.");
        String requestToken = "sent";
        if (returnResult) {
            try {
                int requestCode = nextResultRequestCode();
                requestToken = Integer.toString(requestCode);
                Intent resultIntent = new Intent(context, CommandResultService.class);
                resultIntent.putExtra(CommandResultService.EXTRA_COMMAND, script);
                resultIntent.putExtra(CommandResultService.EXTRA_REQUEST_KIND, requestKind);
                resultIntent.putExtra(CommandResultService.EXTRA_REQUEST_TOKEN, requestToken);
                int flags = PendingIntent.FLAG_ONE_SHOT;
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    // Termux adds its result bundle when it sends the callback.
                    flags |= PendingIntent.FLAG_MUTABLE;
                }
                PendingIntent resultPendingIntent = PendingIntent.getService(
                        context, requestCode, resultIntent, flags);
                intent.putExtra("com.termux.RUN_COMMAND_PENDING_INTENT", resultPendingIntent);
            } catch (RuntimeException error) {
                Log.e(TAG, "Unable to create the Termux command-result callback", error);
                return null;
            }
        }

        try {
            context.startService(intent);
            return requestToken;
        } catch (RuntimeException error) {
            Log.e(TAG, "Unable to send RUN_COMMAND intent", error);
            return null;
        }
    }

    private static synchronized int nextResultRequestCode() {
        if (nextResultRequestCode == Integer.MAX_VALUE) {
            nextResultRequestCode = 1000;
        }
        return nextResultRequestCode++;
    }

    private static boolean isAllowedScript(String script) {
        return "start.sh".equals(script)
                || "stop.sh".equals(script)
                || "diagnostics.sh".equals(script)
                || "android-apps.sh".equals(script)
                || "linux-mode.sh".equals(script);
    }

    private static boolean areAllowedArguments(String script, String[] arguments) {
        if (!"linux-mode.sh".equals(script)) {
            return arguments.length == 0;
        }
        // Keep the Android-to-Termux protocol deliberately finite. A command
        // word is mandatory, and only enable/toggle may carry one profile.
        // This prevents a future UI call site from accidentally turning the
        // bridge into a general-purpose argument tunnel.
        if (arguments.length == 0 || !isAllowedModeCommand(arguments[0])) {
            return false;
        }
        if (arguments.length == 1) {
            return true;
        }
        if (!("enable".equals(arguments[0]) || "toggle".equals(arguments[0]))) {
            return false;
        }
        if (arguments.length == 2) {
            return arguments[1].startsWith("--profile=")
                    && isAllowedProfile(arguments[1].substring("--profile=".length()));
        }
        return arguments.length == 3
                && "--profile".equals(arguments[1])
                && isAllowedProfile(arguments[2]);
    }

    private static boolean isAllowedModeCommand(String argument) {
        return "setup-status".equals(argument)
                || "status".equals(argument)
                || "enable".equals(argument)
                || "disable".equals(argument)
                || "toggle".equals(argument)
                || "memory".equals(argument)
                || "recover".equals(argument);
    }

    private static boolean isAllowedProfile(String profile) {
        return "balanced".equals(profile)
                || "linux-focused".equals(profile)
                || "maximum-linux".equals(profile);
    }

    private static String shellQuote(String value) {
        return "'" + value.replace("'", "'\\''") + "'";
    }
}
