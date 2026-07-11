# 分类字样对照（前后端三套）

> 用途：对齐「兴趣设置 / 筛选」时参考。当前三套不同源，前端筛选/兴趣与后端对不上。
> 说明：后端两套**代码里没有中文标签**（前端从不直接显示它们），下方中文是注解，非代码原文。

---

## ① 后端 `CATEGORY`（用途 · 单选 · 12 个）
- 位置：`backend/app/models/enums.py` → `CATEGORY`
- 谁在用：`GET /projects?category=` 真筛（`services/projects.py:91`）；AI 管线 `ai_processor` 填它。

| 值 | 注解（非代码） |
|---|---|
| `fun_ideas` | 趣味点子 |
| `image_design` | 图像设计 |
| `video_music` | 视频音乐 |
| `life_utility` | 生活工具 |
| `work_efficiency` | 工作效率 |
| `learning_growth` | 学习成长 |
| `business_ideas` | 商业点子 |
| `automation_tools` | 自动化工具 |
| `creator_tools` | 创作者工具 |
| `ai_apps` | AI 应用 |
| `weird_fun` | 奇趣好玩 |
| `future_cases` | 未来案例 |

---

## ② 后端 `DOMAIN`（职业/行业 · 多选 · 10 个）
- 位置：`backend/app/models/enums.py` → `DOMAIN`
- 谁在用：`project.domains`（项目多选）+ `user.interests`（用户兴趣，CHECK 约束限定取值）；`GET /projects?domain=` 真筛（`services/projects.py:89`）。

| 值 | 注解（非代码） |
|---|---|
| `dev` | 开发 |
| `design` | 设计 |
| `video` | 视频 |
| `marketing` | 营销 |
| `writing` | 写作 |
| `education` | 教育 |
| `ecommerce` | 电商 |
| `office` | 办公 |
| `cad_3d` | 3D/CAD |
| `other` | 其他 |

---

## ③ 前端 content-type（`Project.domain` · 7 个）
- 位置：`frontend/lib/features/kankan/kankan_screen.dart`（筛选 chip）、`features/me/me_screen.dart:374`（我关注的领域标签）
- 谁在用：kankan 筛选 chip + me 页「我关注的领域」；`_domainPattern`/`_domainIcon` 挑封面图案与图标。**这套标签是代码里的真标签。**

| 值 | 标签（代码原文） |
|---|---|
| `ai_image` | AI图 |
| `ai_video` | AI视频 |
| `web` | 网页 |
| `app` | App |
| `tool` | 工具 |
| `opensource` | 开源 |
| `prompt` | Prompt |

---

## 现在怎么（没）连上
- **展示桥**：DTO `_mapDomain(category)` 把后端 `CATEGORY` → 前端 content-type（尽力映射、兜底 `tool`），**只为挑封面图案/图标**（`data/dto/project_card_dto.dart:56`）。
- **兴趣断裂**：前端兴趣用 content-type（`ai_image`…），后端 `/interests` 的 CHECK 只认 `DOMAIN`（`dev/design`…），直接发 **422**，所以 `me_api` 里注释「interests 暂不接」。
- **筛选断裂**：前端 content-type 筛选是本地/装饰，没走后端 `category`/`domain` 真筛。

## 两个对齐方向（择一）
- **修正版 ①（零后端改动，推荐）**：前端改用后端已有两套 —— 兴趣接 `DOMAIN`（职业）、kankan 筛选接 `CATEGORY`（用途，真走 `GET /projects?category=`）；前端 content-type 降级为纯装饰。代价：筛选/兴趣词表从「内容类型」变「用途/职业」。
- **②（后端立新轴）**：后端新增 `content_type`（= 前端那 7 个），project + interests 都对它，前端语义（AI图/Prompt）保留。代价：后端迁移 + AI 管线多推断一个轴 + 与现有 `CATEGORY`/`DOMAIN` 三轴并存。
