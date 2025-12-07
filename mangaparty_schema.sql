-- ==================================================================
-- 0. EXTENSIONS & SETUP
-- ==================================================================

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Function to auto-update updated_at timestamps
CREATE OR REPLACE FUNCTION update_modified_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- ==================================================================
-- 1. ENUMS
-- ==================================================================

CREATE TYPE mp_entity_type AS ENUM (
  -- LRM Core
  'res',
  'work',
  'expression',
  'manifestation',
  'item',
  'agent',
  'person',
  'collective_agent',
  'nomen',
  'place',
  'time_span',
  -- Custom System Types
  'language',
  'content_rating',
  'type',
  'status',
  'tag',
  'digital_resource',
  'image',
  'link',
  'rss_feed',
  'file'
);

CREATE TYPE mp_relationship_type AS ENUM (
  -- --- Unified MP Relationships (LRM Core Implementation) ---
  'MP_R1',  -- Res is associated with Res (LRM-R1)
  'MP_R2',  -- Work is realized through Expression (LRM-R2)
  'MP_R3',  -- Expression is embodied in Manifestation (LRM-R3)
  'MP_R4',  -- Manifestation is exemplified by Item (LRM-R4)
  'MP_R5',  -- Work was created by Agent (LRM-R5)
  'MP_R6',  -- Expression was created by Agent (LRM-R6)
  'MP_R7',  -- Manifestation was created by Agent (LRM-R7)
  'MP_R8',  -- Manifestation was manufactured by Agent (LRM-R8)
  'MP_R9',  -- Manifestation is distributed by Agent (LRM-R9)
  'MP_R10', -- Item is owned by Agent (LRM-R10)
  'MP_R11', -- Item was modified by Agent (LRM-R11)
  'MP_R12', -- Work has as subject Res (LRM-R12)
  'MP_R13', -- Res has appellation Nomen (LRM-R13)
  'MP_R14', -- Agent assigned Nomen (LRM-R14)
  'MP_R15', -- Nomen is equivalent to Nomen (LRM-R15)
  'MP_R16', -- Nomen has part Nomen (LRM-R16)
  'MP_R17', -- Nomen is derivation of Nomen (LRM-R17)
  'MP_R18', -- Work has part Work (LRM-R18)
  'MP_R19', -- Work precedes Work (LRM-R19)
  'MP_R20', -- Work accompanies / complements Work (LRM-R20)
  'MP_R21', -- Work is inspiration for Work (LRM-R21)
  'MP_R22', -- Work is a transformation of Work (LRM-R22)
  'MP_R23', -- Expression has part Expression (LRM-R23)
  'MP_R24', -- Expression is derivation of Expression (LRM-R24)
  'MP_R25', -- Expression was aggregated by Expression (LRM-R25)
  'MP_R26', -- Manifestation has part Manifestation (LRM-R26)
  'MP_R27', -- Manifestation has reproduction Manifestation (LRM-R27)
  'MP_R28', -- Item has reproduction Manifestation (LRM-R28)
  'MP_R29', -- Manifestation has alternate Manifestation (LRM-R29)
  'MP_R30', -- Agent is member of Collective Agent (LRM-R30)
  'MP_R31', -- Collective Agent has part Collective Agent (LRM-R31)
  'MP_R32', -- Collective Agent precedes Collective Agent (LRM-R32)
  'MP_R33', -- Res has association with Place (LRM-R33)
  'MP_R34', -- Place has part Place (LRM-R34)
  'MP_R35', -- Res has association with Time-span (LRM-R35)
  'MP_R36', -- Time-span has part Time-span (LRM-R36)
  
  -- --- Unified MP Relationships (System Extensions) ---
  'MP_R37', -- Res has Tag (formerly SYS_HAS_TAG)
  'MP_R38', -- Res has Digital Resource representation (formerly SYS_HAS_DIGITAL_REP)
  'MP_R39', -- Res is in Language (formerly SYS_HAS_LANGUAGE)
  'MP_R40'  -- Res has Content Rating (formerly SYS_HAS_RATING)
);

-- ==================================================================
-- 2. ROOT ENTITY (LRM-E1 / MP-E1)
-- ==================================================================

CREATE TABLE mp_res (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  entity_type mp_entity_type NOT NULL,
  note TEXT[],
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ
);

COMMENT ON TABLE mp_res IS 'MP-E1 (LRM-E1): Top level entity. All other entities inherit from this via 1:1 FK.';
COMMENT ON COLUMN mp_res.entity_type IS 'Discriminator for Class Table Inheritance';
COMMENT ON COLUMN mp_res.note IS 'Multivalued attribute';

-- Trigger for updated_at
CREATE TRIGGER update_mp_res_modtime
BEFORE UPDATE ON mp_res
FOR EACH ROW EXECUTE PROCEDURE update_modified_column();

-- ==================================================================
-- 3. WEMI ENTITIES (LRM-E2 to E5)
-- ==================================================================

CREATE TABLE mp_work (
  id UUID PRIMARY KEY REFERENCES mp_res(id) ON DELETE CASCADE,
  category TEXT[],
  representative_attributes JSONB
);

COMMENT ON TABLE mp_work IS 'MP-E2 (LRM-E2): The intellectual or artistic content.';
COMMENT ON COLUMN mp_work.category IS 'e.g. termination intention, creative domain';
COMMENT ON COLUMN mp_work.representative_attributes IS 'Stores cached values from the canonical expression (Key, Language, Scale)';

CREATE TABLE mp_expression (
  id UUID PRIMARY KEY REFERENCES mp_res(id) ON DELETE CASCADE,
  category TEXT[],
  extent TEXT[],
  intended_audience TEXT[],
  use_rights TEXT[],
  cartographic_scale TEXT[],
  language TEXT[],
  musical_key TEXT[],
  medium_of_performance TEXT[]
);

COMMENT ON TABLE mp_expression IS 'MP-E3 (LRM-E3): A distinct combination of signs conveying content.';
COMMENT ON COLUMN mp_expression.category IS 'e.g. content type, notation';
COMMENT ON COLUMN mp_expression.extent IS 'e.g. duration, word count';
COMMENT ON COLUMN mp_expression.language IS 'LRM-E3-A6';
COMMENT ON COLUMN mp_expression.musical_key IS 'LRM-E3-A7';
COMMENT ON COLUMN mp_expression.medium_of_performance IS 'LRM-E3-A8';

CREATE TABLE mp_manifestation (
  id UUID PRIMARY KEY REFERENCES mp_res(id) ON DELETE CASCADE,
  carrier_category TEXT[],
  extent TEXT[],
  intended_audience TEXT[],
  manifestation_statement TEXT[],
  access_conditions TEXT[],
  use_rights TEXT[]
);

COMMENT ON TABLE mp_manifestation IS 'MP-E4 (LRM-E4): A set of all carriers sharing the same content/form.';
COMMENT ON COLUMN mp_manifestation.carrier_category IS 'e.g. volume, online resource';
COMMENT ON COLUMN mp_manifestation.manifestation_statement IS 'Transcribed title, imprint, etc.';

CREATE TABLE mp_item (
  id UUID PRIMARY KEY REFERENCES mp_res(id) ON DELETE CASCADE,
  location TEXT[],
  use_rights TEXT[]
);

COMMENT ON TABLE mp_item IS 'MP-E5 (LRM-E5): An object carrying signs (The concrete copy).';
COMMENT ON COLUMN mp_item.location IS 'Shelf mark, repository';
COMMENT ON COLUMN mp_item.use_rights IS 'Specific to this copy';

-- ==================================================================
-- 4. AGENTS (LRM-E6 to E8)
-- ==================================================================

CREATE TABLE mp_agent (
  id UUID PRIMARY KEY REFERENCES mp_res(id) ON DELETE CASCADE,
  contact_info TEXT[],
  field_of_activity TEXT[],
  language TEXT[]
);

COMMENT ON TABLE mp_agent IS 'MP-E6 (LRM-E6): Superclass for Person and Collective Agent.';

CREATE TABLE mp_person (
  id UUID PRIMARY KEY REFERENCES mp_agent(id) ON DELETE CASCADE,
  profession TEXT[]
);

COMMENT ON TABLE mp_person IS 'MP-E7 (LRM-E7): An individual human being.';

CREATE TABLE mp_collective_agent (
  id UUID PRIMARY KEY REFERENCES mp_agent(id) ON DELETE CASCADE,
  organization_type TEXT
);

COMMENT ON TABLE mp_collective_agent IS 'MP-E8 (LRM-E8): A gathering or organization acting as a unit.';

-- ==================================================================
-- 5. CONTEXTUAL ENTITIES (LRM-E9 to E11)
-- ==================================================================

CREATE TABLE mp_nomen (
  id UUID PRIMARY KEY REFERENCES mp_res(id) ON DELETE CASCADE,
  category TEXT[],
  nomen_string TEXT NOT NULL,
  scheme TEXT[],
  intended_audience TEXT[],
  context_of_use TEXT[],
  reference_source TEXT[],
  language TEXT[],
  script TEXT[],
  script_conversion TEXT[]
);

COMMENT ON TABLE mp_nomen IS 'MP-E9 (LRM-E9): An association between an entity and a designation.';
COMMENT ON COLUMN mp_nomen.category IS 'e.g. identifier, name, title';
COMMENT ON COLUMN mp_nomen.scheme IS 'e.g. ISBN, LCSH';

CREATE TABLE mp_place (
  id UUID PRIMARY KEY REFERENCES mp_res(id) ON DELETE CASCADE,
  category TEXT[],
  location_data JSONB
);

COMMENT ON TABLE mp_place IS 'MP-E10 (LRM-E10): A given extent of space.';
COMMENT ON COLUMN mp_place.location_data IS 'GeoJSON or coordinates';

CREATE TABLE mp_time_span (
  id UUID PRIMARY KEY REFERENCES mp_res(id) ON DELETE CASCADE,
  start_date TIMESTAMPTZ,
  end_date TIMESTAMPTZ,
  duration INTERVAL
);

COMMENT ON TABLE mp_time_span IS 'MP-E11 (LRM-E11): A temporal extent.';

-- ==================================================================
-- 6. CUSTOM SYSTEM ENTITIES (Inheriting from Res)
-- ==================================================================

CREATE TABLE mp_language (
  id UUID PRIMARY KEY REFERENCES mp_res(id) ON DELETE CASCADE,
  iso_code TEXT,
  name TEXT
);
COMMENT ON TABLE mp_language IS 'Custom entity for managing language controlled vocabulary.';

CREATE TABLE mp_content_rating (
  id UUID PRIMARY KEY REFERENCES mp_res(id) ON DELETE CASCADE,
  authority TEXT,
  rating_value TEXT
);
COMMENT ON TABLE mp_content_rating IS 'Custom entity for content advisories.';
COMMENT ON COLUMN mp_content_rating.authority IS 'e.g. MPAA, ESRB';

CREATE TABLE mp_type (
  id UUID PRIMARY KEY REFERENCES mp_res(id) ON DELETE CASCADE,
  category TEXT,
  label TEXT
);
COMMENT ON TABLE mp_type IS 'Custom entity for resource typing.';

CREATE TABLE mp_status (
  id UUID PRIMARY KEY REFERENCES mp_res(id) ON DELETE CASCADE,
  status_code TEXT,
  label TEXT
);
COMMENT ON TABLE mp_status IS 'Custom entity for workflow status.';

CREATE TABLE mp_tag (
  id UUID PRIMARY KEY REFERENCES mp_res(id) ON DELETE CASCADE,
  label TEXT,
  slug TEXT
);
COMMENT ON TABLE mp_tag IS 'Custom entity for folksonomy/tagging.';

-- ==================================================================
-- 7. DIGITAL RESOURCES (Custom Hierarchy)
-- ==================================================================

CREATE TABLE mp_digital_resource (
  id UUID PRIMARY KEY REFERENCES mp_res(id) ON DELETE CASCADE,
  uri TEXT,
  access_restrictions TEXT[]
);
COMMENT ON TABLE mp_digital_resource IS 'Custom superclass for digital assets.';

CREATE TABLE mp_image (
  id UUID PRIMARY KEY REFERENCES mp_digital_resource(id) ON DELETE CASCADE,
  width INT,
  height INT,
  mime_type TEXT
);

CREATE TABLE mp_link (
  id UUID PRIMARY KEY REFERENCES mp_digital_resource(id) ON DELETE CASCADE,
  target_url TEXT,
  last_checked TIMESTAMPTZ
);

CREATE TABLE mp_rss_feed (
  id UUID PRIMARY KEY REFERENCES mp_digital_resource(id) ON DELETE CASCADE,
  feed_url TEXT,
  update_frequency TEXT
);

CREATE TABLE mp_file (
  id UUID PRIMARY KEY REFERENCES mp_digital_resource(id) ON DELETE CASCADE,
  filename TEXT,
  file_size_bytes BIGINT,
  checksum TEXT,
  extension TEXT
);

-- ==================================================================
-- 8. RELATIONSHIPS (The Graph Edge Table)
-- ==================================================================

CREATE TABLE mp_relationship (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  source_id UUID NOT NULL REFERENCES mp_res(id) ON DELETE CASCADE,
  target_id UUID NOT NULL REFERENCES mp_res(id) ON DELETE CASCADE,
  rel_type mp_relationship_type NOT NULL,
  start_date TIMESTAMPTZ,
  end_date TIMESTAMPTZ,
  note TEXT
);

COMMENT ON TABLE mp_relationship IS 'Generic link table implementing the Unified MP Relationship Model. Connects any Res to any Res based on the definition in mp_relationship_type.';

-- ==================================================================
-- 9. INDEXES
-- ==================================================================

-- Indexes for Relationship Graph Traversal
CREATE INDEX idx_mp_relationship_source ON mp_relationship(source_id);
CREATE INDEX idx_mp_relationship_target ON mp_relationship(target_id);
CREATE INDEX idx_mp_relationship_type ON mp_relationship(rel_type);
CREATE INDEX idx_mp_relationship_composite ON mp_relationship(source_id, rel_type, target_id);

-- Indexes for Nomen lookups (Search)
CREATE INDEX idx_mp_nomen_string ON mp_nomen(nomen_string);
-- Note: pg_trgm extension required for GIN trigram indexes if fuzzy search is desired
-- CREATE EXTENSION IF NOT EXISTS pg_trgm;
-- CREATE INDEX idx_mp_nomen_string_trgm ON mp_nomen USING gin (nomen_string gin_trgm_ops);

-- Indexes for Discriminators
CREATE INDEX idx_mp_res_entity_type ON mp_res(entity_type);