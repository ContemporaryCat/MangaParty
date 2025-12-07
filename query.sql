-- name: CreateRes :one
INSERT INTO mp_res (entity_type, note)
VALUES ($1, $2)
RETURNING id, created_at;

-- name: CreateAgent :exec
INSERT INTO mp_agent (id, contact_info, field_of_activity, language)
VALUES ($1, $2, $3, $4);

-- name: CreatePerson :exec
INSERT INTO mp_person (id, profession)
VALUES ($1, $2);

-- name: GetPerson :one
-- Returns a fully hydrated Person by joining the inheritance tables
SELECT 
    r.id, r.entity_type, r.note, r.created_at, r.updated_at,
    a.contact_info, a.field_of_activity, a.language,
    p.profession
FROM mp_res r
JOIN mp_agent a ON r.id = a.id
JOIN mp_person p ON a.id = p.id
WHERE r.id = $1;

-- name: CreateWork :exec
INSERT INTO mp_work (id, category, representative_attributes)
VALUES ($1, $2, $3);

-- name: GetWork :one
SELECT r.id, r.entity_type, r.note, r.created_at, w.category, w.representative_attributes
FROM mp_res r
JOIN mp_work w ON r.id = w.id
WHERE r.id = $1;

-- name: CreateRelationship :one
INSERT INTO mp_relationship (source_id, target_id, rel_type, note)
VALUES ($1, $2, $3, $4)
RETURNING id;

-- name: GetWorksByCreator :many
-- Demonstrates graph traversal: Find all works created by a specific person
SELECT 
    r.id, r.entity_type, r.note, r.created_at, w.category, w.representative_attributes
FROM mp_relationship rel
JOIN mp_res r ON rel.source_id = r.id
JOIN mp_work w ON r.id = w.id
WHERE rel.target_id = $1 -- The agent's ID
AND rel.rel_type = 'MP_R5'; -- 'Work was created by Agent'