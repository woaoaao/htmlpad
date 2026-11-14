package com.woaoaao.html;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.DialogInterface;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.text.Editable;
import android.text.InputType;
import android.text.TextWatcher;
import android.view.View;
import android.view.ViewGroup;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.File;
import java.util.ArrayList;
import java.util.List;

/** 源码编辑器：编辑 + 查找替换 + 撤销重做 + 保存（二次确认） */
public class EditorActivity extends Activity {

    private EditText editor;
    private File file;
    private Ui.Shell shell;
    private boolean dirty;

    private final List<String> undoStack = new ArrayList<String>();
    private final List<String> redoStack = new ArrayList<String>();
    private String lastSnapshot;
    private final Handler handler = new Handler();
    private Runnable snapshotTask;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        String path = getIntent().getStringExtra("path");
        if (path == null) {
            finish();
            return;
        }
        file = new File(path);

        shell = Ui.build(this, "源代码",
                new Ui.MenuProvider() {
                    @Override
                    public String[] items() {
                        return new String[]{"保存", "查找替换", "撤销", "重做"};
                    }
                },
                new Ui.MenuHandler() {
                    @Override
                    public void onSelected(int index) {
                        handleMenu(index);
                    }
                });

        editor = new EditText(this);
        editor.setBackgroundColor(Color.WHITE);
        editor.setTextColor(Color.parseColor("#1A1A1A"));
        editor.setTypeface(Typeface.MONOSPACE);
        editor.setTextSize(13);
        editor.setGravity(android.view.Gravity.TOP | android.view.Gravity.START);
        editor.setPadding(Ui.dp(this, 14), Ui.dp(this, 12), Ui.dp(this, 14), Ui.dp(this, 20));
        editor.setHorizontallyScrolling(false);
        editor.setInputType(InputType.TYPE_CLASS_TEXT
                | InputType.TYPE_TEXT_FLAG_MULTI_LINE
                | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        editor.setText(Store.readText(file));
        lastSnapshot = editor.getText().toString();

        ScrollView scroll = new ScrollView(this);
        scroll.addView(editor, new ScrollView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        shell.content.addView(scroll, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        editor.addTextChangedListener(new TextWatcher() {
            @Override
            public void beforeTextChanged(CharSequence s, int start, int count, int after) {
            }

            @Override
            public void onTextChanged(CharSequence s, int start, int before, int count) {
            }

            @Override
            public void afterTextChanged(Editable s) {
                markDirty();
                scheduleSnapshot();
            }
        });
    }

    private void handleMenu(int index) {
        switch (index) {
            case 0:
                confirmSave();
                break;
            case 1:
                showFindReplace();
                break;
            case 2:
                undo();
                break;
            case 3:
                redo();
                break;
            default:
                break;
        }
    }

    private void markDirty() {
        if (dirty) {
            return;
        }
        dirty = true;
        shell.setTitle("源代码 ●");
    }

    private void scheduleSnapshot() {
        if (snapshotTask != null) {
            handler.removeCallbacks(snapshotTask);
        }
        snapshotTask = new Runnable() {
            @Override
            public void run() {
                String current = editor.getText().toString();
                pushUndo(lastSnapshot);
                lastSnapshot = current;
            }
        };
        handler.postDelayed(snapshotTask, 700);
    }

    private void pushUndo(String text) {
        if (text == null) {
            return;
        }
        if (!undoStack.isEmpty() && undoStack.get(undoStack.size() - 1).equals(text)) {
            return;
        }
        undoStack.add(text);
        while (undoStack.size() > 30) {
            undoStack.remove(0);
        }
        redoStack.clear();
    }

    private void applyText(String text) {
        if (snapshotTask != null) {
            handler.removeCallbacks(snapshotTask);
        }
        editor.setText(text);
        editor.setSelection(0);
        lastSnapshot = text;
        markDirty();
    }

    private void undo() {
        if (undoStack.isEmpty()) {
            Toast.makeText(this, "没有可撤销的步骤", Toast.LENGTH_SHORT).show();
            return;
        }
        String target = undoStack.remove(undoStack.size() - 1);
        redoStack.add(editor.getText().toString());
        applyText(target);
    }

    private void redo() {
        if (redoStack.isEmpty()) {
            Toast.makeText(this, "没有可重做的步骤", Toast.LENGTH_SHORT).show();
            return;
        }
        String target = redoStack.remove(redoStack.size() - 1);
        undoStack.add(editor.getText().toString());
        applyText(target);
    }

    private void confirmSave() {
        if (!dirty) {
            Toast.makeText(this, "没有改动", Toast.LENGTH_SHORT).show();
            return;
        }
        new AlertDialog.Builder(this)
                .setTitle("保存修改？")
                .setMessage("会直接覆盖原文件，无法撤销。")
                .setPositiveButton("保存", new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        save();
                    }
                })
                .setNegativeButton("取消", null)
                .show();
    }

    private void save() {
        String text = editor.getText().toString();
        if (Store.writeText(file, text)) {
            dirty = false;
            shell.setTitle("源代码");
            lastSnapshot = text;
            Toast.makeText(this, "已保存", Toast.LENGTH_SHORT).show();
        } else {
            Toast.makeText(this, "保存失败", Toast.LENGTH_LONG).show();
        }
    }

    // ---------------- 查找替换 ----------------

    private void showFindReplace() {
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(Ui.dp(this, 20), Ui.dp(this, 12), Ui.dp(this, 20), 0);

        final EditText findField = new EditText(this);
        findField.setHint("查找内容");
        findField.setSingleLine(true);
        layout.addView(findField);

        final EditText replaceField = new EditText(this);
        replaceField.setHint("替换为（留空=删除）");
        replaceField.setSingleLine(true);
        layout.addView(replaceField);

        final TextView countLabel = new TextView(this);
        countLabel.setTextSize(12);
        countLabel.setTextColor(Color.GRAY);
        countLabel.setPadding(0, Ui.dp(this, 6), 0, 0);
        layout.addView(countLabel);

        final AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle("查找替换")
                .setView(layout)
                .setPositiveButton("下一个", null)
                .setNeutralButton("替换", null)
                .setNegativeButton("全部替换", null)
                .create();

        dialog.setOnShowListener(new DialogInterface.OnShowListener() {
            @Override
            public void onShow(DialogInterface d) {
                dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(new View.OnClickListener() {
                    @Override
                    public void onClick(View v) {
                        findNext(findField.getText().toString(), countLabel);
                    }
                });
                dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener(new View.OnClickListener() {
                    @Override
                    public void onClick(View v) {
                        replaceCurrent(findField.getText().toString(),
                                replaceField.getText().toString(), countLabel);
                    }
                });
                dialog.getButton(AlertDialog.BUTTON_NEGATIVE).setOnClickListener(new View.OnClickListener() {
                    @Override
                    public void onClick(View v) {
                        replaceAll(findField.getText().toString(),
                                replaceField.getText().toString(), countLabel);
                    }
                });
            }
        });
        dialog.show();
    }

    private void findNext(String keyword, TextView label) {
        if (keyword.length() == 0) {
            return;
        }
        String text = editor.getText().toString();
        int from = editor.getSelectionEnd();
        if (from < 0 || from >= text.length()) {
            from = 0;
        }
        int index = text.toLowerCase().indexOf(keyword.toLowerCase(), from);
        if (index < 0) {
            index = text.toLowerCase().indexOf(keyword.toLowerCase(), 0);
        }
        if (index < 0) {
            label.setText("没有找到");
            return;
        }
        editor.setSelection(index, index + keyword.length());
        label.setText("已定位：第 " + (index + 1) + " 个字符");
    }

    private void replaceCurrent(String keyword, String replacement, TextView label) {
        if (keyword.length() == 0) {
            return;
        }
        int start = editor.getSelectionStart();
        int end = editor.getSelectionEnd();
        if (start < 0 || end < 0 || end > editor.getText().length()) {
            findNext(keyword, label);
            return;
        }
        String selected = editor.getText().toString().substring(start, end);
        if (!selected.equalsIgnoreCase(keyword)) {
            findNext(keyword, label);
            return;
        }
        pushUndo(editor.getText().toString());
        editor.getText().replace(start, end, replacement);
        label.setText("已替换 1 处");
        findNext(keyword, label);
    }

    private void replaceAll(String keyword, String replacement, TextView label) {
        if (keyword.length() == 0) {
            return;
        }
        String text = editor.getText().toString();
        String lowerText = text.toLowerCase();
        String lowerKeyword = keyword.toLowerCase();
        StringBuilder builder = new StringBuilder();
        int index = 0;
        int count = 0;
        while (true) {
            int found = lowerText.indexOf(lowerKeyword, index);
            if (found < 0) {
                builder.append(text.substring(index));
                break;
            }
            builder.append(text, index, found);
            builder.append(replacement);
            index = found + keyword.length();
            count++;
        }
        if (count == 0) {
            label.setText("没有可替换的内容");
            return;
        }
        pushUndo(text);
        applyText(builder.toString());
        label.setText("已替换 " + count + " 处");
    }

    @Override
    public void onBackPressed() {
        if (dirty) {
            new AlertDialog.Builder(this)
                    .setTitle("还有未保存的修改")
                    .setMessage("要保存后再离开吗？")
                    .setPositiveButton("保存并离开", new DialogInterface.OnClickListener() {
                        @Override
                        public void onClick(DialogInterface dialog, int which) {
                            save();
                            finish();
                        }
                    })
                    .setNeutralButton("不保存", new DialogInterface.OnClickListener() {
                        @Override
                        public void onClick(DialogInterface dialog, int which) {
                            finish();
                        }
                    })
                    .setNegativeButton("取消", null)
                    .show();
            return;
        }
        super.onBackPressed();
    }
}
