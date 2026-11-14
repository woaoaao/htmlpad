package com.woaoaao.html;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Bundle;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.view.ViewGroup;
import android.widget.AdapterView;
import android.widget.BaseAdapter;
import android.widget.EditText;
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
    private final List<Store.Item> items = new ArrayList<Store.Item>();
    private boolean favoritesOnly = false;
    private FileAdapter adapter;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        favoritesOnly = getIntent().getBooleanExtra("favorites", false);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.WHITE);

        listView = new ListView(this);
        LinearLayout.LayoutParams listParams =
                new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f);
        root.addView(listView, listParams);

        emptyView = new TextView(this);
        emptyView.setText("还没有 HTML 文件\n点右上角「⋮」→ 导入文件\n（也可以把文件放到 文件管理 → Android/data/com.woaoaao.html/files/HTML）");
        emptyView.setTextColor(Color.GRAY);
        emptyView.setTextSize(14);
        emptyView.setGravity(android.view.Gravity.CENTER);
        emptyView.setPadding(48, 32, 48, 32);
        emptyView.setVisibility(View.GONE);
        root.addView(emptyView, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 2f));

        setContentView(root);

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

        if (getActionBar() != null) {
            getActionBar().setTitle(favoritesOnly ? "收藏夹" : "爱豆");
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

    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        menu.add(0, 1, 0, "导入文件");
        menu.add(0, 2, 1, "从剪贴板新建");
        menu.add(0, 3, 2, "刷新");
        menu.add(0, 4, 3, favoritesOnly ? "全部文件" : "收藏夹");
        menu.add(0, 5, 4, "设置");
        return true;
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        switch (item.getItemId()) {
            case 1:
                pickFile();
                return true;
            case 2:
                newFromClipboard();
                return true;
            case 3:
                reload();
                Toast.makeText(this, "已刷新", Toast.LENGTH_SHORT).show();
                return true;
            case 4:
                Intent intent = new Intent(this, MainActivity.class);
                intent.putExtra("favorites", !favoritesOnly);
                startActivity(intent);
                finish();
                return true;
            case 5:
                startActivity(new Intent(this, SettingsActivity.class));
                return true;
            default:
                return super.onOptionsItemSelected(item);
        }
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
        intent.putExtra(Intent.EXTRA_MIME_TYPES, new String[]{"text/html", "text/plain", "text/*", "application/json"});
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
        if (clipboard.length() == 0) {
            Toast.makeText(this, "剪贴板里没有文本，将创建空白页面", Toast.LENGTH_SHORT).show();
        }

        new AlertDialog.Builder(this)
                .setTitle("从剪贴板新建")
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
                "重命名（暂不支持）",
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
                        } else if (which == 2) {
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
                row.setPadding(28, 18, 28, 18);
                row.setGravity(android.view.Gravity.CENTER_VERTICAL);

                ImageView icon = new ImageView(MainActivity.this);
                icon.setImageResource(R.drawable.ic_doc);
                row.addView(icon, new LinearLayout.LayoutParams(56, 56));

                LinearLayout texts = new LinearLayout(MainActivity.this);
                texts.setOrientation(LinearLayout.VERTICAL);
                texts.setPadding(20, 0, 0, 0);
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
                meta.setPadding(0, 4, 0, 0);
                texts.addView(meta);

                holder = new ViewHolder(name, meta);
                row.setTag(holder);
                convertView = row;
            } else {
                holder = (ViewHolder) convertView.getTag();
            }

            Store.Item item = items.get(position);
            String prefix = item.favorite ? "★ " : "";
            holder.name.setText(prefix + item.name);
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
