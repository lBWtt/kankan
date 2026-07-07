# 字体资源(需本地生成后放入此目录)

> **P2 接口留好,资源待投** —— 对应 `lib/core/fonts/font_family.dart`
> 已定义 `KkFonts.title` / `KkFonts.mono` + `fontFamilyFallback` 回退链,
> `pubspec.yaml` 默认注释掉 `fonts:` 段,即使本目录为空 app 也能跑
> (Flutter 按回退链匹配系统已安装的同名字体)。要切到自托管子集,只需
> 按下方生成两个文件,然后取消 `pubspec.yaml` 末尾 `fonts:` 段注释。

## 为什么必须自托管子集化

HANDOFF §5 铁律:
- 标题字:Noto Serif SC(衬线,**必须含中文子集**)
- Web 版踩过坑:Google Fonts `subsets:['latin']` 不含中文,标题回退成系统 sans
- Flutter 端:**自托管子集化文件**,不依赖运行时拉取

## 需要的文件(精确文件名)

pubspec.yaml `fonts:` 段引用的就是这两个文件名,**大小写、连字符都要对上**:

| 文件名(精确) | 来源 | 大小 |
|---|---|---|
| `NotoSerifSC-Subset.ttf` | Noto Serif SC 子集化(见下) | ~1.5–3 MB |
| `JetBrainsMono-Regular.ttf` | [JetBrains Mono GitHub releases](https://github.com/JetBrains/JetBrainsMono/releases) — zip 内 `fonts/ttf/JetBrainsMono-Regular.ttf` | ~200 KB |

## 下载源字体

```bash
# Noto Serif SC(原版 OTF,~16MB)
#   https://github.com/notofonts/noto-cjk/releases
#   找最新 NotoSerifSC 或 "03_NotoSerifCJK*" 资源包,提取 Regular.otf

# JetBrains Mono
#   https://github.com/JetBrains/JetBrainsMono/releases
#   下载 JetBrainsMono-x.x.x.zip,解压取 fonts/ttf/JetBrainsMono-Regular.ttf
```

## 一键子集化(推荐)

```bash
# 前置:pip install fonttools brotli
./subset.sh /path/to/NotoSerifSC-Regular.otf
# 产出:NotoSerifSC-Subset.ttf → 放入本目录
```

## 手动子集化

### 宽模式:CJK 全量 + 标点 + ASCII(~20k 字 → ~3MB)

```bash
pyftsubset NotoSerifSC-Regular.otf \
  --unicodes="U+4E00-9FFF,U+3000-303F,U+FF00-FFEF,U+2000-206F,U+0020-007E" \
  --output-file=NotoSerifSC-Subset.ttf \
  --no-hinting \
  --desubroutinize \
  --drop-tables+=DSIG
```

- `U+4E00-9FFF`:CJK 统一汉字(全部 ~20k 字)
- `U+3000-303F`:CJK 标点
- `U+FF00-FFEF`:全角符号
- `U+2000-206F`:通用标点
- `U+0020-007E`:ASCII

### 精简到 3500 常用字(~1.5MB,生产推荐)

准备 `common-3500.txt`(通用规范汉字表一级字,3500 字,一行一字),改用:

```bash
pyftsubset NotoSerifSC-Regular.otf \
  --text-file=common-3500.txt \
  --output-file=NotoSerifSC-Subset.ttf \
  --no-hinting \
  --desubroutinize
```

`common-3500.txt` 可从 https://github.com/JaidedAI/EasyOCR 或类似仓库获取,
或用 Python 从 `unicodedata` 生成 GB2312 一级字。

## 放好后

1. 把两个 `.ttf` 放入本目录(`assets/fonts/NotoSerifSC-Subset.ttf`、
   `assets/fonts/JetBrainsMono-Regular.ttf`)。
2. 编辑 `pubspec.yaml`,取消文件末尾 `fonts:` 段注释(P2-FONTS 标记下方):
   ```yaml
   fonts:
     - family: NotoSerifSC
       fonts:
         - asset: assets/fonts/NotoSerifSC-Subset.ttf
     - family: JetBrainsMono
       fonts:
         - asset: assets/fonts/JetBrainsMono-Regular.ttf
   ```
3. `flutter pub get && flutter run`

字体资源 *必须* 先放好再取消注释,否则 `flutter pub get` 会因缺文件报错。

## 不放字体的降级行为(P2 默认状态)

`pubspec.yaml` 默认注释掉 `fonts:` 段。此时 `ThemeData` / `KkType` /
各 widget 里写的 `fontFamily: 'NotoSerifSC'`(`= KkFonts.title`)找不到
声明 family,Flutter 按 `fontFamilyFallback` 链(`KkFonts.titleFallback`)匹配:

- `Noto Serif SC` → 用户系统若已装(开发者机常见),直接命中
- `Source Han Serif SC` → 思源宋体
- `Songti SC` → macOS / iOS 宋体
- `serif` → Flutter 内置 generic family 兜底

等宽同理(`KkFonts.monoFallback`:`JetBrains Mono` → `Roboto Mono` →
`Droid Sans Mono` → `monospace`)。

中文正常显示,只是不是自托管子集。这是 P2 的有意降级,不是 bug——
让 app 放下就能跑,不等字体子集化("接口留好就行")。

## 注意

- **不要把 `.ttf` 文件 commit 进 git**(二进制大文件,污染历史)。
  本目录建议加 `.gitignore` 排除 `*.ttf`(只跟踪 README.md / subset.sh)。
- 子集化是离线一次性操作,产物放本地或 CDN,不入库。
