package com.pluseight8.fedorashell.bridge;

import android.app.IntentService;
import android.content.Intent;
import android.os.Bundle;

/**
 * Receives the result of one small, allowlisted Termux status or memory request. The
 * service forwards only an in-memory, package-scoped update to the visible
 * activity; command output is not persisted and is deliberately truncated.
 */
public class CommandResultService extends IntentService {
    public static final String ACTION_RESULT =
            "com.pluseight8.fedorashell.ACTION_TERMUX_RESULT";
    public static final String EXTRA_COMMAND = "command";
    public static final String EXTRA_REQUEST_KIND = "request_kind";
    public static final String EXTRA_REQUEST_TOKEN = "request_token";
    public static final String EXTRA_EXIT_CODE = "exit_code";
    public static final String EXTRA_ERROR_CODE = "error_code";
    public static final String EXTRA_STDOUT = "stdout";
    public static final String EXTRA_STDERR = "stderr";

    private static final String RESULT_BUNDLE = "result";
    private static final String RESULT_EXIT_CODE = "exitCode";
    private static final String RESULT_ERROR_CODE = "err";
    private static final String RESULT_STDOUT = "stdout";
    private static final String RESULT_STDERR = "stderr";
    private static final int MAX_FORWARD_CHARS = 4096;

    public CommandResultService() {
        super("FedoraShellCommandResult");
    }

    @Override
    protected void onHandleIntent(Intent intent) {
        if (intent == null) {
            return;
        }
        Bundle result = intent.getBundleExtra(RESULT_BUNDLE);
        if (result == null) {
            return;
        }

        Intent update = new Intent(ACTION_RESULT);
        update.setPackage(getPackageName());
        update.putExtra(EXTRA_COMMAND, intent.getStringExtra(EXTRA_COMMAND));
        update.putExtra(EXTRA_REQUEST_KIND, intent.getStringExtra(EXTRA_REQUEST_KIND));
        update.putExtra(EXTRA_REQUEST_TOKEN, intent.getStringExtra(EXTRA_REQUEST_TOKEN));
        update.putExtra(EXTRA_EXIT_CODE, result.getInt(RESULT_EXIT_CODE, -1));
        update.putExtra(EXTRA_ERROR_CODE, result.getInt(RESULT_ERROR_CODE, -1));
        update.putExtra(EXTRA_STDOUT, limit(result.getString(RESULT_STDOUT, "")));
        update.putExtra(EXTRA_STDERR, limit(result.getString(RESULT_STDERR, "")));
        sendBroadcast(update);
    }

    private String limit(String value) {
        if (value == null) {
            return "";
        }
        return value.length() <= MAX_FORWARD_CHARS
                ? value
                : value.substring(0, MAX_FORWARD_CHARS);
    }
}
