# ============================================================
# 这个文件是干什么的：话题（hashtag）相关的响应 schema。
# 它对应产品里的什么功能：话题广场 / 今日话题横条 / 话题详情页（某个 #tag 下的项目+动态）。
# 话题不是一张表，而是对 projects.tools + posts.tags 的实时聚合（与前端同口径）。
# ============================================================
from typing import List

from pydantic import BaseModel

from app.schemas.post import PostOut
from app.schemas.project import ProjectCard


class TopicOut(BaseModel):
    """一个话题的聚合热度（与前端 Topic 模型对齐：tag/heat/projectCount/postCount/totalLikes）。
    heat = projectCount*10 + postCount*5 + totalLikes//100（真实聚合，非编造放大）。"""
    tag: str
    heat: int
    project_count: int
    post_count: int
    total_likes: int
    is_followed: bool = False


class TopicDetail(BaseModel):
    """话题详情：热度头 + 该 tag 下的项目卡片 + 动态。"""
    topic: TopicOut
    projects: List[ProjectCard]
    posts: List[PostOut]
