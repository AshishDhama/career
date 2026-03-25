-- Career Platform — Initial Schema

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Users (professionals + calibrators)
CREATE TABLE users (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email       TEXT UNIQUE NOT NULL,
    password    TEXT NOT NULL,         -- bcrypt hash
    name        TEXT NOT NULL,
    role        TEXT NOT NULL CHECK (role IN ('professional', 'calibrator', 'admin')),
    bio         TEXT,
    avatar_url  TEXT,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Skills
CREATE TABLE skills (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name        TEXT UNIQUE NOT NULL,
    category    TEXT NOT NULL,
    description TEXT,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Assessment sessions
CREATE TABLE assessments (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    professional_id UUID NOT NULL REFERENCES users(id),
    calibrator_id   UUID REFERENCES users(id),
    skill_id        UUID NOT NULL REFERENCES skills(id),
    status          TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'scheduled', 'in_progress', 'completed', 'cancelled')),
    score           INTEGER CHECK (score BETWEEN 0 AND 100),
    notes           TEXT,
    scheduled_at    TIMESTAMPTZ,
    started_at      TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- WebRTC session state
CREATE TABLE sessions (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    assessment_id   UUID NOT NULL REFERENCES assessments(id),
    offer_sdp       TEXT,
    answer_sdp      TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Chat messages within assessments
CREATE TABLE messages (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    assessment_id   UUID NOT NULL REFERENCES assessments(id),
    sender_id       UUID NOT NULL REFERENCES users(id),
    content         TEXT NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Seed some skills
INSERT INTO skills (name, category, description) VALUES
    ('React Development', 'Frontend', 'Building UIs with React'),
    ('System Design', 'Architecture', 'Designing scalable systems'),
    ('PostgreSQL', 'Database', 'Relational database design and optimization'),
    ('Zig', 'Backend', 'Systems programming with Zig'),
    ('WebRTC', 'Networking', 'Real-time peer-to-peer communication');
