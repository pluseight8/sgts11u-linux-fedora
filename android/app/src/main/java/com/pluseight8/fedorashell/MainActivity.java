package com.pluseight8.fedorashell;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import com.pluseight8.fedorashell.boot.BootReceiver;
import com.pluseight8.fedorashell.bridge.BridgeClient;

/**
 * Minimal launcher/emergency surface. Selecting this app as Home is always a
 * user-controlled Android Settings decision; the app never replaces One UI.
 */
public class MainActivity extends Activity {
    private TextView status;
    private CheckBox bootCheck;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(Color.BLACK);
        getWindow().setNavigationBarColor(Color.BLACK);
        buildUi();
        applyImmersiveMode();
    }

    @Override
    protected void onResume() {
        super.onResume();
        applyImmersiveMode();
    }

    private void buildUi() {
        int padding = dp(20);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(padding, padding, padding, padding);
        content.setBackgroundColor(Color.rgb(30, 30, 30));

        TextView title = new TextView(this);
        title.setText("Fedora Shell");
        title.setTextColor(Color.WHITE);
        title.setTextSize(28);
        title.setGravity(Gravity.CENTER_HORIZONTAL);
        content.addView(title, new LinearLayout.LayoutParams(-1, -2));

        TextView subtitle = new TextView(this);
        subtitle.setText("Non-root Fedora ARM64 + GNOME controller\nAndroid and One UI remain intact");
        subtitle.setTextColor(Color.LTGRAY);
        subtitle.setGravity(Gravity.CENTER_HORIZONTAL);
        subtitle.setPadding(0, dp(8), 0, dp(18));
        content.addView(subtitle, new LinearLayout.LayoutParams(-1, -2));

        status = new TextView(this);
        status.setText("Wayland-first session; Termux:X11 is the current transport.");
        status.setTextColor(Color.rgb(190, 220, 190));
        status.setPadding(0, 0, 0, dp(12));
        content.addView(status, new LinearLayout.LayoutParams(-1, -2));

        addAction(content, "Start / reconnect Fedora", v -> runScript("start.sh", true));
        addAction(content, "Stop Fedora", v -> runScript("stop.sh", true));
        addAction(content, "Diagnostics", v -> runScript("diagnostics.sh", true));
        addAction(content, "Android Settings", v -> openSettings(Settings.ACTION_SETTINGS));
        addAction(content, "Wi-Fi Settings", v -> openSettings(Settings.ACTION_WIFI_SETTINGS));
        addAction(content, "Bluetooth Settings", v -> openSettings(Settings.ACTION_BLUETOOTH_SETTINGS));
        addAction(content, "Choose Home app / One UI", v -> openSettings(Settings.ACTION_HOME_SETTINGS));

        bootCheck = new CheckBox(this);
        bootCheck.setText("Best-effort Fedora start after Android boot");
        bootCheck.setTextColor(Color.WHITE);
        bootCheck.setChecked(getSharedPreferences(BootReceiver.PREFS, MODE_PRIVATE)
                .getBoolean(BootReceiver.AUTO_START, false));
        bootCheck.setOnCheckedChangeListener((button, checked) -> getSharedPreferences(
                BootReceiver.PREFS, MODE_PRIVATE).edit().putBoolean(BootReceiver.AUTO_START, checked).apply());
        content.addView(bootCheck, new LinearLayout.LayoutParams(-1, -2));

        TextView note = new TextView(this);
        note.setText("Emergency path: use Stop Fedora or Android Settings.\n\nThe app requests Termux RUN_COMMAND only after the user grants the additional permission and enables allow-external-apps=true in Termux.");
        note.setTextColor(Color.LTGRAY);
        note.setPadding(0, dp(16), 0, 0);
        content.addView(note, new LinearLayout.LayoutParams(-1, -2));

        ScrollView scroll = new ScrollView(this);
        scroll.addView(content);
        setContentView(scroll);
    }

    private void addAction(LinearLayout parent, String label, View.OnClickListener listener) {
        Button button = new Button(this);
        button.setText(label);
        button.setOnClickListener(listener);
        parent.addView(button, new LinearLayout.LayoutParams(-1, -2));
    }

    private void runScript(String script, boolean background) {
        boolean sent = BridgeClient.runProjectScript(this, script, background);
        status.setText(sent
                ? "Sent " + script + " to Termux. Android background policy may delay it."
                : "Could not contact Termux. Grant RUN_COMMAND and check Termux setup.");
    }

    private void openSettings(String action) {
        try {
            startActivity(new Intent(action));
        } catch (RuntimeException error) {
            startActivity(new Intent(Settings.ACTION_SETTINGS));
        }
    }

    private void applyImmersiveMode() {
        Window window = getWindow();
        if (android.os.Build.VERSION.SDK_INT >= 30) {
            WindowInsetsController controller = window.getInsetsController();
            if (controller != null) {
                controller.hide(WindowInsets.Type.statusBars() | WindowInsets.Type.navigationBars());
                controller.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
            }
        } else {
            window.getDecorView().setSystemUiVisibility(
                    View.SYSTEM_UI_FLAG_FULLSCREEN
                            | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                            | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                            | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                            | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                            | View.SYSTEM_UI_FLAG_LAYOUT_STABLE);
        }
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
