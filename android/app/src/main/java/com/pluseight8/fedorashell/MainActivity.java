package com.pluseight8.fedorashell;

import android.app.Activity;
import android.app.ActivityManager;
import android.app.AlertDialog;
import android.app.role.RoleManager;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Spinner;
import android.widget.TextView;

import com.pluseight8.fedorashell.boot.BootReceiver;
import com.pluseight8.fedorashell.bridge.BridgeClient;
import com.pluseight8.fedorashell.bridge.CommandResultService;

import java.util.Locale;

/**
 * User-facing Linux Mode controller. It is also declared as a HOME candidate,
 * but Android Settings decides whether the user selects it. This activity does
 * not remove, disable or reconfigure One UI or Android services.
 */
public class MainActivity extends Activity {
    private static final int HOME_ROLE_REQUEST = 4101;
    private static final String[] PROFILE_LABELS = {
            "Balanced",
            "Linux Focused (recommended for 12 GiB)",
            "Maximum Linux (Fedora-side only)"
    };
    private static final String[] PROFILE_SLUGS = {
            "balanced",
            "linux-focused",
            "maximum-linux"
    };

    private TextView status;
    private CheckBox bootCheck;
    private Spinner profileSpinner;
    private boolean setupComplete;
    private boolean launchedAsHome;
    private boolean autoResumeAttempted;
    private boolean statusProbePending;
    private boolean statusProbeComplete;
    private boolean memoryProbePending;
    private int statusProbeGeneration;
    private int memoryProbeGeneration;
    private String statusProbeToken;
    private String memoryProbeToken;
    private boolean recoveryDialogShown;
    private BroadcastReceiver termuxResultReceiver;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(Color.TRANSPARENT);
        getWindow().setNavigationBarColor(Color.TRANSPARENT);
        setupComplete = preferences().getBoolean(BootReceiver.SETUP_COMPLETE, false);
        launchedAsHome = isHomeIntent(getIntent());
        buildUi();
        registerTermuxResultReceiver();
        applyImmersiveMode();
        if (handleAndroidLaunchIntent(getIntent())) {
            return;
        }
        requestHomeStatus();
    }

    @Override
    protected void onDestroy() {
        if (termuxResultReceiver != null) {
            unregisterReceiver(termuxResultReceiver);
            termuxResultReceiver = null;
        }
        super.onDestroy();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        if (handleAndroidLaunchIntent(intent)) {
            return;
        }
        launchedAsHome = isHomeIntent(intent);
        if (launchedAsHome) {
            // A later Home intent is a new visible session. Do not let a
            // previous auto-resume attempt permanently suppress this one.
            autoResumeAttempted = false;
        }
        statusProbeGeneration++;
        statusProbePending = false;
        statusProbeComplete = false;
        statusProbeToken = null;
        requestHomeStatus();
        maybeAutoResume();
    }

    @Override
    protected void onResume() {
        super.onResume();
        applyImmersiveMode();
        maybeAutoResume();
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) {
            applyImmersiveMode();
        }
    }

    private android.content.SharedPreferences preferences() {
        return getSharedPreferences(BootReceiver.PREFS, MODE_PRIVATE);
    }

    private void buildUi() {
        int padding = dp(20);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(padding, padding, padding, padding);
        content.setBackgroundColor(Color.rgb(30, 30, 30));

        TextView title = text("Linux Mode", 28, Color.WHITE);
        title.setGravity(Gravity.CENTER_HORIZONTAL);
        content.addView(title, matchWrap());

        TextView subtitle = text(
                "Fedora ARM64 · GNOME · Mutter · Wayland\nAndroid remains the hardware and safety host",
                15, Color.LTGRAY);
        subtitle.setGravity(Gravity.CENTER_HORIZONTAL);
        subtitle.setPadding(0, dp(8), 0, dp(16));
        content.addView(subtitle, matchWrap());

        status = text(setupComplete
                ? "Android Mode: unchanged. Linux Mode is ready to start."
                : "Complete the initial GUI setup before starting Linux Mode.",
                15, Color.rgb(190, 220, 190));
        status.setPadding(0, 0, 0, dp(12));
        content.addView(status, matchWrap());

        if (!setupComplete) {
            addInitialSetup(content);
        }

        TextView modeTitle = text("LINUX MODE", 19, Color.WHITE);
        modeTitle.setPadding(0, dp(14), 0, dp(4));
        content.addView(modeTitle, matchWrap());

        TextView modeNote = text(
                "ON starts Fedora through Termux:X11/PRoot. OFF stops only project-owned Fedora processes.\n"
                        + "No Android package, setting, service, kernel, LMKD or zRAM policy is changed.",
                14, Color.LTGRAY);
        modeNote.setPadding(0, 0, 0, dp(8));
        content.addView(modeNote, matchWrap());

        profileSpinner = new Spinner(this);
        ArrayAdapter<String> adapter = new ArrayAdapter<>(
                this, android.R.layout.simple_spinner_item, PROFILE_LABELS);
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        profileSpinner.setAdapter(adapter);
        profileSpinner.setSelection(profileIndex(preferences().getString(
                BootReceiver.PROFILE, "linux-focused")));
        profileSpinner.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener() {
            @Override
            public void onItemSelected(android.widget.AdapterView<?> parent, View view,
                                       int position, long id) {
                preferences().edit().putString(BootReceiver.PROFILE,
                        PROFILE_SLUGS[position]).apply();
            }

            @Override
            public void onNothingSelected(android.widget.AdapterView<?> parent) {
                // Keep the last explicit profile.
            }
        });
        content.addView(profileSpinner, matchWrap());

        Button start = addAction(content, "Linux Mode ON / Start Fedora", v -> startFedora());
        start.setEnabled(setupComplete);
        addAction(content, "Linux Mode OFF / Restore Android Mode", v -> stopFedora());
        addAction(content, "Recover unclean Fedora session", v -> runModeCommand("recover"));
        addAction(content, "Memory (read-only)", v -> showMemoryDialog());
        addAction(content, "Refresh Android apps in Fedora", v -> syncAndroidApps());
        addAction(content, "RAM Plus — read-only guidance", v -> showRamPlusGuidance());
        addAction(content, "Android deep sleep — only manual guidance",
                v -> showAndroidDeepSleepGuidance());

        bootCheck = new CheckBox(this);
        bootCheck.setText("Auto-resume Linux Mode when Fedora Shell Home appears");
        bootCheck.setTextColor(Color.WHITE);
        bootCheck.setChecked(preferences().getBoolean(BootReceiver.AUTO_START, false));
        bootCheck.setEnabled(setupComplete);
        bootCheck.setOnCheckedChangeListener((button, checked) -> preferences().edit()
                .putBoolean(BootReceiver.AUTO_START, checked).apply());
        content.addView(bootCheck, matchWrap());

        addAction(content, "Open Termux:X11", v -> setStatus(openTermuxX11Activity()
                ? "Termux:X11 opened. Keep its Activity visible; leave its device fullscreen off for bottom-swipe navigation."
                : "Termux:X11 Activity is unavailable; install the compatible APK manually."));
        addAction(content, "Android navigation and overlay guidance",
                v -> showNavigationGuidance());
        addAction(content, "Linux Mode keyboard focus (Linux only)",
                v -> showKeyboardGuidance());
        addAction(content, "Check prerequisites (read-only)",
                v -> runModeCommand("setup-status"));
        addAction(content, "Run read-only diagnostics", v -> runScript("diagnostics.sh", true));
        addAction(content, "Choose Fedora Shell as Home", v -> chooseHome());
        addAction(content, "Return to One UI Home (choose in Android)",
                v -> openSettings(Settings.ACTION_HOME_SETTINGS));
        addAction(content, "Open Termux (check RUN_COMMAND)",
                v -> setStatus(openTermuxActivity()
                        ? "Termux opened. Verify allow-external-apps=true, then return here."
                        : "Termux is not installed or cannot be opened."));
        addAction(content, "Android Settings", v -> openSettings(Settings.ACTION_SETTINGS));

        TextView note = text(
                "Initial setup is intentionally user-controlled. Fedora Shell is only a Home candidate;"
                        + " Android Settings must approve the choice. One UI Home is never deleted or disabled.\n\n"
                        + "Android owns the volume panel, notification shade and system navigation. This app cannot"
                        + " block those protected overlays. The controller keeps the bottom gesture/navigation area"
                        + " available. Termux:X11 is a separate Android Activity, so its own fullscreen preference"
                        + " must be left off when reliable bottom-swipe navigation is needed.",
                13, Color.LTGRAY);
        note.setPadding(0, dp(16), 0, 0);
        content.addView(note, matchWrap());

        ScrollView scroll = new ScrollView(this);
        scroll.addView(content);
        installNavigationInsets(scroll);
        setContentView(scroll);
    }

    private void installNavigationInsets(ScrollView scroll) {
        if (android.os.Build.VERSION.SDK_INT >= 30) {
            scroll.setOnApplyWindowInsetsListener((view, insets) -> {
                int insetTypes = WindowInsets.Type.systemBars()
                        | WindowInsets.Type.displayCutout()
                        | WindowInsets.Type.mandatorySystemGestures();
                int bottom = insets.getInsets(insetTypes).bottom;
                int safeBottom = Math.max(dp(24), bottom);
                view.setPadding(view.getPaddingLeft(), view.getPaddingTop(),
                        view.getPaddingRight(), safeBottom);
                return insets;
            });
        } else {
            // API 26–29 do not expose the modern type-based inset API. Keep a
            // conservative navigation-bar reserve for those devices.
            scroll.setPadding(0, 0, 0, dp(48));
        }
        // The listener deliberately does not consume insets or touch events.
        // Android therefore retains ownership of the bottom gesture edge.
        scroll.requestApplyInsets();
    }

    private void addInitialSetup(LinearLayout content) {
        TextView heading = text("Первоначальная настройка", 21, Color.WHITE);
        heading.setPadding(0, dp(8), 0, dp(4));
        content.addView(heading, matchWrap());

        TextView explanation = text(
                "Перед первым запуском проверьте транспорт и, если хотите, выберите Fedora Shell"
                        + " в Android Settings → Home app. Android/One UI, приложения, службы, ядро,"
                        + " LMKD и zRAM остаются нетронутыми; Fedora работает поверх них через Termux/PRoot.",
                14, Color.LTGRAY);
        explanation.setPadding(0, 0, 0, dp(8));
        content.addView(explanation, matchWrap());

        TextView checklist = text(initialSetupChecklist(), 13, Color.rgb(210, 210, 210));
        checklist.setPadding(0, 0, 0, dp(8));
        content.addView(checklist, matchWrap());

        addAction(content, "1. Открыть Termux:X11", v -> setStatus(openTermuxX11Activity()
                ? "Termux:X11 открыт. Для свайпа снизу оставьте device fullscreen выключенным; touch можно включить."
                : "Откройте совместимый Termux:X11 APK вручную."));
        addAction(content, "2. RAM Plus (только инструкция)", v -> showRamPlusGuidance());
        addAction(content, "3. Глубокий сон Android (только инструкция)",
                v -> showAndroidDeepSleepGuidance());
        addAction(content, "4. Настроить навигацию Android (только инструкция)",
                v -> showNavigationGuidance());
        addAction(content, "5. Настроить фокус клавиатуры Linux (только инструкция)",
                v -> showKeyboardGuidance());
        addAction(content, "6. Проверить prerequisites (только чтение)",
                v -> runModeCommand("setup-status"));
        addAction(content, "7. Запустить read-only диагностику", v -> runScript("diagnostics.sh", true));
        addAction(content, "8. Попробовать выбрать Fedora Shell как Home", v -> chooseHome());
        addAction(content, "Открыть Termux и проверить RUN_COMMAND",
                v -> setStatus(openTermuxActivity()
                        ? "Termux открыт. Проверьте allow-external-apps=true и вернитесь сюда."
                        : "Termux не найден; установите официальный Termux вручную."));

        CheckBox safetyCheck = new CheckBox(this);
        safetyCheck.setText("Я понимаю: Android не изменяется, а Home выбирается вручную");
        safetyCheck.setTextColor(Color.WHITE);
        content.addView(safetyCheck, matchWrap());
        addAction(content, "Завершить первоначальную настройку", v -> {
            if (!safetyCheck.isChecked()) {
                setStatus("Поставьте подтверждение безопасности, чтобы завершить настройку.");
                return;
            }
            preferences().edit().putBoolean(BootReceiver.SETUP_COMPLETE, true).apply();
            setupComplete = true;
            buildUi();
            applyImmersiveMode();
            setStatus("Настройка завершена. Android/One UI не изменялись.");
            requestHomeStatus();
            maybeAutoResume();
        });
    }

    private TextView text(String value, int size, int color) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextColor(color);
        view.setTextSize(size);
        return view;
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(-1, -2);
    }

    private Button addAction(LinearLayout parent, String label, View.OnClickListener listener) {
        Button button = new Button(this);
        button.setText(label);
        button.setOnClickListener(listener);
        parent.addView(button, matchWrap());
        return button;
    }

    private void setStatus(String message) {
        if (status != null) {
            status.setText(message);
        }
    }

    private void registerTermuxResultReceiver() {
        termuxResultReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                handleTermuxResult(intent);
            }
        };
        IntentFilter filter = new IntentFilter(CommandResultService.ACTION_RESULT);
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            registerReceiver(termuxResultReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            registerReceiver(termuxResultReceiver, filter);
        }
    }

    private void requestHomeStatus() {
        if (!setupComplete || !launchedAsHome || statusProbePending || statusProbeComplete) {
            return;
        }
        statusProbePending = true;
        final int generation = ++statusProbeGeneration;
        statusProbeToken = BridgeClient.requestModeStatusToken(this);
        if (statusProbeToken == null) {
            statusProbePending = false;
            statusProbeComplete = true;
            statusProbeToken = null;
            maybeAutoResume();
            return;
        }
        // A missing callback must never strand the Home activity. The fallback
        // preserves the old best-effort auto-start behavior after a short wait.
        getWindow().getDecorView().postDelayed(() -> {
            if (statusProbePending && statusProbeGeneration == generation) {
                statusProbePending = false;
                statusProbeComplete = true;
                statusProbeToken = null;
                maybeAutoResume();
            }
        }, 1800);
    }

    private void handleTermuxResult(Intent intent) {
        if (!"linux-mode.sh".equals(intent.getStringExtra(CommandResultService.EXTRA_COMMAND))) {
            return;
        }
        String requestKind = intent.getStringExtra(CommandResultService.EXTRA_REQUEST_KIND);
        String requestToken = intent.getStringExtra(CommandResultService.EXTRA_REQUEST_TOKEN);
        if ("memory".equals(requestKind)) {
            if (!memoryProbePending) {
                return;
            }
            if (requestToken != null && memoryProbeToken != null
                    && !requestToken.equals(memoryProbeToken)) {
                return;
            }
            memoryProbePending = false;
            memoryProbeToken = null;
            int exitCode = intent.getIntExtra(CommandResultService.EXTRA_EXIT_CODE, -1);
            showMemoryReportDialog(
                    intent.getStringExtra(CommandResultService.EXTRA_STDOUT),
                    intent.getStringExtra(CommandResultService.EXTRA_STDERR),
                    exitCode);
            return;
        }
        // A result from a future request kind must never be interpreted as a
        // Home status response. Older callbacks without a kind remain accepted
        // for compatibility with an already-running controller process.
        if (requestKind != null && !"status".equals(requestKind)) {
            return;
        }
        // A delayed callback from an earlier Home visit must not overwrite a
        // newer UI state or unexpectedly open the recovery dialog.
        if (!statusProbePending) {
            return;
        }
        if (requestToken != null && statusProbeToken != null
                && !requestToken.equals(statusProbeToken)) {
            return;
        }
        statusProbePending = false;
        statusProbeComplete = true;
        statusProbeToken = null;
        int exitCode = intent.getIntExtra(CommandResultService.EXTRA_EXIT_CODE, -1);
        String stdout = intent.getStringExtra(CommandResultService.EXTRA_STDOUT);
        if (exitCode == 0 && isUncleanState(stdout)) {
            if (launchedAsHome && preferences().getBoolean(BootReceiver.AUTO_START, false)) {
                showRecoveryDialog();
            } else {
                setStatus("Previous Linux Mode did not exit cleanly. Use Recover or Restore Android Mode.");
            }
            return;
        }
        if (exitCode != 0) {
            setStatus("Linux Mode status probe failed; use read-only diagnostics in Termux.");
        }
        maybeAutoResume();
    }

    private boolean isUncleanState(String output) {
        return output != null && (output.contains("phase=crashed")
                || output.contains("phase=exited")
                || output.contains("phase=needs-recovery"));
    }

    private void showRecoveryDialog() {
        if (recoveryDialogShown || isFinishing()) {
            return;
        }
        recoveryDialogShown = true;
        new AlertDialog.Builder(this)
                .setTitle("Previous Linux Mode did not exit cleanly")
                .setMessage("Fedora stopped unexpectedly. Resume it, or stop the recorded Fedora resources safely. Android and One UI remain unchanged.")
                .setPositiveButton("Resume Linux Mode", (dialog, which) -> {
                    recoveryDialogShown = false;
                    startFedora();
                })
                .setNegativeButton("Restore Android Mode", (dialog, which) -> {
                    recoveryDialogShown = false;
                    runModeCommand("recover");
                })
                .setNeutralButton("Later", (dialog, which) -> recoveryDialogShown = false)
                .setOnCancelListener(dialog -> recoveryDialogShown = false)
                .show();
    }

    private void runScript(String script, boolean background) {
        boolean sent = BridgeClient.runProjectScript(this, script, background);
        setStatus(sent
                ? "Отправлено в Termux: " + script
                : "Не удалось связаться с Termux. Проверьте RUN_COMMAND и allow-external-apps.");
    }

    private void runModeCommand(String command) {
        boolean sent = BridgeClient.runProjectScript(this, "linux-mode.sh", true, command);
        setStatus(sent
                ? "Linux Mode command sent: " + command
                : "Не удалось связаться с Termux. Проверьте разрешение RUN_COMMAND.");
    }

    /**
     * Android 12+ may reject a background activity launch from Termux. The
     * controller is foreground when the user presses ON, so open the X11
     * Activity here and only send the project command to Termux.
     */
    private void startFedora() {
        if (!setupComplete) {
            setStatus("Сначала завершите первоначальную GUI-настройку.");
            return;
        }
        String profile = selectedProfile();
        boolean x11Opened = openTermuxX11Activity();
        if (!x11Opened) {
            // Do not start a headless PRoot/Wayland workload. The user can
            // open the compatible Termux:X11 APK manually and press ON again;
            // this keeps a failed Android surface launch from wasting RAM.
            setStatus("Termux:X11 не открылся. Сначала откройте совместимый APK вручную, затем повторите ON.");
            return;
        }
        boolean sent = BridgeClient.runProjectScript(this, "linux-mode.sh", true,
                "enable", "--profile", profile);
        if (!sent) {
            setStatus("Не удалось связаться с Termux. Проверьте разрешение RUN_COMMAND.");
        } else {
            setStatus("Linux Mode ON отправлен; профиль: " + profile + ". Termux:X11 открыт.");
        }
    }

    private void stopFedora() {
        boolean sent = BridgeClient.runProjectScript(this, "linux-mode.sh", true, "disable");
        setStatus(sent
                ? "Linux Mode OFF отправлен. Android Mode и One UI остаются штатными."
                : "Не удалось связаться с Termux. Попробуйте stop.sh из Termux.");
    }

    private void syncAndroidApps() {
        boolean sent = BridgeClient.syncAndroidApps(this);
        setStatus(sent
                ? "Обновление Android-приложений отправлено в Fedora; Android не изменяется."
                : "Не удалось связаться с Termux. Проверьте RUN_COMMAND и запущенный Linux Mode.");
    }

    private String selectedProfile() {
        int position = profileSpinner == null ? 1 : profileSpinner.getSelectedItemPosition();
        if (position < 0 || position >= PROFILE_SLUGS.length) {
            position = 1;
        }
        return PROFILE_SLUGS[position];
    }

    private int profileIndex(String profile) {
        for (int index = 0; index < PROFILE_SLUGS.length; index++) {
            if (PROFILE_SLUGS[index].equals(profile)) {
                return index;
            }
        }
        return 1;
    }

    private void showMemoryDialog() {
        ActivityManager manager = (ActivityManager) getSystemService(ACTIVITY_SERVICE);
        ActivityManager.MemoryInfo info = new ActivityManager.MemoryInfo();
        if (manager != null) {
            manager.getMemoryInfo(info);
        }
        String message = String.format(Locale.US,
                "Только чтение — Android остаётся владельцем памяти.\n\n"
                        + "Total host RAM: %s\nAvailable host RAM: %s\nLow-memory signal: %s\n\n"
                        + "Fedora PSS и PSI измеряются отдельным Termux-представлением и сохраняются в\n"
                        + "$HOME/.fedora-shell/state/memory-latest.json.\n"
                        + "RAM Plus не читается как точная настройка: полный отчёт показывает только косвенные"
                        + " swap/zRAM-счётчики и помечает неизвестные значения.\n"
                        + "Профили Linux Mode экономят память только на Fedora helpers/буферах; Android apps"
                        + " не останавливаются и не ограничиваются. Для Android-приложений доступна отдельная"
                        + " инструкция глубокого сна; она не применяет политику автоматически.",
                formatBytes(info.totalMem), formatBytes(info.availMem), info.lowMemory ? "yes" : "no");
        new AlertDialog.Builder(this)
                .setTitle("Memory — read-only")
                .setMessage(message)
                .setNegativeButton("Закрыть", null)
                .setPositiveButton("Снять полный отчёт", (dialog, which) -> requestMemoryReport())
                .show();
    }

    private void showAndroidDeepSleepGuidance() {
        String message =
                "Глубокий сон Android — только ручная настройка Samsung/Android.\n\n"
                        + "Fedora Shell не переводит приложения в deep sleep, не меняет AppOps или"
                        + " background restrictions, не выполняет force-stop и не вмешивается в LMKD,"
                        + " CachedAppOptimizer, zRAM или RAM Plus. Это обязательная граница безопасности"
                        + " и совместимости. Android сам переводит неиспользуемые cached-процессы в"
                        + " состояние reclaim/frozen, когда это необходимо.\n\n"
                        + "Если приложение можно без уведомлений и фоновой синхронизации, откройте Android"
                        + " Settings → Батарея / Обслуживание устройства → Ограничения фоновой работы →"
                        + " Приложения в глубоком сне. Названия пунктов зависят от версии One UI."
                        + " Добавляйте туда только приложения, для которых вы принимаете задержку уведомлений"
                        + " и фоновых задач. Мессенджеры, звонки, навигацию, VPN, Bluetooth-компаньоны и"
                        + " выбранные приложения не ограничивайте без проверки.\n\n"
                        + "Эта кнопка лишь открывает штатный экран Android/Samsung. Fedora Shell не записывает"
                        + " туда никаких значений и не удаляет One UI или приложения.";
        new AlertDialog.Builder(this)
                .setTitle("Android deep sleep — только вручную")
                .setMessage(message)
                .setNegativeButton("Закрыть", null)
                .setPositiveButton("Открыть Android Settings",
                        (dialog, which) -> openAndroidDeepSleepSettings())
                .show();
    }

    /**
     * Samsung documents this activity as a user-facing deep-sleep list. The
     * explicit activity type is only navigation: the user still chooses every
     * package in Android UI. If a firmware removes or renames the entry point,
     * fall back to the public Android Settings screen.
     */
    private void openAndroidDeepSleepSettings() {
        Intent intent = new Intent();
        intent.setAction("com.samsung.android.sm.ACTION_OPEN_CHECKABLE_LISTACTIVITY");
        intent.setPackage("com.samsung.android.lool");
        intent.putExtra("activity_type", 1);
        try {
            if (getPackageManager().resolveActivity(intent, 0) != null) {
                startActivity(intent);
                return;
            }
        } catch (RuntimeException ignored) {
            // Firmware-specific Samsung entry point is optional.
        }
        openSettings(Settings.ACTION_SETTINGS);
    }

    private void showRamPlusGuidance() {
        String message =
                "RAM Plus — функция Android/Samsung, а не настройка Fedora.\n\n"
                        + "По вашему правилу Fedora Shell не включает, не выключает и не меняет RAM Plus"
                        + " скрытыми командами, не пишет Android settings и не трогает LMKD, zRAM или ядро.\n\n"
                        + "Если вы хотите включить RAM Plus вручную, обычно путь такой:\n"
                        + "Настройки → Обслуживание устройства → Память → RAM Plus.\n"
                        + "Название пунктов может отличаться; Android может попросить перезапуск.\n\n"
                        + "RAM Plus использует внутреннее хранилище как виртуальную память, это не добавляет"
                        + " физическую RAM и не гарантирует ускорение GNOME. При сильном давлении на память"
                        + " возможны дополнительные операции с накопителем и задержки. Оставьте управление"
                        + " zRAM/LMKD Android штатным.\n\n"
                        + "Кнопка Memory / полный отчёт покажет доступные косвенные zRAM/swap-метрики, но"
                        + " точное состояние RAM Plus останется unknown — в JSON это отмечается как"
                        + " android.ramPlus.setting=not-readable. Это намеренная граница безопасности.";
        new AlertDialog.Builder(this)
                .setTitle("RAM Plus — только чтение")
                .setMessage(message)
                .setNegativeButton("Закрыть", null)
                .setPositiveButton("Открыть Android Settings",
                        (dialog, which) -> openSettings(Settings.ACTION_SETTINGS))
                .show();
    }

    private void requestMemoryReport() {
        if (memoryProbePending) {
            setStatus("Отчёт памяти уже запрашивается; Android остаётся нетронутым.");
            return;
        }
        memoryProbePending = true;
        final int generation = ++memoryProbeGeneration;
        memoryProbeToken = BridgeClient.requestMemoryToken(this);
        if (memoryProbeToken == null) {
            memoryProbePending = false;
            memoryProbeToken = null;
            setStatus("Не удалось запросить read-only отчёт. Проверьте RUN_COMMAND.");
            return;
        }
        setStatus("Снимается read-only отчёт: host, Android attribution, Fedora, zRAM/PSI...");
        getWindow().getDecorView().postDelayed(() -> {
            if (memoryProbePending && memoryProbeGeneration == generation) {
                memoryProbePending = false;
                memoryProbeToken = null;
                setStatus("Отчёт памяти не вернулся вовремя; Android не изменялся.");
            }
        }, 10000);
    }

    private void showMemoryReportDialog(String stdout, String stderr, int exitCode) {
        String report = stdout == null ? "" : stdout.trim();
        if (report.isEmpty() && stderr != null) {
            report = stderr.trim();
        }
        if (report.isEmpty()) {
            report = "Termux returned no report output.";
        }
        if (exitCode != 0) {
            report = "Read-only report command exited with code " + exitCode + "\n\n" + report;
        }

        TextView reportView = text(report, 13, Color.WHITE);
        reportView.setTextIsSelectable(true);
        reportView.setPadding(dp(16), dp(12), dp(16), dp(12));
        ScrollView scroll = new ScrollView(this);
        scroll.addView(reportView);
        new AlertDialog.Builder(this)
                .setTitle("Memory — read-only report")
                .setView(scroll)
                .setNegativeButton("Закрыть", null)
                .show();
    }

    private String formatBytes(long bytes) {
        if (bytes <= 0) {
            return "unavailable";
        }
        return String.format(Locale.US, "%,d MiB", bytes / (1024L * 1024L));
    }

    private boolean openTermuxX11Activity() {
        Intent intent = new Intent();
        intent.setClassName("com.termux.x11", "com.termux.x11.MainActivity");
        intent.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT);
        try {
            startActivity(intent);
            return true;
        } catch (RuntimeException error) {
            return false;
        }
    }

    private boolean openTermuxActivity() {
        try {
            Intent intent = getPackageManager().getLaunchIntentForPackage("com.termux");
            if (intent == null) {
                return false;
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT);
            startActivity(intent);
            return true;
        } catch (RuntimeException error) {
            return false;
        }
    }

    private void showNavigationGuidance() {
        new AlertDialog.Builder(this)
                .setTitle("Безопасная Android-навигация")
                .setMessage(
                        "Системные панели громкости и уведомлений принадлежат Android. Обычное приложение"
                                + " не может их отключить или перекрыть, и Fedora Shell их не изменяет.\n\n"
                                + "Нижний свайп Home/Overview и кнопки Back/Home остаются системными. В самом"
                                + " контроллере нижняя область не скрывается и не перехватывается.\n\n"
                                + "Для видимого рабочего стола откройте Termux:X11 → Preferences и оставьте"
                                + " ‘Fullscreen on device display’ выключенным. Иначе именно Termux:X11 может"
                                + " скрыть нижнюю область. Проект не меняет эту настройку автоматически.\n\n"
                                + "После этого: свайп снизу вверх — Home, свайп снизу вверх с удержанием — Overview,"
                                + " свайп от края — Back (если включена жестовая навигация Android).")
                .setPositiveButton("Открыть Termux:X11", (dialog, which) -> {
                    if (!openTermuxX11Activity()) {
                        setStatus("Termux:X11 недоступен; откройте совместимый APK вручную.");
                    }
                })
                .setNegativeButton("Закрыть", null)
                .show();
    }

    private void showKeyboardGuidance() {
        new AlertDialog.Builder(this)
                .setTitle("Клавиатура — только Linux Mode")
                .setMessage(
                        "В Linux Mode обычные аппаратные клавиши получает сфокусированная Activity"
                                + " Termux:X11, а затем их обрабатывает Fedora/Wayland/Mutter/GNOME."
                                + " Откройте Termux:X11, тапните по поверхности Fedora и только после этого"
                                + " вводите Ctrl/Alt/Super/F-клавиши или обычные сочетания. Контроллер Fedora"
                                + " сам не перехватывает клавиатуру: фактическая desktop-поверхность находится"
                                + " в Termux:X11.\n\n"
                                + "Защищённые глобальные клавиши Android остаются у Android SystemUI: Home, Back,"
                                + " громкость, шторка уведомлений, скриншоты, DeX и другие системные сочетания."
                                + " Обычное приложение не может безопасно украсть их у Android через публичный SDK"
                                + " и не должно ломать Android Mode.\n\n"
                                + "Для работающего нижнего свайпа оставьте в Termux:X11 параметр"
                                + " ‘Fullscreen on device display’ выключенным. Эта функция не меняет Android"
                                + " settings, keymap, IME, Accessibility, overlay или разрешения. Если сочетание"
                                + " ушло в Android, вернитесь в Termux:X11, снова тапните по Fedora и повторите.")
                .setPositiveButton("Открыть Termux:X11", (dialog, which) -> {
                    if (!openTermuxX11Activity()) {
                        setStatus("Termux:X11 недоступен; откройте совместимый APK вручную.");
                    }
                })
                .setNegativeButton("Закрыть", null)
                .show();
    }

    private String initialSetupChecklist() {
        return "Проверка (только чтение):\n"
                + "• Termux: " + installed("com.termux") + "\n"
                + "• Termux:X11: " + installed("com.termux.x11") + "\n"
                + "• Termux:API (не обязателен): " + installed("com.termux.api") + "\n"
                + "• Termux RUN_COMMAND: " + runCommandPermission() + "\n"
                + "• Fedora/PRoot: проверяется кнопкой диагностики\n"
                + "• Android ROLE_HOME: " + homeRoleStatus() + "\n"
                + "Home — необязательный выбор пользователя; One UI Home останется доступен.";
    }

    private String installed(String packageName) {
        try {
            getPackageManager().getPackageInfo(packageName, 0);
            return "установлен";
        } catch (PackageManager.NameNotFoundException error) {
            return "не найден";
        } catch (RuntimeException error) {
            return "неизвестно";
        }
    }

    private String runCommandPermission() {
        if (android.os.Build.VERSION.SDK_INT < 23) {
            return "не проверяется";
        }
        // RUN_COMMAND also depends on Termux's own allow-external-apps
        // preference. Avoid telling the user that Android Settings can grant
        // a permission which may be normal/signature-protected on a build.
        return checkSelfPermission("com.termux.permission.RUN_COMMAND")
                == PackageManager.PERMISSION_GRANTED
                ? "манифест разрешён; проверьте allow-external-apps"
                : "проверьте allow-external-apps в Termux";
    }

    private String homeRoleStatus() {
        if (android.os.Build.VERSION.SDK_INT < 29) {
            return "откройте Home app Settings";
        }
        try {
            RoleManager roleManager = getSystemService(RoleManager.class);
            if (roleManager == null || !roleManager.isRoleAvailable(RoleManager.ROLE_HOME)) {
                return "ROLE_HOME недоступен; используйте Home app Settings";
            }
            return roleManager.isRoleHeld(RoleManager.ROLE_HOME)
                    ? "Fedora Shell выбран как Home"
                    : "доступен, выбор только вручную";
        } catch (RuntimeException error) {
            return "не удалось проверить; используйте Home app Settings";
        }
    }

    /**
     * Ask Android's own role UI to offer ROLE_HOME. The app never assigns the
     * role silently and never disables or removes the existing launcher.
     */
    private void chooseHome() {
        if (android.os.Build.VERSION.SDK_INT >= 29) {
            try {
                RoleManager roleManager = getSystemService(RoleManager.class);
                if (roleManager != null && roleManager.isRoleAvailable(RoleManager.ROLE_HOME)
                        && !roleManager.isRoleHeld(RoleManager.ROLE_HOME)) {
                    startActivityForResult(
                            roleManager.createRequestRoleIntent(RoleManager.ROLE_HOME),
                            HOME_ROLE_REQUEST);
                    return;
                }
            } catch (RuntimeException ignored) {
                // Fall through to the public Home settings page.
            }
        }
        openSettings(Settings.ACTION_HOME_SETTINGS);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == HOME_ROLE_REQUEST) {
            setStatus(resultCode == RESULT_OK
                    ? "Fedora Shell выбран как Home пользователем. One UI Home не изменён."
                    : "Выбор Home отменён; Android/One UI остались без изменений.");
        }
    }

    private void openSettings(String action) {
        try {
            startActivity(new Intent(action));
        } catch (RuntimeException error) {
            startActivity(new Intent(Settings.ACTION_SETTINGS));
        }
    }

    private void maybeAutoResume() {
        if (!setupComplete || autoResumeAttempted || !launchedAsHome
                || !preferences().getBoolean(BootReceiver.AUTO_START, false)) {
            return;
        }
        if (!statusProbeComplete) {
            requestHomeStatus();
            return;
        }
        autoResumeAttempted = true;
        getWindow().getDecorView().postDelayed(this::startFedora, 700);
    }

    private boolean isHomeIntent(Intent intent) {
        return intent != null && intent.getCategories() != null
                && intent.getCategories().contains(Intent.CATEGORY_HOME);
    }

    /**
     * Handle the only external deep-link understood by the controller. This
     * is the Android-16 fallback for a Termux `am start` call that is rejected
     * because the caller is not the Android shell UID. The package name is
     * validated twice (here and in the Linux broker), then Android's own
     * PackageManager chooses the launcher activity. No package/settings/process
     * state is changed.
     */
    private boolean handleAndroidLaunchIntent(Intent intent) {
        if (intent == null || !Intent.ACTION_VIEW.equals(intent.getAction())) {
            return false;
        }
        Uri data = intent.getData();
        if (data == null || !"fedora-shell".equals(data.getScheme())
                || !"android".equals(data.getHost())
                || !"/launch".equals(data.getPath())) {
            return false;
        }
        String packageName;
        try {
            packageName = data.getQueryParameter("package");
        } catch (RuntimeException error) {
            setStatus("Некорректный Android launch URI; Android не изменялся.");
            return true;
        }
        if (!isValidAndroidPackage(packageName)) {
            setStatus("Некорректное имя Android package; Android не изменялся.");
            return true;
        }
        try {
            Intent launch = getPackageManager().getLaunchIntentForPackage(packageName);
            if (launch == null) {
                setStatus("Android package не имеет доступной launcher activity: " + packageName);
                return true;
            }
            launch.addFlags(Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
            startActivity(launch);
            // This controller is only the hand-off surface. Finish it after a
            // successful launch so Android Back reveals the still-running
            // Termux:X11/Fedora surface instead of exposing a second launcher
            // or an empty controller window. This changes no Android package,
            // setting, permission or process policy.
            finish();
        } catch (RuntimeException error) {
            setStatus("Android не разрешил запуск приложения: " + packageName);
        }
        return true;
    }

    private boolean isValidAndroidPackage(String packageName) {
        return packageName != null
                && packageName.matches("[a-zA-Z][a-zA-Z0-9_]*(\\.[a-zA-Z][a-zA-Z0-9_]*)+");
    }

    private void applyImmersiveMode() {
        Window window = getWindow();
        // Android SystemUI remains authoritative. Keep the bottom navigation /
        // mandatory-gesture region visible and unclaimed so Home, Back and
        // Overview continue to work. Only the persistent status bar is hidden
        // while this controller is focused; volume/notification overlays are
        // protected Android windows and remain available.
        window.setStatusBarColor(Color.TRANSPARENT);
        window.setNavigationBarColor(Color.TRANSPARENT);
        if (android.os.Build.VERSION.SDK_INT >= 29) {
            window.setStatusBarContrastEnforced(false);
            window.setNavigationBarContrastEnforced(false);
        }
        if (android.os.Build.VERSION.SDK_INT >= 30) {
            window.setDecorFitsSystemWindows(false);
            WindowInsetsController controller = window.getInsetsController();
            if (controller != null) {
                controller.hide(WindowInsets.Type.statusBars());
                controller.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
            }
        } else {
            window.getDecorView().setSystemUiVisibility(
                    View.SYSTEM_UI_FLAG_FULLSCREEN
                            | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                            | View.SYSTEM_UI_FLAG_LAYOUT_STABLE);
        }
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
