package com.woaoaao.html;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Bundle;
import android.view.View;
import android.view.ViewGroup;
import android.widget.AdapterView;
import android.widget.BaseAdapter;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;

/** 主页：文件列表 + 导入（系统选择器 / 剪贴板 / 其它 App 分享） */
public class MainActivity extends Activity {

    private static final int REQUEST_IMPORT = 1001;

    private ListView listView;
    private TextView emptyView;
    private Ui.Shell shell;
    private final List<Store.Item> items = new ArrayList<Store.Item>();
    private boolean favoritesOnly = false;
    private FileAdapter adapter;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        favoritesOnly = getIntent().getBooleanExtra("favorites", false);

        shell = Ui.build(this, favoritesOnly ? "收藏夹" : "爱豆",
                new Ui.MenuProvider() {
                    @Override
                    public String[] items() {
                        return new String[]{
                                "导入文件",
                                "从剪贴板新建",
                                "刷新",
                                favoritesOnly ? "全部文件" : "收藏夹",
                                "设置"
                        };
                    }
                },
                new Ui.MenuHandler() {
                    @Override
                    public void onSelected(int index) {
                        handleMenu(index);
                    }
                });

        FrameLayout contentBox = new FrameLayout(this);
        shell.content.addView(contentBox, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        listView = new ListView(this);
        listView.setDividerHeight(1);
        contentBox.addView(listView, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        emptyView = new TextView(this);
        emptyView.setText("还没有 HTML 文件\n点右上角「⋮」→ 导入文件\n也可以从其它 App 分享 html 给「爱豆」");
        emptyView.setTextColor(Color.GRAY);
        emptyView.setTextSize(14);
        emptyView.setGravity(android.view.Gravity.CENTER);
        emptyView.setPadding(48, 32, 48, 32);
        emptyView.setVisibility(View.GONE);
        contentBox.addView(emptyView, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        adapter = new FileAdapter();
        listView.setAdapter(adapter);
        listView.setOnItemClickListener(new AdapterView.OnItemClickListener() {
            @Override
            public void onItemClick(AdapterView<?> parent, View view, int position, long id) {
                Store.Item item = items.get(position);
                Intent intent = new Intent(MainActivity.this, ViewerActivity.class);
                intent.putExtra("path", item.file.getAbsolutePath());
                startActivity(intent);
            }
        });
        listView.setOnItemLongClickListener(new AdapterView.OnItemLongClickListener() {
            @Override
            public boolean onItemLongClick(AdapterView<?> parent, View view, int position, long id) {
                showItemMenu(items.get(position));
                return true;
            }
        });
    }

    private void handleMenu(int index) {
        switch (index) {
            case 0:
                pickFile();
                break;
            case 1:
                newFromClipboard();
                break;
            case 2:
                reload();
                Toast.makeText(this, "已刷新", Toast.LENGTH_SHORT).show();
                break;
            case 3: {
                Intent intent = new Intent(this, MainActivity.class);
                intent.putExtra("favorites", !favoritesOnly);
                startActivity(intent);
                finish();
                break;
            }
            case 4:
                startActivity(new Intent(this, SettingsActivity.class));
                break;
            default:
                break;
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        reload();
        handleIncomingIntent(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handleIncomingIntent(intent);
    }

    private void reload() {
        items.clear();
        List<Store.Item> all = Store.list(this);
        for (Store.Item item : all) {
            if (!favoritesOnly || item.favorite) {
                items.add(item);
            }
        }
        adapter.notifyDataSetChanged();
        boolean empty = items.isEmpty();
        emptyView.setVisibility(empty ? View.VISIBLE : View.GONE);
        listView.setVisibility(empty ? View.GONE : View.VISIBLE);
    }

    // ---------------- 导入 ----------------

    private void pickFile() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        try {
            startActivityForResult(intent, REQUEST_IMPORT);
        } catch (Exception e) {
            Toast.makeText(this, "没有可用的文件选择器", Toast.LENGTH_LONG).show();
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_IMPORT && resultCode == RESULT_OK && data != null) {
            Uri uri = data.getData();
            if (uri != null) {
                importUri(uri);
            }
        }
    }

    private void importUri(Uri uri) {
        try {
            InputStream input = getContentResolver().openInputStream(uri);
            String name = queryName(uri);
            Store.importStream(this, input, name);
            reload();
            Toast.makeText(this, "已导入 " + name, Toast.LENGTH_SHORT).show();
        } catch (Exception e) {
            Toast.makeText(this, "导入失败：" + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private String queryName(Uri uri) {
        String name = uri.getLastPathSegment();
        if (name == null || name.length() == 0) {
            name = "导入文件.html";
        }
        if (name.contains("/")) {
            name = name.substring(name.lastIndexOf('/') + 1);
        }
        if (name.contains(":")) {
            name = name.substring(name.lastIndexOf(':') + 1);
        }
        if (!name.contains(".")) {
            name = name + ".html";
        }
        return name;
    }

    private void newFromClipboard() {
        ClipboardManager manager = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        final String clipboard = manager != null && manager.hasPrimaryClip()
                && manager.getPrimaryClip() != null && manager.getPrimaryClip().getItemCount() > 0
                ? String.valueOf(manager.getPrimaryClip().getItemAt(0).getText())
                : "";

        final EditText nameField = new EditText(this);
        nameField.setHint("文件名，例如 index.html");
        nameField.setText("新建页面.html");

        new AlertDialog.Builder(this)
                .setTitle(clipboard.length() > 0 ? "从剪贴板新建" : "新建空白页面")
                .setView(nameField)
                .setPositiveButton("创建", new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        String name = nameField.getText().toString().trim();
                        if (name.length() == 0) {
                            name = "新建页面.html";
                        }
                        String content = clipboard.length() > 0 ? clipboard
                                : "<!DOCTYPE html>\n<html lang=\"zh-CN\">\n<head><meta charset=\"utf-8\">"
                                + "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
                                + "<title>新页面</title></head>\n<body>\n  <h1>新页面</h1>\n</body>\n</html>\n";
                        try {
                            Store.createFile(MainActivity.this, name, content);
                            reload();
                            Toast.makeText(MainActivity.this, "已创建 " + name, Toast.LENGTH_SHORT).show();
                        } catch (Exception e) {
                            Toast.makeText(MainActivity.this, "创建失败：" + e.getMessage(), Toast.LENGTH_LONG).show();
                        }
                    }
                })
                .setNegativeButton("取消", null)
                .show();
    }

    private void handleIncomingIntent(Intent intent) {
        if (intent == null) {
            return;
        }
        String action = intent.getAction();
        if (Intent.ACTION_SEND.equals(action)) {
            Uri stream = intent.getParcelableExtra(Intent.EXTRA_STREAM);
            if (stream != null) {
                importUri(stream);
                intent.setAction(null);
                return;
            }
            CharSequence text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT);
            if (text != null) {
                try {
                    Store.createFile(this, "分享的内容.html", text.toString());
                    reload();
                    Toast.makeText(this, "已保存分享的内容", Toast.LENGTH_SHORT).show();
                } catch (Exception ignored) {
                }
                intent.setAction(null);
            }
        } else if (Intent.ACTION_VIEW.equals(action)) {
            Uri data = intent.getData();
            if (data != null) {
                importUri(data);
                intent.setAction(null);
            }
        }
    }

    private void showItemMenu(final Store.Item item) {
        final String[] options = new String[]{
                item.favorite ? "取消收藏" : "收藏",
                "删除"
        };
        new AlertDialog.Builder(this)
                .setTitle(item.name)
                .setItems(options, new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        if (which == 0) {
                            Store.toggleFavorite(MainActivity.this, item.rel);
                            reload();
                        } else if (which == 1) {
                            new AlertDialog.Builder(MainActivity.this)
                                    .setTitle("删除 " + item.name + "？")
                                    .setMessage("文件会从 App 目录里删掉，无法恢复。")
                                    .setPositiveButton("删除", new DialogInterface.OnClickListener() {
                                        @Override
                                        public void onClick(DialogInterface d, int w) {
                                            item.file.delete();
                                            reload();
                                        }
                                    })
                                    .setNegativeButton("取消", null)
                                    .show();
                        }
                    }
                })
                .show();
    }

    // ---------------- 列表 ----------------

    private class FileAdapter extends BaseAdapter {

        @Override
        public int getCount() {
            return items.size();
        }

        @Override
        public Object getItem(int position) {
            return items.get(position);
        }

        @Override
        public long getItemId(int position) {
            return position;
        }

        @Override
        public View getView(int position, View convertView, ViewGroup parent) {
            LinearLayout row;
            ViewHolder holder;
            if (convertView == null) {
                row = new LinearLayout(MainActivity.this);
                row.setOrientation(LinearLayout.HORIZONTAL);
                row.setPadding(Ui.dp(MainActivity.this, 20), Ui.dp(MainActivity.this, 14),
                        Ui.dp(MainActivity.this, 20), Ui.dp(MainActivity.this, 14));
                row.setGravity(android.view.Gravity.CENTER_VERTICAL);

                ImageView icon = new ImageView(MainActivity.this);
                icon.setImageResource(R.drawable.ic_doc);
                row.addView(icon, new LinearLayout.LayoutParams(
                        Ui.dp(MainActivity.this, 28), Ui.dp(MainActivity.this, 28)));

                LinearLayout texts = new LinearLayout(MainActivity.this);
                texts.setOrientation(LinearLayout.VERTICAL);
                texts.setPadding(Ui.dp(MainActivity.this, 14), 0, 0, 0);
                row.addView(texts, new LinearLayout.LayoutParams(0,
                        ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

                TextView name = new TextView(MainActivity.this);
                name.setTextSize(16);
                name.setTextColor(Color.parseColor("#1A1A1A"));
                name.setTypeface(Typeface.DEFAULT_BOLD);
                texts.addView(name);

                TextView meta = new TextView(MainActivity.this);
                meta.setTextSize(12);
                meta.setTextColor(Color.parseColor("#888888"));
                meta.setPadding(0, Ui.dp(MainActivity.this, 3), 0, 0);
                texts.addView(meta);

                holder = new ViewHolder(name, meta);
                row.setTag(holder);
                convertView = row;
            } else {
                holder = (ViewHolder) convertView.getTag();
            }

            Store.Item item = items.get(position);
            holder.name.setText((item.favorite ? "★ " : "") + item.name);
            holder.meta.setText(Store.sizeText(item.size) + " · " + Store.dateText(item.modified));
            return convertView;
        }
    }

    private static class ViewHolder {
        final TextView name;
        final TextView meta;

        ViewHolder(TextView name, TextView meta) {
            this.name = name;
            this.meta = meta;
        }
    }
}
