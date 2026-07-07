import '../../domain/models/models.dart';

/// Mock seed — 全谱系覆盖。
///
/// HANDOFF §6.10 铁律:所有计数取真实值,**禁止 ×200 / ×8+30 编造公式**。
/// Web 版重灾区(activity 屏 ×200、topic 屏 ×8+30、me 屏 ×200)。Flutter 端从零做对。
///
/// 覆盖谱系(HANDOFF §4 验收要求每种 ≥ 2):
///   - ai_image  AI 图(2)
///   - ai_video  AI 视频(2)
///   - web       网页(2)
///   - app       App(2)
///   - tool      工具(2)
///   - opensource 开源(2)
///   - prompt    prompt(2)
///
/// 每个 Project 的 resultData + actions 组合验证 HANDOFF §2 可组合渲染:
///   - 多动作项目(App+开源+提示词+工作流)→ 四个动作一行一个并存
///   - 纯开源项目 → 只有 repo 卡 + 一个 go,**无珊瑚橙**
///   - 纯图片项目 → 视频在上、照片能左右滑
///   - take 真复制/真下载、go 真开外链、how 跳工作流

// ── 用户 ──
final mockUsers = <KkUser>[
  KkUser(
    id: 'me',
    name: '看看君',
    bio: '在看 AI 做的东西',
    avatar: null,
    followingIds: ['chen', 'lin', 'wang'],
    // F-37:重算双向关注。原 ['chen','lin'] 含 lin,但 lin.followingIds=['chen']
    // 不含 me → 反向不一致。以 followingIds 为准,me 的粉丝只有 chen(chen→me)。
    followerIds: ['chen'],
  ),
  KkUser(
    id: 'chen',
    name: '陈小匠',
    bio: '做工具的',
    // F-37:加 zhao, liu。原只有 ['me'],但 zhao.followerIds / liu.followerIds
    // 都含 chen,说明 chen 应关注 zhao 和 liu。补齐后双向自洽。
    followingIds: ['me', 'zhao', 'liu'],
    // F-37:删 liu。原含 liu,但 liu.followingIds=['wang'] 不含 chen → 反向不一致。
    // 以 followingIds 为准,chen 的粉丝 = 谁的 following 含 chen = [me,lin,wang,zhao]。
    followerIds: ['me', 'lin', 'wang', 'zhao'],
  ),
  KkUser(
    id: 'lin',
    name: '林设计',
    bio: 'AI 出图',
    followingIds: ['chen'],
    followerIds: ['me', 'wang'],
  ),
  KkUser(
    id: 'wang',
    name: '王老板',
    bio: '写代码也写文',
    followingIds: ['chen', 'lin'],
    // F-37:删 chen(chen.following 不含 wang),加 liu(liu.following 含 wang)。
    // 以 followingIds 为准重算:wang 的粉丝 = [me, liu]。
    followerIds: ['me', 'liu'],
  ),
  KkUser(
    id: 'zhao',
    name: '赵算法',
    bio: '开源贡献者',
    followingIds: ['chen'],
    // F-37:删 liu。原含 liu,但 liu.followingIds=['wang'] 不含 zhao → 反向不一致。
    // 以 followingIds 为准,zhao 的粉丝 = [chen](chen.following 含 zhao)。
    followerIds: ['chen'],
  ),
  KkUser(
    id: 'liu',
    name: '刘产品',
    bio: 'App 独立开发',
    followingIds: ['wang'],
    followerIds: ['chen'],
  ),
];

// ── 基准时间(写死,便于测试可重复)──
// 2025-12-01 10:00 UTC+8 = 2025-12-01 02:00 UTC
const _baseMs = 1833012000000;

int _ms(int daysAgo, [int hoursAgo = 0]) =>
    _baseMs - daysAgo * 86400000 - hoursAgo * 3600000;

// ── 项目(14 个,覆盖 7 谱系 × 2)──
final mockProjects = <Project>[
  // ── AI 图 ×2 ──
  Project(
    id: 'p_aiimg_1',
    title: '赛博朋克茶馆',
    summary: '用 Midjourney v6 做的赛博朋克中式茶馆系列',
    authorId: 'lin',
    domain: 'ai_image',
    resultData: const ResultData(
      media: [
        MediaItem(
          type: 'image',
          url: 'https://sfile.chatglm.cn/images-ppt/a5fb2321b9d5.png',
          alt: '赛博朋克茶馆 霓虹灯笼',
        ),
        MediaItem(
          type: 'image',
          url: 'https://picsum.photos/seed/cybertea2/800/1000',
          alt: '茶馆内景 全息菜单',
        ),
        MediaItem(
          type: 'image',
          url: 'https://picsum.photos/seed/cybertea3/800/1000',
          alt: '茶馆外街景',
        ),
      ],
    ),
    actions: const [
      TakeAction(
        source: '--style raw --ar 3:4 --v 6.1\n cyberpunk chinese tea house, neon lanterns, rain wet street, cinematic, volumetric lighting, intricate details, 8k',
        takeKind: 'copy',
        label: '提示词',
        hint: '粘进 Midjourney 就能跑',
      ),
      HowAction(ref: 'workflow_midjourney_v6'),
    ],
    tags: const ['midjourney', '赛博朋克', '中式'],
    authorNote: '试了 v6 和 v6.1 对比,v6.1 对中式建筑细节理解好很多, lantern 的光晕更自然。',
    likes: 234,
    commentCount: 12,
    takeawayCount: 89,
    createdAtMs: _ms(1, 2),
  ),
  Project(
    id: 'p_aiimg_2',
    title: '十二节气插画',
    summary: 'Stable Diffusion + ControlNet 做的二十四节气(半)',
    authorId: 'lin',
    domain: 'ai_image',
    resultData: const ResultData(
      media: [
        MediaItem(type: 'image', url: 'https://sfile.chatglm.cn/images-ppt/179c3d3b3d1b.jpg'),
        MediaItem(type: 'image', url: 'https://picsum.photos/seed/jieqi2/800/600'),
      ],
      io: IoBlock(
        input: 'masterpiece, traditional chinese painting, 24 solar terms, 立春, soft watercolor, flat composition',
        output: '一张水墨淡彩,柳枝抽芽,远山含黛。',
        model: 'SDXL + ControlNet Canny',
        lang: 'prompt',
      ),
    ),
    actions: const [
      TakeAction(
        source: 'masterpiece, traditional chinese painting, 24 solar terms, 立春, soft watercolor, flat composition --s 750 --steps 30',
        takeKind: 'copy',
        label: '提示词',
        hint: '粘进 SD Web UI 正向词框',
      ),
      HowAction(ref: 'workflow_sdxl_controlnet'),
    ],
    tags: const ['stable-diffusion', 'sdxl', 'controlnet', '节气'],
    authorNote: null, // 测试空作者的话 → detail 整块隐藏
    likes: 156,
    commentCount: 7,
    takeawayCount: 42,
    createdAtMs: _ms(3, 5),
  ),

  // ── AI 视频 ×2 ──
  Project(
    id: 'p_aivid_1',
    title: '城市黎明延时',
    summary: 'Runway Gen-3 生成的 8 秒城市黎明延时',
    authorId: 'wang',
    domain: 'ai_video',
    resultData: const ResultData(
      media: [
        MediaItem(
          type: 'video',
          url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
          poster: 'https://sfile.chatglm.cn/images-ppt/bfb88838ab60.jpeg',
          durationSec: 8,
          alt: '城市黎明延时',
        ),
      ],
    ),
    actions: const [
      HowAction(ref: 'workflow_runway_gen3'),
    ],
    tags: const ['runway', 'gen3', '延时'],
    authorNote: 'Gen-3 对镜头运动的控制比 Gen-2 好太多,这个 push-in 一气呵成。',
    likes: 412,
    commentCount: 23,
    takeawayCount: 0, // 无 take 动作
    createdAtMs: _ms(0, 6),
  ),
  Project(
    id: 'p_aivid_2',
    title: '水墨游鱼',
    summary: '可灵 AI 做的水墨风游鱼循环动画',
    authorId: 'lin',
    domain: 'ai_video',
    resultData: const ResultData(
      media: [
        MediaItem(
          type: 'video',
          url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
          poster: 'https://sfile.chatglm.cn/images-ppt/8540030f8ce1.jpg',
          durationSec: 5,
        ),
        MediaItem(type: 'image', url: 'https://picsum.photos/seed/inkfish_frame/800/450'),
      ],
    ),
    actions: const [
      TakeAction(
        source: 'https://example.com/fish_loop.mp4',
        takeKind: 'download',
        label: '动画文件',
        hint: '下载后可直接发短视频',
      ),
      HowAction(ref: 'workflow_kling'),
    ],
    tags: const ['可灵', '水墨', '循环'],
    authorNote: '水墨的晕染在视频里很难保持一致,试了 7 次才稳定。',
    likes: 289,
    commentCount: 15,
    takeawayCount: 67,
    createdAtMs: _ms(2),
  ),

  // ── 网页 ×2 ──
  Project(
    id: 'p_web_1',
    title: 'AI 工具导航站',
    summary: '收录 200+ AI 工具,按场景分类',
    authorId: 'wang',
    domain: 'web',
    resultData: const ResultData(
      media: [
        MediaItem(type: 'image', url: 'https://sfile.chatglm.cn/images-ppt/47a9a604f473.png', alt: '首页截图'),
        MediaItem(type: 'image', url: 'https://picsum.photos/seed/navweb2/1000/600', alt: '分类页截图'),
      ],
    ),
    actions: const [
      GoAction(url: 'https://example.com/ai-nav', label: '访问站点'),
      GoAction(url: 'https://github.com/wang/ai-nav', label: 'GitHub'),
    ],
    tags: const ['导航', 'ai工具', 'web'],
    authorNote: '做了半年,从 30 个工具收到现在 200+,欢迎提 PR 加新工具。',
    likes: 521,
    commentCount: 34,
    takeawayCount: 0,
    createdAtMs: _ms(5),
  ),
  Project(
    id: 'p_web_2',
    title: '个人作品集',
    summary: '用 Next.js + Framer Motion 做的个人作品集',
    authorId: 'chen',
    domain: 'web',
    resultData: const ResultData(
      media: [
        MediaItem(type: 'image', url: 'https://sfile.chatglm.cn/images-ppt/40c16eb70ea8.jpeg'),
      ],
    ),
    actions: const [
      GoAction(url: 'https://example.com/chen', label: '访问站点'),
    ],
    tags: const ['作品集', 'nextjs'],
    authorNote: null,
    likes: 78,
    commentCount: 4,
    takeawayCount: 0,
    createdAtMs: _ms(8, 3),
  ),

  // ── App ×2 ──
  Project(
    id: 'p_app_1',
    title: '极简记账',
    summary: '一个只做加法的记账 App,iOS / Android 双端',
    authorId: 'liu',
    domain: 'app',
    resultData: const ResultData(
      media: [
        MediaItem(type: 'image', url: 'https://sfile.chatglm.cn/images-ppt/2cb8926bbbea.png', alt: '主界面'),
        MediaItem(type: 'image', url: 'https://picsum.photos/seed/app_record2/600/1000', alt: '统计页'),
        MediaItem(type: 'image', url: 'https://picsum.photos/seed/app_record3/600/1000', alt: '设置页'),
      ],
    ),
    actions: const [
      GoAction(url: 'https://apps.apple.com/app/example', label: 'App Store'),
      GoAction(url: 'https://play.google.com/store/apps/details?id=com.example', label: 'Google Play'),
      HowAction(ref: 'workflow_flutter_app'),
    ],
    tags: const ['flutter', '记账', 'app'],
    authorNote: '做了 3 个月,核心思路是"只记加法"——所有支出都转化为"我要为这个工作多久"。',
    likes: 367,
    commentCount: 19,
    takeawayCount: 0,
    createdAtMs: _ms(4, 2),
  ),
  Project(
    id: 'p_app_2',
    title: '番茄钟 +',
    summary: '带白噪音和专注统计的番茄钟',
    authorId: 'liu',
    domain: 'app',
    resultData: const ResultData(
      media: [
        MediaItem(type: 'image', url: 'https://sfile.chatglm.cn/images-ppt/d9b8b7fca13d.jpeg'),
        MediaItem(type: 'image', url: 'https://picsum.photos/seed/pomodoro2/600/1000'),
      ],
    ),
    actions: const [
      GoAction(url: 'https://apps.apple.com/app/pomodoro', label: 'App Store'),
    ],
    tags: const ['ios', '番茄钟', '效率'],
    authorNote: null,
    likes: 134,
    commentCount: 8,
    takeawayCount: 0,
    createdAtMs: _ms(10),
  ),

  // ── 工具 ×2 ──
  Project(
    id: 'p_tool_1',
    title: '批量图片压缩脚本',
    summary: 'Python 脚本,递归压缩目录下所有图片',
    authorId: 'chen',
    domain: 'tool',
    resultData: const ResultData(
      media: [
        MediaItem(type: 'image', url: 'https://sfile.chatglm.cn/images-ppt/14c467b11f9e.png'),
      ],
      io: IoBlock(
        input: 'python compress.py ./photos --quality 85 --max-width 1920',
        output: '✓ 234 张图片已压缩\n  原始: 1.2 GB\n  压缩后: 187 MB\n  压缩比: 84%',
        lang: 'bash',
      ),
    ),
    actions: const [
      TakeAction(
        source: 'https://example.com/compress.py',
        takeKind: 'download',
        label: '脚本文件',
        hint: 'python 命令行直接跑',
      ),
      HowAction(ref: 'workflow_python_tool'),
    ],
    tags: const ['python', '图片', '脚本'],
    authorNote: '用 Pillow + tqdm,支持断点续传。我自己每周用一次清相册。',
    likes: 198,
    commentCount: 11,
    takeawayCount: 76,
    createdAtMs: _ms(6),
  ),
  Project(
    id: 'p_tool_2',
    title: 'Markdown 转 PDF CLI',
    summary: '命令行工具,Markdown 带 CSS 转 PDF',
    authorId: 'chen',
    domain: 'tool',
    resultData: const ResultData(
      media: [
        MediaItem(type: 'image', url: 'https://sfile.chatglm.cn/images-ppt/4eb33bec5485.png'),
      ],
      io: IoBlock(
        input: 'md2pdf report.md -o report.pdf --theme github',
        output: '✓ 生成 report.pdf (12 页, 340 KB)\n✓ 使用主题: github\n✓ 代码高亮: 已应用',
        lang: 'bash',
      ),
    ),
    actions: const [
      TakeAction(
        source: '# 安装\npip install md2pdf-cli\n\n# 使用\nmd2pdf input.md -o output.pdf --theme github\n\n# 主题列表\nmd2pdf --list-themes',
        takeKind: 'copy',
        label: '安装命令',
        hint: '终端粘贴即装好',
      ),
      GoAction(url: 'https://github.com/chen/md2pdf', label: 'GitHub'),
    ],
    tags: const ['cli', 'markdown', 'pdf'],
    authorNote: null,
    likes: 87,
    commentCount: 3,
    takeawayCount: 31,
    createdAtMs: _ms(12),
  ),

  // ── 开源 ×2(纯导流,无珊瑚橙验收项)──
  Project(
    id: 'p_repo_1',
    title: 'Flutter 贡献热力图组件',
    summary: '可定制 的 GitHub 风格热力图,86 cells',
    authorId: 'zhao',
    domain: 'opensource',
    resultData: const ResultData(
      media: [
        MediaItem(type: 'image', url: 'https://sfile.chatglm.cn/images-ppt/dbb5816557c3.jpg'),
      ],
      repo: RepoInfo(
        name: 'flutter_heatmap',
        fullName: 'zhao/flutter_heatmap',
        stars: 234,
        language: 'Dart',
        url: 'https://github.com/zhao/flutter_heatmap',
        description: 'A customizable GitHub-style heatmap widget for Flutter.',
      ),
    ),
    actions: const [
      GoAction(url: 'https://github.com/zhao/flutter_heatmap', label: 'GitHub'),
    ],
    tags: const ['flutter', 'widget', 'heatmap'],
    authorNote: '发了 2 周收到 234 star,欢迎提 issue。',
    likes: 89,
    commentCount: 5,
    takeawayCount: 0,
    repoStars: 234,
    createdAtMs: _ms(7),
  ),
  Project(
    id: 'p_repo_2',
    title: 'React Native 性能监控库',
    summary: '轻量级 RN 性能监控,FPS / 内存 / 启动耗时',
    authorId: 'zhao',
    domain: 'opensource',
    resultData: const ResultData(
      media: [
        MediaItem(type: 'image', url: 'https://sfile.chatglm.cn/images-ppt/4bdca2a67305.png'),
      ],
      repo: RepoInfo(
        name: 'rn-perf-monitor',
        fullName: 'zhao/rn-perf-monitor',
        stars: 412,
        language: 'TypeScript',
        url: 'https://github.com/zhao/rn-perf-monitor',
        description: 'Lightweight performance monitor for React Native apps.',
      ),
    ),
    actions: const [
      GoAction(url: 'https://github.com/zhao/rn-perf-monitor', label: 'GitHub'),
      HowAction(ref: 'workflow_rn_perf'),
    ],
    tags: const ['react-native', '性能', 'typescript'],
    authorNote: null,
    likes: 145,
    commentCount: 9,
    takeawayCount: 0,
    repoStars: 412,
    createdAtMs: _ms(15),
  ),

  // ── Prompt ×2 ──
  Project(
    id: 'p_prompt_1',
    title: 'GPT 代码评审提示词',
    summary: '让 GPT-4o 做 senior 级代码评审的系统提示词',
    authorId: 'wang',
    domain: 'prompt',
    resultData: const ResultData(
      media: [
        MediaItem(type: 'image', url: 'https://sfile.chatglm.cn/images-ppt/967e52879b04.jpg'),
      ],
      io: IoBlock(
        input: '你是一位资深代码评审。请评审以下代码,关注:\n1. 可读性\n2. 潜在 bug\n3. 性能\n4. 安全\n\n代码:\n```python\ndef add(a, b):\n    return a + b\n```',
        output: '## 评审结果\n\n### 可读性\n函数名 `add` 清晰,参数名 `a` `b` 过于简略,建议改为 `first` `second` 或更具语义的名字。\n\n### 潜在 bug\n未做类型检查,若传入字符串会触发字符串拼接而非数值加法。\n\n### 性能\n无问题。\n\n### 安全\n无问题。',
        model: 'GPT-4o',
      ),
    ),
    actions: const [
      TakeAction(
        source: '你是一位资深代码评审。请评审以下代码,关注:\n1. 可读性\n2. 潜在 bug\n3. 性能\n4. 安全\n\n请用 Markdown 输出,每项给出具体建议而非泛泛而谈。\n\n代码:\n```{lang}\n{code}\n```',
        takeKind: 'copy',
        label: '系统提示词',
        hint: '粘进 GPT 当系统提示词',
      ),
      HowAction(ref: 'workflow_gpt_review'),
    ],
    tags: const ['gpt', '代码评审', '提示词'],
    authorNote: '用了 3 个月迭代到这版,关键是"具体建议而非泛泛而谈"这句约束。',
    likes: 678,
    commentCount: 41,
    takeawayCount: 312,
    createdAtMs: _ms(2, 8),
  ),
  Project(
    id: 'p_prompt_2',
    title: 'Claude 写作助手提示词',
    summary: '让 Claude 帮你把口语化想法整理成结构化文章',
    authorId: 'wang',
    domain: 'prompt',
    resultData: const ResultData(
      media: [
        MediaItem(type: 'image', url: 'https://sfile.chatglm.cn/images-ppt/e733e22680f6.jpg'),
      ],
      io: IoBlock(
        input: '帮我把这段想法整理成文章:\n"今天用了 cursor 写代码 感觉 ai 补全比 copilot 好很多 特别是跨文件理解 但有时候它会乱改 我觉得关键是 review 它的 diff"',
        output: '# Cursor vs Copilot:跨文件理解是关键\n\n今天试用 Cursor 写代码,最直观的感受是 AI 补全比 Copilot 好很多,尤其是跨文件理解能力...\n\n## 优点\n- 跨文件上下文\n- ...\n\n## 注意点\n- review diff 是关键\n- ...',
        model: 'Claude 3.5 Sonnet',
      ),
    ),
    actions: const [
      TakeAction(
        source: '你是写作助手。请把用户的口语化想法整理成结构化 Markdown 文章:\n\n要求:\n- 保留原意\n- 补充合理结构(标题/小标题/列表)\n- 不添加未提及的事实\n- 输出直接是 Markdown,不要前言\n\n用户想法:\n{input}',
        takeKind: 'copy',
        label: '提示词',
        hint: '粘进 Claude 当系统提示词',
      ),
    ],
    tags: const ['claude', '写作', '提示词'],
    authorNote: null,
    likes: 234,
    commentCount: 12,
    takeawayCount: 98,
    createdAtMs: _ms(4, 4),
  ),
];

// ── 动态(轻)— 发现页 feed 用,8 条覆盖各领域 ──
final mockPosts = <Post>[
  Post(
    id: 'post_1',
    content: '今天发现 Midjourney v6.1 对中文提示词的理解比 v6 好太多了,之前要翻译成英文才出对图,现在直接中文也行。',
    authorId: 'lin',
    tags: const ['midjourney', 'v6'],
    quoteProjectId: 'p_aiimg_1',
    media: const [
      MediaItem(type: 'image', url: 'https://picsum.photos/seed/mj_v6_a/800/800'),
      MediaItem(type: 'image', url: 'https://picsum.photos/seed/mj_v6_b/800/800'),
      MediaItem(type: 'image', url: 'https://picsum.photos/seed/mj_v6_c/800/800'),
    ],
    likes: 45,
    commentCount: 3,
    createdAtMs: _ms(0, 1),
  ),
  Post(
    id: 'post_2',
    content: '用了半年 Cursor,最大的感悟是:AI 补全好的前提是你代码结构清晰。结构乱的项目,AI 越帮越忙。',
    authorId: 'wang',
    tags: const ['cursor', 'ai编程'],
    likes: 89,
    commentCount: 7,
    createdAtMs: _ms(1, 3),
  ),
  Post(
    id: 'post_3',
    content: 'Runway Gen-3 的 push-in 镜头太顺了。前 Gen-2 想做这种运镜得 keyframe 半天,现在一句 prompt 搞定。',
    authorId: 'wang',
    tags: const ['runway', 'gen3'],
    quoteProjectId: 'p_aivid_1',
    media: const [
      MediaItem(
        type: 'video',
        url: 'https://picsum.photos/seed/runway_g3_clip/1200/675',
        poster: 'https://picsum.photos/seed/runway_g3_poster/1200/675',
        durationSec: 12,
      ),
    ],
    likes: 67,
    commentCount: 4,
    createdAtMs: _ms(0, 4),
  ),
  Post(
    id: 'post_4',
    content: '今天看了极简记账的设计思路,"只记加法"这个切入点太妙了。所有支出转化为"我要为这个工作多久",瞬间不乱花钱了。',
    authorId: 'chen',
    tags: const ['产品设计', '记账'],
    quoteProjectId: 'p_app_1',
    likes: 34,
    commentCount: 2,
    createdAtMs: _ms(2, 2),
  ),
  Post(
    id: 'post_5',
    content: 'SDXL + ControlNet Canny 做节气系列,ControlNet 的强度调到 0.6 最稳定,再高线条僵硬,再低形跑偏。',
    authorId: 'lin',
    tags: const ['sdxl', 'controlnet', '参数'],
    quoteProjectId: 'p_aiimg_2',
    media: const [
      MediaItem(type: 'image', url: 'https://picsum.photos/seed/sdxl_canny_a/800/600'),
      MediaItem(type: 'image', url: 'https://picsum.photos/seed/sdxl_canny_b/800/600'),
    ],
    likes: 56,
    commentCount: 5,
    createdAtMs: _ms(3, 1),
  ),
  Post(
    id: 'post_6',
    content: '刚把 Flutter 贡献热力图组件的 star 破 200 了,2 周从 0 到 234。关键是在 reddit r/FlutterDev 发了篇真心的分享。',
    authorId: 'zhao',
    tags: const ['flutter', '开源', '增长'],
    quoteProjectId: 'p_repo_1',
    likes: 78,
    commentCount: 6,
    createdAtMs: _ms(1, 6),
  ),
  Post(
    id: 'post_7',
    content: '写代码评审提示词最关键的不是"你是专家"这种角色设定,而是"具体建议而非泛泛而谈"这种输出约束。后者直接决定质量。',
    authorId: 'wang',
    tags: const ['prompt', '心得'],
    quoteProjectId: 'p_prompt_1',
    likes: 102,
    commentCount: 11,
    createdAtMs: _ms(0, 8),
  ),
  Post(
    id: 'post_8',
    content: '今天试了把 Python 压缩脚本改成支持 WebP 输出,体积比 JPEG 再小 30%。WebP 在国内 CDN 兼容性已经没问题了。',
    authorId: 'chen',
    tags: const ['python', 'webp', '图片优化'],
    quoteProjectId: 'p_tool_1',
    media: const [
      MediaItem(type: 'image', url: 'https://picsum.photos/seed/webp_compare/1000/562'),
    ],
    likes: 41,
    commentCount: 3,
    createdAtMs: _ms(4, 2),
  ),
  Post(
    id: 'post_9',
    content: '没有引用项目,纯吐槽:现在 AI 出图工具太多了,每天一个新名字,学不动了。还是 Midjourney + SD 两个就够。',
    authorId: 'lin',
    tags: const ['吐槽'],
    likes: 23,
    commentCount: 1,
    createdAtMs: _ms(0, 2),
  ),
  Post(
    id: 'post_10',
    content: 'Claude 3.5 写作助手那个提示词,关键在"不添加未提及的事实"这句。AI 最爱脑补,这一句直接堵死幻觉。',
    authorId: 'wang',
    tags: const ['claude', '写作', 'prompt'],
    quoteProjectId: 'p_prompt_2',
    likes: 88,
    commentCount: 9,
    createdAtMs: _ms(2, 5),
  ),
];

// ── 评论(Project / Post 共用,统一 hostType + hostId)──
final mockComments = <Comment>[
  // p_aiimg_1 评论
  Comment(
    id: 'c_p_aiimg_1_1',
    hostType: 'project',
    hostId: 'p_aiimg_1',
    authorId: 'wang',
    content: 'v6.1 的光晕确实自然多了,请问 lantern 的 prompt 是直接写的还是用 --sref?',
    likes: 12,
    createdAtMs: _ms(1, 1),
    replies: [
      Comment(
        id: 'c_p_aiimg_1_1_r1',
        hostType: 'project',
        hostId: 'p_aiimg_1',
        authorId: 'lin',
        content: '直接写的,neon lanterns 关键词就够。--sref 风格太强会压掉赛博朋克味。',
        likes: 5,
        createdAtMs: _ms(1),
      ),
    ],
  ),
  Comment(
    id: 'c_p_aiimg_1_2',
    hostType: 'project',
    hostId: 'p_aiimg_1',
    authorId: 'chen',
    content: '求出一套手机壁纸尺寸的!',
    likes: 8,
    createdAtMs: _ms(0, 12),
  ),
  // p_aivid_1 评论
  Comment(
    id: 'c_p_aivid_1_1',
    hostType: 'project',
    hostId: 'p_aivid_1',
    authorId: 'lin',
    content: 'push-in 一气呵成,Gen-3 对运镜理解比 Gen-2 强太多。',
    likes: 15,
    createdAtMs: _ms(0, 3),
  ),
  // p_prompt_1 评论(热门)
  Comment(
    id: 'c_p_prompt_1_1',
    hostType: 'project',
    hostId: 'p_prompt_1',
    authorId: 'chen',
    content: '关键那句"具体建议而非泛泛而谈"我直接抄到自己的 prompt 里了,效果立竿见影。',
    likes: 34,
    createdAtMs: _ms(1, 4),
    replies: [
      Comment(
        id: 'c_p_prompt_1_1_r1',
        hostType: 'project',
        hostId: 'p_prompt_1',
        authorId: 'wang',
        content: '对,这句是 3 个月迭代出来的。早期没这句,GPT 老给"建议改善可读性"这种废话。',
        likes: 18,
        createdAtMs: _ms(1, 2),
      ),
    ],
  ),
  Comment(
    id: 'c_p_prompt_1_2',
    hostType: 'project',
    hostId: 'p_prompt_1',
    authorId: 'liu',
    content: '拿走去评审我的代码了,谢谢分享。',
    likes: 9,
    createdAtMs: _ms(0, 6),
  ),
  // post_2 评论(发现页动态评论)
  Comment(
    id: 'c_post_2_1',
    hostType: 'post',
    hostId: 'post_2',
    authorId: 'chen',
    content: '深有同感。结构乱的项目,Copilot 给的补全我都不敢用,得反复改。',
    likes: 12,
    createdAtMs: _ms(1, 1),
  ),
  Comment(
    id: 'c_post_2_2',
    hostType: 'post',
    hostId: 'post_2',
    authorId: 'lin',
    content: '所以 AI 编程的前提是先重构?',
    likes: 5,
    createdAtMs: _ms(0, 8),
    replies: [
      Comment(
        id: 'c_post_2_2_r1',
        hostType: 'post',
        hostId: 'post_2',
        authorId: 'wang',
        content: '不一定要先重构,但模块边界要清晰。函数职责单一,AI 才能给你对的东西。',
        likes: 8,
        createdAtMs: _ms(0, 4),
      ),
    ],
  ),
  // post_7 评论
  Comment(
    id: 'c_post_7_1',
    hostType: 'post',
    hostId: 'post_7',
    authorId: 'zhao',
    content: '"具体建议而非泛泛而谈"这句我直接收藏。所有 prompt 工程的心法都是这个:约束输出格式。',
    likes: 22,
    createdAtMs: _ms(0, 5),
  ),
];

// ── 我拿走的(HANDOFF §6.3 内容库)— mock 假设 me 已经拿走过 ──
// 按 文本/文件/链接 三档分类。计数 = mockSavedTakeaways.length(真实)。
final mockSavedTakeaways = <SavedTakeaway>[
  SavedTakeaway(
    id: 'st_p_aiimg_1_take_0',
    projectId: 'p_aiimg_1',
    projectTitle: '赛博朋克茶馆',
    domain: 'ai_image',
    kind: 'text',
    source: '--style raw --ar 3:4 --v 6.1\n cyberpunk chinese tea house, neon lanterns, rain wet street, cinematic, volumetric lighting, intricate details, 8k',
    label: '提示词',
    savedAtMs: _ms(0, 2),
  ),
  SavedTakeaway(
    id: 'st_p_prompt_1_take_0',
    projectId: 'p_prompt_1',
    projectTitle: 'GPT 代码评审提示词',
    domain: 'prompt',
    kind: 'text',
    source: '你是一位资深代码评审。请评审以下代码,关注:\n1. 可读性\n2. 潜在 bug\n3. 性能\n4. 安全\n\n请用 Markdown 输出,每项给出具体建议而非泛泛而谈。\n\n代码:\n```{lang}\n{code}\n```',
    label: '系统提示词',
    savedAtMs: _ms(0, 5),
  ),
  SavedTakeaway(
    id: 'st_p_prompt_2_take_0',
    projectId: 'p_prompt_2',
    projectTitle: 'Claude 写作助手提示词',
    domain: 'prompt',
    kind: 'text',
    source: '你是写作助手。请把用户的口语化想法整理成结构化 Markdown 文章:\n\n要求:\n- 保留原意\n- 补充合理结构(标题/小标题/列表)\n- 不添加未提及的事实\n- 输出直接是 Markdown,不要前言\n\n用户想法:\n{input}',
    label: '提示词',
    savedAtMs: _ms(1, 1),
  ),
  SavedTakeaway(
    id: 'st_p_tool_1_take_0',
    projectId: 'p_tool_1',
    projectTitle: '批量图片压缩脚本',
    domain: 'tool',
    kind: 'file',
    source: 'https://example.com/compress.py',
    label: '脚本文件',
    savedAtMs: _ms(2, 3),
  ),
  SavedTakeaway(
    id: 'st_p_aivid_2_take_0',
    projectId: 'p_aivid_2',
    projectTitle: '水墨游鱼',
    domain: 'ai_video',
    kind: 'file',
    source: 'https://example.com/fish_loop.mp4',
    label: '动画文件',
    savedAtMs: _ms(3, 4),
  ),
  SavedTakeaway(
    id: 'st_p_tool_2_go_1',
    projectId: 'p_tool_2',
    projectTitle: 'Markdown 转 PDF CLI',
    domain: 'tool',
    kind: 'link',
    source: 'https://github.com/chen/md2pdf',
    label: 'GitHub',
    savedAtMs: _ms(4, 1),
  ),
  SavedTakeaway(
    id: 'st_p_web_1_go_0',
    projectId: 'p_web_1',
    projectTitle: 'AI 工具导航站',
    domain: 'web',
    kind: 'link',
    source: 'https://example.com/ai-nav',
    label: '访问站点',
    savedAtMs: _ms(5, 2),
  ),
  SavedTakeaway(
    id: 'st_p_repo_1_go_0',
    projectId: 'p_repo_1',
    projectTitle: 'Flutter 贡献热力图组件',
    domain: 'opensource',
    kind: 'link',
    source: 'https://github.com/zhao/flutter_heatmap',
    label: 'GitHub',
    savedAtMs: _ms(6),
  ),
];

// ── 通知(5 类精准跳转,HANDOFF §6.8)──
// 真实场景:后端推送。这里 mock 一组覆盖 5 类 + 时间分布(今天/昨天/本周/更早)。
final mockNotifications = <NotificationItem>[
  // ── 今天 ──
  NotificationItem(
    id: 'n_1',
    type: 'like',
    actorId: 'chen',
    targetId: 'post_2',
    preview: null,
    createdAtMs: _ms(0, 1),
  ),
  NotificationItem(
    id: 'n_2',
    type: 'comment',
    actorId: 'lin',
    targetId: 'post_2',
    hostType: 'post',
    preview: '所以 AI 编程的前提是先重构?',
    createdAtMs: _ms(0, 2),
  ),
  NotificationItem(
    id: 'n_3',
    type: 'follow',
    actorId: 'zhao',
    targetId: 'zhao',
    preview: null,
    createdAtMs: _ms(0, 3),
  ),
  NotificationItem(
    id: 'n_4',
    type: 'favorite',
    actorId: 'liu',
    targetId: 'p_app_1',
    preview: null,
    createdAtMs: _ms(0, 5),
  ),
  // ── 昨天 ──
  NotificationItem(
    id: 'n_5',
    type: 'comment',
    actorId: 'wang',
    targetId: 'p_aiimg_1',
    hostType: 'project',
    preview: 'v6.1 的光晕确实自然多了,请问 lantern 的 prompt 是直接写的还是用 --sref?',
    createdAtMs: _ms(1, 2),
  ),
  NotificationItem(
    id: 'n_6',
    type: 'like',
    actorId: 'lin',
    targetId: 'post_7',
    preview: null,
    createdAtMs: _ms(1, 4),
  ),
  NotificationItem(
    id: 'n_7',
    type: 'system',
    actorId: null,
    targetId: null,
    preview: '版本 1.2.0 已发布,新增「我拿走的」内容库找回功能。',
    createdAtMs: _ms(1, 8),
  ),
  // ── 本周(3-6 天前)──
  NotificationItem(
    id: 'n_8',
    type: 'follow',
    actorId: 'liu',
    targetId: 'liu',
    preview: null,
    createdAtMs: _ms(3, 2),
  ),
  NotificationItem(
    id: 'n_9',
    type: 'favorite',
    actorId: 'chen',
    targetId: 'p_tool_1',
    preview: null,
    createdAtMs: _ms(4, 1),
  ),
  NotificationItem(
    id: 'n_10',
    type: 'comment',
    actorId: 'chen',
    targetId: 'p_prompt_1',
    hostType: 'project',
    preview: '关键那句"具体建议而非泛泛而谈"我直接抄到自己的 prompt 里了。',
    createdAtMs: _ms(5, 3),
  ),
  // ── 更早 ──
  NotificationItem(
    id: 'n_11',
    type: 'like',
    actorId: 'wang',
    targetId: 'post_10',
    preview: null,
    createdAtMs: _ms(9, 2),
  ),
  NotificationItem(
    id: 'n_12',
    type: 'system',
    actorId: null,
    targetId: null,
    preview: '欢迎使用「看看」。这里会显示点赞、评论、关注和系统通知。',
    createdAtMs: _ms(15),
  ),
];

// ── 贡献热力图签到数据(me 屏 + activity 屏用,HANDOFF §6.10 真实数据)──
// 任务⑯:182 cells(26 周 × 7 天)。每个值 = 当天贡献数(0/1/2/3/4 档)。
// 真实场景:Drift 表查 group by date。这里 mock 182 天的分布。
// 编造规则(非 ×N 公式,而是确定性 mock 数据):
//   - 周末贡献少(0-1)
//   - 周中贡献多(1-3)
//   - 个别高产日 4
// 用 _baseMs 反推 182 天的日期,生成稳定 mock。
final mockHeatmapCells = <HeatmapCell>[
  for (var i = 181; i >= 0; i--)
    HeatmapCell(
      // 第 i 天的 0 点(本地时区由 DateTime 处理)
      dateMs: _baseMs - i * 86400000,
      // 确定性 mock:i 是天数,用简单 hash 出 0-4 的档位。
      // 不是 ×N 编造,而是 mock 数据本身(真实场景从 DB 读)。
      level: _mockHeatLevel(i),
    ),
];

int _mockHeatLevel(int dayIndex) {
  // 周期性:每 7 天一组(周中高,周末低)
  final dow = (dayIndex + 4) % 7; // 偏移让 dayIndex=0 落在周一附近
  if (dow == 5 || dow == 6) return dayIndex % 5 == 0 ? 1 : 0; // 周末
  // 周中:用 dayIndex 哈希出 1-3,偶尔 4
  final h = (dayIndex * 31) % 7;
  if (h == 0) return 4;
  if (h <= 2) return 2;
  if (h <= 4) return 3;
  return 1;
}

/// 热力图单元(model 内嵌,无需 freezed —— 简单不可变值对象)。
class HeatmapCell {
  final int dateMs;
  final int level; // 0-4
  const HeatmapCell({required this.dateMs, required this.level});
}

// ── 浏览历史种子(me 屏 + 浏览历史页用)──
// 真实场景:Drift 表查最近 50 条。这里 mock 5 条(最近浏览)。
final mockBrowseHistory = <String>[
  'p_aiimg_1',
  'p_prompt_1',
  'p_aivid_1',
  'p_tool_1',
  'p_repo_1',
];

// ── 最近搜索词(search 屏用)──
// 真实场景:SharedPreferences 持久化。这里 mock 6 条。
final mockRecentSearches = <String>[
  'midjourney',
  'cursor',
  'flutter',
  'python',
  '记账',
  'controlnet',
];

// ── 便捷查找 ──
KkUser? findUser(String id) =>
    mockUsers.where((u) => u.id == id).firstOrNull;

Project? findProject(String id) =>
    mockProjects.where((p) => p.id == id).firstOrNull;

Post? findPost(String id) =>
    mockPosts.where((p) => p.id == id).firstOrNull;

List<Comment> commentsFor(String hostId) =>
    mockComments.where((c) => c.hostId == hostId).toList();

// ── Phase 3 Tier 3:话题聚合(真实 heat,HANDOFF §6.10 禁 ×8+30 编造)──
// heat = projectCount * 10 + postCount * 5 + totalLikes ÷ 100(三方加权)
// 真实场景:后端聚合;这里 mock 端启动时算一次,稳定可重复。
final mockTopics = _computeTopics();

class _TagStat {
  int projectCount = 0;
  int postCount = 0;
  int totalProjectLikes = 0;
  int totalPostLikes = 0;
}

List<Topic> _computeTopics() {
  final tagStats = <String, _TagStat>{};
  for (final p in mockProjects) {
    for (final t in p.tags) {
      final s = tagStats.putIfAbsent(t, () => _TagStat());
      s.projectCount++;
      s.totalProjectLikes += p.likes;
    }
  }
  for (final p in mockPosts) {
    for (final t in p.tags) {
      final s = tagStats.putIfAbsent(t, () => _TagStat());
      s.postCount++;
      s.totalPostLikes += p.likes;
    }
  }
  final list = tagStats.entries.map((e) {
    final s = e.value;
    final totalLikes = s.totalProjectLikes + s.totalPostLikes;
    final heat = s.projectCount * 10 + s.postCount * 5 + totalLikes ~/ 100;
    return Topic(
      tag: e.key,
      heat: heat,
      projectCount: s.projectCount,
      postCount: s.postCount,
      totalLikes: totalLikes,
    );
  }).toList();
  list.sort((a, b) => b.heat.compareTo(a.heat));
  return list;
}

// ── Phase 3 Tier 3:作者榜(按总获赞排序,HANDOFF §6.10 真实计数)──
// 真实场景:后端按时间窗口(周/月)聚合;这里 mock 端启动时算一次。
// rankChange 是 mock 确定性值(真实场景后端返回上期排名对比)。
final mockAuthorRanking = _computeAuthorRanking();

class AuthorRankingEntry {
  final String userId;
  final int totalLikes;
  final int projectCount;
  final int postCount;
  final int rank; // 1-based
  final int rankChange; // 较上期:0 持平 / +N 上升 / -N 下降(mock 确定性)

  const AuthorRankingEntry({
    required this.userId,
    required this.totalLikes,
    required this.projectCount,
    required this.postCount,
    required this.rank,
    required this.rankChange,
  });
}

class _AuthorStat {
  int projectCount = 0;
  int postCount = 0;
  int projectLikes = 0;
  int postLikes = 0;
}

List<AuthorRankingEntry> _computeAuthorRanking() {
  final stats = <String, _AuthorStat>{
    for (final u in mockUsers) u.id: _AuthorStat(),
  };
  for (final p in mockProjects) {
    final s = stats[p.authorId];
    if (s != null) {
      s.projectCount++;
      s.projectLikes += p.likes;
    }
  }
  for (final p in mockPosts) {
    final s = stats[p.authorId];
    if (s != null) {
      s.postCount++;
      s.postLikes += p.likes;
    }
  }
  final entries = stats.entries.toList()
    ..sort((a, b) {
      final la = a.value.projectLikes + a.value.postLikes;
      final lb = b.value.projectLikes + b.value.postLikes;
      return lb.compareTo(la);
    });
  return entries.asMap().entries.map((e) {
    final idx = e.key;
    final userId = e.value.key;
    final s = e.value.value;
    final totalLikes = s.projectLikes + s.postLikes;
    // rankChange 确定性 mock:hash(userId) 出 -3..+3(0 表示持平)
    final h = userId.hashCode.abs() % 7;
    final rankChange = h - 3;
    return AuthorRankingEntry(
      userId: userId,
      totalLikes: totalLikes,
      projectCount: s.projectCount,
      postCount: s.postCount,
      rank: idx + 1,
      rankChange: rankChange,
    );
  }).toList();
}

// ── Phase 3 Tier 3:项目榜 / 动态榜(直接复用 mockProjects/mockPosts 排序)──
// 不另存数据,在 ranking_screen 内用 repository.sorted('hot') 取真实排序。
// rankChange 由 mock 确定性 hash 出,与作者榜同套路。

/// 任务⑥ Part B:新上榜哨兵值。`mockProjectRankChange` / `mockPostRankChange`
/// 返回此值 → `_RankChangeChip` 显示「新锐」pill(mint 底 + teal 字,不用 coral)。
const kRankNewEntrySentinel = 999;

/// 任务⑥ Part B:新上榜项目 id 集合(1-2 个,标「新锐」)。
const mockNewProjectIds = <String>{
  'p_aivid_2', // 水墨游鱼
};

/// 任务⑥ Part B:新上榜动态 id 集合(1-2 个,标「新锐」)。
const mockNewPostIds = <String>{
  'post_7',
};

/// 项目榜排名变化(mock 确定性,稳定可重复)。
/// 返回 -3..+3,0 表示持平;新上榜返回 [kRankNewEntrySentinel](任务⑥ Part B)。
int mockProjectRankChange(String projectId) {
  if (mockNewProjectIds.contains(projectId)) return kRankNewEntrySentinel;
  final h = projectId.hashCode.abs() % 7;
  return h - 3;
}

/// 动态榜排名变化(mock 确定性,稳定可重复)。
/// 新上榜返回 [kRankNewEntrySentinel](任务⑥ Part B)。
int mockPostRankChange(String postId) {
  if (mockNewPostIds.contains(postId)) return kRankNewEntrySentinel;
  final h = postId.hashCode.abs() % 7;
  return h - 3;
}

// ── Phase 3 Tier 4:工作流展示数据(给 code_diff_block 接入用)──
// HANDOFF §2.2 how 动作:点「工作流」按钮应跳工作流展示页。
// Phase 4 真做工作流页;Tier 4 先在 detail 屏 inline 展示 before/after diff。
// mockWorkflows 按 HowAction.ref 索引,提供 title/before/after/language。
class MockWorkflow {
  final String ref;
  final String title;
  final String? before;
  final String after;
  final String language;

  /// 任务⑤:旧流程步骤(每步一句,如「录音」「听一遍记时间点」)。null → 不显流程对比块。
  final List<String>? oldFlow;

  /// 任务⑤:新流程步骤。null → 不显流程对比块。
  final List<String>? newFlow;

  /// 任务⑤:省下多少(如「每期省 ~3 小时」)。null → 不显省下 chip。
  final String? saved;

  const MockWorkflow({
    required this.ref,
    required this.title,
    this.before,
    required this.after,
    required this.language,
    this.oldFlow,
    this.newFlow,
    this.saved,
  });
}

final mockWorkflows = <MockWorkflow>[
  MockWorkflow(
    ref: 'workflow_midjourney_v6',
    title: 'Midjourney v6 出图工作流',
    before: '--v 5.2 cyberpunk tea house\n--ar 16:9',
    after: '--v 6.1 --style raw cyberpunk chinese tea house, neon lanterns, '
        'rain wet street, cinematic\n--ar 3:4 --stylize 250',
    language: 'bash',
  ),
  MockWorkflow(
    ref: 'workflow_sdxl_controlnet',
    title: 'SDXL + ControlNet 线稿上色',
    before: 'prompt: a girl, anime style\nsteps: 20, cfg: 7',
    after: 'prompt: a girl, anime style, detailed eyes, soft lighting\n'
        'steps: 30, cfg: 5.5\ncontrolnet: lineart (weight 0.8)',
    language: 'bash',
  ),
  MockWorkflow(
    ref: 'workflow_flutter_app',
    title: 'Flutter 状态管理迁移',
    before: '// setState 全屏刷新\nclass _PageState extends State {\n'
        '  int _count = 0;\n  void _inc() => setState(() => _count++);\n}',
    after: '// Riverpod 精准刷新\nfinal countProvider = NotifierProvider<...>(\n'
        '  () => CountNotifier(),\n);',
    language: 'dart',
  ),
  MockWorkflow(
    ref: 'workflow_python_tool',
    title: 'Python 批量压缩脚本',
    before: '# 单线程\nfor f in files:\n    compress(f)',
    after: '# 多进程并行\nfrom multiprocessing import Pool\n'
        'with Pool(8) as p:\n    p.map(compress, files)',
    language: 'python',
    // 任务⑤:旧→新流程叙事
    oldFlow: const ['单线程逐张压', '1000 张约 40 分钟', '中途卡住重来'],
    newFlow: const ['8 进程并行', '1000 张约 6 分钟', '断点续传'],
    saved: '每批省 ~30 分钟',
  ),
  MockWorkflow(
    ref: 'workflow_gpt_review',
    title: 'GPT 代码评审 prompt 调优',
    before: '你评审一下这段代码',
    after: '你是资深代码评审。请评审以下代码,关注:\n'
        '1. 可读性\n2. 潜在 bug\n3. 性能\n4. 安全\n'
        '用 Markdown 输出,每项给具体建议而非泛泛而谈。',
    language: 'markdown',
    // 任务⑤:旧→新流程叙事
    oldFlow: const ['一句话丢给它', '反复追问补充', '结果泛泛'],
    newFlow: const ['一条结构化 prompt', '四维度一次到位', '直接可用'],
    saved: '每次省 ~10 分钟',
  ),
  MockWorkflow(
    ref: 'workflow_rn_perf',
    title: 'React Native 列表性能优化',
    before: '<ScrollView>\n  {items.map(i => <Item key={i.id} />)}\n</ScrollView>',
    after: '<FlatList\n  data={items}\n  renderItem={({item}) => <Item item={item} />}\n'
        '  keyExtractor={i => i.id}\n  windowSize={5}\n  removeClippedSubviews\n/>',
    language: 'tsx',
  ),
  MockWorkflow(
    ref: 'workflow_runway_gen3',
    title: 'Runway Gen-3 视频生成',
    before: 'image + text prompt → 5s clip',
    after: 'image + text prompt + motion brush (区域运动控制)\n'
        '→ 10s clip, camera move: slow zoom',
    language: 'bash',
  ),
  MockWorkflow(
    ref: 'workflow_kling',
    title: 'Kling 视频工作流',
    before: 'single prompt → 5s',
    after: 'storyboard (3 keyframes) + per-frame prompt\n→ 15s 连贯叙事',
    language: 'bash',
    // 任务⑤:旧→新流程叙事(原型第二强「想做」钩子)
    oldFlow: const ['单条 prompt 出 5s', '手动拼接多段', '对轨调节奏'],
    newFlow: const ['storyboard 3 关键帧', '逐帧 prompt 出 15s 连贯', '一次成片'],
    saved: '一条片省 ~2 小时',
  ),
];

/// 按 ref 查工作流(给 detail 屏 how 动作展开用)。
MockWorkflow? findWorkflow(String ref) =>
    mockWorkflows.where((w) => w.ref == ref).firstOrNull;

// ── 任务③:我关注的领域 / 话题(me_screen 用)──
// KkUser 无 interests 字段(F-3 注释:Phase 5 加字段后接),me 屏先用 mock 演示。
// 领域值对齐 profile_edit._domainOptions 的 7 个标准值,kankan 屏也用同一套。
// 真实场景:Drift 表存 user.followed_domains;这里 mock 3 个(子集)。
final mockFollowedDomains = <String>[
  'ai_image',
  'tool',
  'prompt',
];

// 话题取自 mock 项目 / 动态里真实出现过的 tag(me 屏"我关注的话题"用)。
// 真实场景:Drift 表存 user.followed_tags;这里 mock 3 个真实 tag。
final mockFollowedTopics = <String>[
  'midjourney',
  'flutter',
  '记账',
];
