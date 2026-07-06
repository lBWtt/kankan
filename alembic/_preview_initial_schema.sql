BEGIN;

CREATE TABLE alembic_version (
    version_num VARCHAR(32) NOT NULL, 
    CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num)
);

-- Running upgrade  -> 0001

CREATE TYPE "project_status" AS ENUM ('draft', 'published', 'hidden', 'under_review', 'rejected', 'taken_down', 'deleted');

CREATE TYPE "candidate_status" AS ENUM ('ai_collected', 'ai_processed', 'pending_review', 'edited', 'approved', 'parked', 'discarded');

CREATE TYPE "category" AS ENUM ('fun_ideas', 'image_design', 'video_music', 'life_utility', 'work_efficiency', 'learning_growth', 'business_ideas', 'automation_tools', 'creator_tools', 'ai_apps', 'weird_fun', 'future_cases');

CREATE TYPE "content_source_type" AS ENUM ('ai_crawled', 'manual_import', 'user_original', 'user_discovery');

CREATE TYPE "reaction_type" AS ENUM ('creative', 'big_brain', 'cool');

CREATE TYPE "share_status" AS ENUM ('clicked', 'completed');

CREATE TYPE "share_channel" AS ENUM ('wechat', 'moments', 'x', 'xiaohongshu', 'copy_link', 'other');

CREATE TYPE "notification_type" AS ENUM ('daily_pick', 'weekly_ranking', 'how_to_interest', 'clue_update', 'similar_project', 'content_status', 'system', 'interaction');

CREATE TYPE "report_status" AS ENUM ('pending', 'processing', 'resolved', 'rejected');

CREATE TYPE "language" AS ENUM ('zh-CN', 'en-US');

CREATE TABLE users (
    id UUID DEFAULT gen_random_uuid() NOT NULL, 
    email VARCHAR(255), 
    phone VARCHAR(20), 
    nickname VARCHAR(50), 
    avatar_url TEXT, 
    bio VARCHAR(500), 
    language_preference language DEFAULT 'zh-CN' NOT NULL, 
    country_region VARCHAR(50), 
    interests TEXT[] DEFAULT '{}'::text[] NOT NULL, 
    role VARCHAR(20), 
    is_admin BOOLEAN DEFAULT false NOT NULL, 
    membership_tier VARCHAR(20), 
    membership_expires_at TIMESTAMP WITH TIME ZONE, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
    deleted_at TIMESTAMP WITH TIME ZONE, 
    CONSTRAINT pk_users PRIMARY KEY (id), 
    CONSTRAINT uq_users_email UNIQUE (email), 
    CONSTRAINT uq_users_phone UNIQUE (phone), 
    CONSTRAINT ck_users_role_allowed CHECK (role IS NULL OR role IN ('creator', 'developer', 'general')), 
    CONSTRAINT ck_users_interests_allowed CHECK (interests <@ ARRAY['dev', 'design', 'video', 'marketing', 'writing', 'education', 'ecommerce', 'office', 'cad_3d', 'other']::text[])
);

CREATE TABLE projects (
    id UUID DEFAULT gen_random_uuid() NOT NULL, 
    author_user_id UUID, 
    title VARCHAR(80) NOT NULL, 
    tagline VARCHAR(140) NOT NULL, 
    summary VARCHAR(500) NOT NULL, 
    description TEXT, 
    category category NOT NULL, 
    language language DEFAULT 'zh-CN' NOT NULL, 
    source_type content_source_type NOT NULL, 
    is_original BOOLEAN DEFAULT false NOT NULL, 
    source_url TEXT, 
    source_platform VARCHAR(50), 
    original_author_name VARCHAR(100), 
    original_author_url TEXT, 
    cover_media_url TEXT, 
    allow_how_to_interest BOOLEAN DEFAULT true NOT NULL, 
    service_enabled BOOLEAN DEFAULT false NOT NULL, 
    service_note TEXT, 
    tools TEXT[] DEFAULT '{}'::text[] NOT NULL, 
    domains TEXT[] DEFAULT '{}'::text[] NOT NULL, 
    ai_badge VARCHAR(20) DEFAULT 'none' NOT NULL, 
    ai_implementation_hint TEXT, 
    target_users TEXT[], 
    use_cases TEXT[], 
    featured_rank INTEGER, 
    status project_status DEFAULT 'draft' NOT NULL, 
    hot_score FLOAT DEFAULT 0 NOT NULL, 
    published_at TIMESTAMP WITH TIME ZONE, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
    deleted_at TIMESTAMP WITH TIME ZONE, 
    CONSTRAINT pk_projects PRIMARY KEY (id), 
    CONSTRAINT ck_projects_domains_allowed CHECK (domains <@ ARRAY['dev', 'design', 'video', 'marketing', 'writing', 'education', 'ecommerce', 'office', 'cad_3d', 'other']::text[]), 
    CONSTRAINT ck_projects_ai_badge_allowed CHECK (ai_badge IN ('worth_a_look', 'high_potential', 'staff_pick', 'none')), 
    CONSTRAINT fk_projects_author_user_id_users FOREIGN KEY(author_user_id) REFERENCES users (id)
);

CREATE INDEX ix_projects_status_published_at ON projects (status, published_at);

CREATE INDEX ix_projects_category_status ON projects (category, status);

CREATE INDEX ix_projects_hot_score ON projects (hot_score);

CREATE INDEX ix_projects_featured_rank ON projects (featured_rank);

CREATE INDEX ix_projects_domains_gin ON projects USING gin (domains);

CREATE INDEX ix_projects_tools_gin ON projects USING gin (tools);

CREATE INDEX ix_projects_fulltext ON projects USING gin (to_tsvector('simple', coalesce(title, '') || ' ' || coalesce(tagline, '')));

CREATE TABLE project_media (
    id UUID DEFAULT gen_random_uuid() NOT NULL, 
    project_id UUID NOT NULL, 
    media_type VARCHAR(20) NOT NULL, 
    url TEXT NOT NULL, 
    thumbnail_url TEXT, 
    sort_order INTEGER DEFAULT 0 NOT NULL, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
    CONSTRAINT pk_project_media PRIMARY KEY (id), 
    CONSTRAINT ck_project_media_media_type_allowed CHECK (media_type IN ('image', 'video')), 
    CONSTRAINT fk_project_media_project_id_projects FOREIGN KEY(project_id) REFERENCES projects (id)
);

CREATE INDEX ix_project_media_project_id ON project_media (project_id);

CREATE TABLE project_tags (
    id UUID DEFAULT gen_random_uuid() NOT NULL, 
    name VARCHAR(50) NOT NULL, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
    CONSTRAINT pk_project_tags PRIMARY KEY (id), 
    CONSTRAINT uq_project_tags_name UNIQUE (name)
);

CREATE TABLE project_tag_relations (
    id UUID DEFAULT gen_random_uuid() NOT NULL, 
    project_id UUID NOT NULL, 
    tag_id UUID NOT NULL, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
    CONSTRAINT pk_project_tag_relations PRIMARY KEY (id), 
    CONSTRAINT uq_project_tag_relations_project_tag UNIQUE (project_id, tag_id), 
    CONSTRAINT fk_project_tag_relations_project_id_projects FOREIGN KEY(project_id) REFERENCES projects (id), 
    CONSTRAINT fk_project_tag_relations_tag_id_project_tags FOREIGN KEY(tag_id) REFERENCES project_tags (id)
);

CREATE INDEX ix_project_tag_relations_tag_id ON project_tag_relations (tag_id);

CREATE TABLE favorites (
    id UUID DEFAULT gen_random_uuid() NOT NULL, 
    user_id UUID NOT NULL, 
    project_id UUID NOT NULL, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
    CONSTRAINT pk_favorites PRIMARY KEY (id), 
    CONSTRAINT uq_favorites_user_project UNIQUE (user_id, project_id), 
    CONSTRAINT fk_favorites_user_id_users FOREIGN KEY(user_id) REFERENCES users (id), 
    CONSTRAINT fk_favorites_project_id_projects FOREIGN KEY(project_id) REFERENCES projects (id)
);

CREATE INDEX ix_favorites_project_id ON favorites (project_id);

CREATE TABLE try_items (
    id UUID DEFAULT gen_random_uuid() NOT NULL, 
    user_id UUID NOT NULL, 
    project_id UUID NOT NULL, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
    CONSTRAINT pk_try_items PRIMARY KEY (id), 
    CONSTRAINT uq_try_items_user_project UNIQUE (user_id, project_id), 
    CONSTRAINT fk_try_items_user_id_users FOREIGN KEY(user_id) REFERENCES users (id), 
    CONSTRAINT fk_try_items_project_id_projects FOREIGN KEY(project_id) REFERENCES projects (id)
);

CREATE INDEX ix_try_items_project_id ON try_items (project_id);

CREATE TABLE how_to_interests (
    id UUID DEFAULT gen_random_uuid() NOT NULL, 
    user_id UUID, 
    anon_client_id VARCHAR(64), 
    project_id UUID NOT NULL, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
    CONSTRAINT pk_how_to_interests PRIMARY KEY (id), 
    CONSTRAINT ck_how_to_interests_identity_present CHECK (user_id IS NOT NULL OR anon_client_id IS NOT NULL), 
    CONSTRAINT fk_how_to_interests_user_id_users FOREIGN KEY(user_id) REFERENCES users (id), 
    CONSTRAINT fk_how_to_interests_project_id_projects FOREIGN KEY(project_id) REFERENCES projects (id)
);

CREATE UNIQUE INDEX uq_how_to_interests_user_project ON how_to_interests (user_id, project_id) WHERE user_id IS NOT NULL;

CREATE UNIQUE INDEX uq_how_to_interests_anon_project ON how_to_interests (anon_client_id, project_id) WHERE user_id IS NULL;

CREATE INDEX ix_how_to_interests_project_id ON how_to_interests (project_id);

CREATE TABLE clue_subscriptions (
    id UUID DEFAULT gen_random_uuid() NOT NULL, 
    user_id UUID NOT NULL, 
    project_id UUID NOT NULL, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
    CONSTRAINT pk_clue_subscriptions PRIMARY KEY (id), 
    CONSTRAINT uq_clue_subscriptions_user_project UNIQUE (user_id, project_id), 
    CONSTRAINT fk_clue_subscriptions_user_id_users FOREIGN KEY(user_id) REFERENCES users (id), 
    CONSTRAINT fk_clue_subscriptions_project_id_projects FOREIGN KEY(project_id) REFERENCES projects (id)
);

CREATE INDEX ix_clue_subscriptions_project_id ON clue_subscriptions (project_id);

CREATE TABLE similar_project_links (
    id UUID DEFAULT gen_random_uuid() NOT NULL, 
    source_project_id UUID NOT NULL, 
    similar_project_id UUID NOT NULL, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
    CONSTRAINT pk_similar_project_links PRIMARY KEY (id), 
    CONSTRAINT uq_similar_links_source_similar UNIQUE (source_project_id, similar_project_id), 
    CONSTRAINT fk_similar_project_links_source_project_id_projects FOREIGN KEY(source_project_id) REFERENCES projects (id), 
    CONSTRAINT fk_similar_project_links_similar_project_id_projects FOREIGN KEY(similar_project_id) REFERENCES projects (id)
);

CREATE INDEX ix_similar_links_source ON similar_project_links (source_project_id);

CREATE INDEX ix_similar_links_similar ON similar_project_links (similar_project_id);

CREATE TABLE project_reactions (
    id UUID DEFAULT gen_random_uuid() NOT NULL, 
    user_id UUID NOT NULL, 
    project_id UUID NOT NULL, 
    reaction_type reaction_type NOT NULL, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
    CONSTRAINT pk_project_reactions PRIMARY KEY (id), 
    CONSTRAINT uq_reactions_user_project_type UNIQUE (user_id, project_id, reaction_type), 
    CONSTRAINT fk_project_reactions_user_id_users FOREIGN KEY(user_id) REFERENCES users (id), 
    CONSTRAINT fk_project_reactions_project_id_projects FOREIGN KEY(project_id) REFERENCES projects (id)
);

CREATE INDEX ix_project_reactions_project_id ON project_reactions (project_id);

CREATE TABLE shares (
    id UUID DEFAULT gen_random_uuid() NOT NULL, 
    user_id UUID, 
    anon_client_id VARCHAR(64), 
    project_id UUID NOT NULL, 
    share_channel share_channel NOT NULL, 
    share_status share_status NOT NULL, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
    CONSTRAINT pk_shares PRIMARY KEY (id), 
    CONSTRAINT fk_shares_user_id_users FOREIGN KEY(user_id) REFERENCES users (id), 
    CONSTRAINT fk_shares_project_id_projects FOREIGN KEY(project_id) REFERENCES projects (id)
);

CREATE INDEX ix_shares_project_status_channel ON shares (project_id, share_status, share_channel);

CREATE TABLE reports (
    id UUID DEFAULT gen_random_uuid() NOT NULL, 
    reporter_user_id UUID NOT NULL, 
    project_id UUID NOT NULL, 
    reason VARCHAR(50) NOT NULL, 
    description TEXT, 
    status report_status DEFAULT 'pending' NOT NULL, 
    handled_by_user_id UUID, 
    handled_at TIMESTAMP WITH TIME ZONE, 
    resolution_note TEXT, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
    CONSTRAINT pk_reports PRIMARY KEY (id), 
    CONSTRAINT fk_reports_reporter_user_id_users FOREIGN KEY(reporter_user_id) REFERENCES users (id), 
    CONSTRAINT fk_reports_project_id_projects FOREIGN KEY(project_id) REFERENCES projects (id), 
    CONSTRAINT fk_reports_handled_by_user_id_users FOREIGN KEY(handled_by_user_id) REFERENCES users (id)
);

CREATE INDEX ix_reports_status_created_at ON reports (status, created_at);

CREATE INDEX ix_reports_project_id ON reports (project_id);

CREATE TABLE notifications (
    id UUID DEFAULT gen_random_uuid() NOT NULL, 
    user_id UUID NOT NULL, 
    type notification_type NOT NULL, 
    title VARCHAR(200) NOT NULL, 
    body TEXT, 
    project_id UUID, 
    is_read BOOLEAN DEFAULT false NOT NULL, 
    read_at TIMESTAMP WITH TIME ZONE, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
    CONSTRAINT pk_notifications PRIMARY KEY (id), 
    CONSTRAINT fk_notifications_user_id_users FOREIGN KEY(user_id) REFERENCES users (id), 
    CONSTRAINT fk_notifications_project_id_projects FOREIGN KEY(project_id) REFERENCES projects (id)
);

CREATE INDEX ix_notifications_user_read_created ON notifications (user_id, is_read, created_at);

CREATE TABLE push_preferences (
    id UUID DEFAULT gen_random_uuid() NOT NULL, 
    user_id UUID NOT NULL, 
    daily_pick_enabled BOOLEAN DEFAULT true NOT NULL, 
    weekly_ranking_enabled BOOLEAN DEFAULT true NOT NULL, 
    how_to_interest_enabled BOOLEAN DEFAULT true NOT NULL, 
    clue_update_enabled BOOLEAN DEFAULT true NOT NULL, 
    similar_project_enabled BOOLEAN DEFAULT true NOT NULL, 
    content_status_enabled BOOLEAN DEFAULT true NOT NULL, 
    system_enabled BOOLEAN DEFAULT true NOT NULL, 
    interaction_enabled BOOLEAN DEFAULT true NOT NULL, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
    CONSTRAINT pk_push_preferences PRIMARY KEY (id), 
    CONSTRAINT uq_push_preferences_user_id UNIQUE (user_id), 
    CONSTRAINT fk_push_preferences_user_id_users FOREIGN KEY(user_id) REFERENCES users (id)
);

CREATE TABLE candidate_contents (
    id UUID DEFAULT gen_random_uuid() NOT NULL, 
    status candidate_status DEFAULT 'ai_collected' NOT NULL, 
    title VARCHAR(80), 
    tagline VARCHAR(140), 
    summary VARCHAR(500), 
    description TEXT, 
    category category, 
    language language DEFAULT 'zh-CN' NOT NULL, 
    domains TEXT[] DEFAULT '{}'::text[] NOT NULL, 
    tools TEXT[] DEFAULT '{}'::text[] NOT NULL, 
    tags_json JSONB, 
    ai_implementation_hint TEXT, 
    target_users TEXT[], 
    use_cases TEXT[], 
    source_url TEXT, 
    source_platform VARCHAR(50), 
    original_author_name VARCHAR(100), 
    original_author_url TEXT, 
    cover_media_url TEXT, 
    media_json JSONB, 
    scores_json JSONB, 
    ai_curation_score INTEGER, 
    risk_flags TEXT[] DEFAULT '{}'::text[] NOT NULL, 
    risk_note TEXT, 
    reviewed_by_user_id UUID, 
    reviewed_at TIMESTAMP WITH TIME ZONE, 
    project_id UUID, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
    CONSTRAINT pk_candidate_contents PRIMARY KEY (id), 
    CONSTRAINT fk_candidate_contents_reviewed_by_user_id_users FOREIGN KEY(reviewed_by_user_id) REFERENCES users (id), 
    CONSTRAINT fk_candidate_contents_project_id_projects FOREIGN KEY(project_id) REFERENCES projects (id)
);

CREATE INDEX ix_candidate_contents_status_created ON candidate_contents (status, created_at);

CREATE INDEX ix_candidate_contents_score ON candidate_contents (ai_curation_score);

CREATE TABLE admin_actions (
    id UUID DEFAULT gen_random_uuid() NOT NULL, 
    admin_user_id UUID NOT NULL, 
    action VARCHAR(50) NOT NULL, 
    target_type VARCHAR(30) NOT NULL, 
    target_id UUID, 
    detail JSONB, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
    CONSTRAINT pk_admin_actions PRIMARY KEY (id), 
    CONSTRAINT fk_admin_actions_admin_user_id_users FOREIGN KEY(admin_user_id) REFERENCES users (id)
);

CREATE INDEX ix_admin_actions_admin_created ON admin_actions (admin_user_id, created_at);

CREATE INDEX ix_admin_actions_target ON admin_actions (target_type, target_id);

CREATE TABLE analytics_events (
    id UUID DEFAULT gen_random_uuid() NOT NULL, 
    user_id UUID, 
    event_name VARCHAR(50) NOT NULL, 
    project_id UUID, 
    event_payload JSONB, 
    client_info JSONB, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, 
    CONSTRAINT pk_analytics_events PRIMARY KEY (id)
);

CREATE INDEX ix_analytics_events_name_created ON analytics_events (event_name, created_at);

CREATE INDEX ix_analytics_events_project_id ON analytics_events (project_id);

INSERT INTO alembic_version (version_num) VALUES ('0001') RETURNING alembic_version.version_num;

COMMIT;

