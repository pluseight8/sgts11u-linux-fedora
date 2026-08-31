package com.pluseight8.fedorashell.bridge;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
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

    private BridgeClient() {
    }

    public static boolean runProjectScript(Context context, String script, boolean background) {
        if (!isAllowedScript(script)) {
            Log.e(TAG, "Rejected non-allowlisted script: " + script);
            return false;
        }

        Intent intent = new Intent(RUN_COMMAND_ACTION);
        intent.setComponent(new ComponentName(TERMUX_PACKAGE, RUN_COMMAND_SERVICE));
        intent.putExtra("com.termux.RUN_COMMAND_PATH", TERMUX_PREFIX + "/bin/bash");
        String command = "config=\"$HOME/.fedora-shell/config.env\"; "
                + "if [ -r \"$config\" ]; then . \"$config\"; fi; "
                + "root=\"${FEDORA_INSTALL_ROOT:-$HOME/.local/share/fedora-shell}\"; "
                + "exec \"$root/scripts/" + script + "\"";
        intent.putExtra("com.termux.RUN_COMMAND_ARGUMENTS", new String[]{"-lc", command});
        intent.putExtra("com.termux.RUN_COMMAND_WORKDIR", TERMUX_HOME);
        intent.putExtra("com.termux.RUN_COMMAND_BACKGROUND", background);
        intent.putExtra("com.termux.RUN_COMMAND_SESSION_ACTION", "0");
        intent.putExtra("com.termux.RUN_COMMAND_COMMAND_LABEL", "Fedora Shell: " + script);
        intent.putExtra("com.termux.RUN_COMMAND_COMMAND_DESCRIPTION", "Run the Fedora Shell project action.");

        try {
            context.startService(intent);
            return true;
        } catch (RuntimeException error) {
            Log.e(TAG, "Unable to send RUN_COMMAND intent", error);
            return false;
        }
    }

    private static boolean isAllowedScript(String script) {
        return "start.sh".equals(script)
                || "stop.sh".equals(script)
                || "diagnostics.sh".equals(script);
    }
}
