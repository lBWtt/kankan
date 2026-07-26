from datetime import date, datetime
from typing import List, Optional

from pydantic import BaseModel


class ActivityStats(BaseModel):
    publish_count: int
    received_like_count: int
    favorite_count: int


class ActivityDay(BaseModel):
    date: date
    count: int
    level: int


class ActivityEvent(BaseModel):
    type: str
    text: str
    created_at: datetime
    target_id: Optional[str] = None


class MyActivityResponse(BaseModel):
    stats: ActivityStats
    days: List[ActivityDay]
    events: List[ActivityEvent]
