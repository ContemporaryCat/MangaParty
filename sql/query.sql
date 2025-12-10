-- name: CreateRes :one
INSERT INTO mp_res (entity_type, note)
VALUES ($1, $2)
RETURNING id, created_at;

-- name: ListRes :many
SELECT id, entity_type, note, created_at, updated_at
FROM mp_res
ORDER BY created_at DESC;

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

-- name: ListPeople :many
SELECT 
    r.id, r.entity_type, r.note, r.created_at, r.updated_at,
    a.contact_info, a.field_of_activity, a.language,
    p.profession
FROM mp_res r
JOIN mp_agent a ON r.id = a.id
JOIN mp_person p ON a.id = p.id
ORDER BY r.created_at DESC;

-- name: CreateWork :exec
INSERT INTO mp_work (id, category, representative_attributes)
VALUES ($1, $2, $3);

-- name: GetWork :one
SELECT r.id, r.entity_type, r.note, r.created_at, w.category, w.representative_attributes
FROM mp_res r
JOIN mp_work w ON r.id = w.id
WHERE r.id = $1;

-- name: ListWorks :many
SELECT r.id, r.entity_type, r.note, r.created_at, w.category, w.representative_attributes
FROM mp_res r
JOIN mp_work w ON r.id = w.id
ORDER BY r.created_at DESC;

-- name: CreateExpression :exec
INSERT INTO mp_expression (id, category, extent, intended_audience, use_rights, cartographic_scale, language, musical_key, medium_of_performance)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9);

-- name: GetExpression :one
SELECT r.id, r.entity_type, r.note, r.created_at, e.category, e.extent, e.intended_audience, e.use_rights, e.cartographic_scale, e.language, e.musical_key, e.medium_of_performance
FROM mp_res r
JOIN mp_expression e ON r.id = e.id
WHERE r.id = $1;

-- name: ListExpressions :many
SELECT r.id, r.entity_type, r.note, r.created_at, e.category, e.extent, e.intended_audience, e.use_rights, e.cartographic_scale, e.language, e.musical_key, e.medium_of_performance
FROM mp_res r
JOIN mp_expression e ON r.id = e.id
ORDER BY r.created_at DESC;

-- name: CreateManifestation :exec
INSERT INTO mp_manifestation (id, carrier_category, extent, intended_audience, manifestation_statement, access_conditions, use_rights)
VALUES ($1, $2, $3, $4, $5, $6, $7);

-- name: GetManifestation :one
SELECT r.id, r.entity_type, r.note, r.created_at, m.carrier_category, m.extent, m.intended_audience, m.manifestation_statement, m.access_conditions, m.use_rights
FROM mp_res r
JOIN mp_manifestation m ON r.id = m.id
WHERE r.id = $1;

-- name: ListManifestations :many
SELECT r.id, r.entity_type, r.note, r.created_at, m.carrier_category, m.extent, m.intended_audience, m.manifestation_statement, m.access_conditions, m.use_rights
FROM mp_res r
JOIN mp_manifestation m ON r.id = m.id
ORDER BY r.created_at DESC;

-- name: CreateItem :exec
INSERT INTO mp_item (id, location, use_rights)
VALUES ($1, $2, $3);

-- name: GetItem :one
SELECT r.id, r.entity_type, r.note, r.created_at, i.location, i.use_rights
FROM mp_res r
JOIN mp_item i ON r.id = i.id
WHERE r.id = $1;

-- name: ListItems :many
SELECT r.id, r.entity_type, r.note, r.created_at, i.location, i.use_rights
FROM mp_res r
JOIN mp_item i ON r.id = i.id
ORDER BY r.created_at DESC;

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