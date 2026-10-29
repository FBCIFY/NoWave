CREATE EXTENSION IF NOT EXISTS postgis;

CREATE SCHEMA nowave;

SET LOCAL search_path = nowave, public;

CREATE TABLE users (
    id uuid PRIMARY KEY NOT NULL,
    firebase_uid text NOT NULL UNIQUE,
    username varchar(100) NOT NULL UNIQUE,
    email varchar(254) NOT NULL UNIQUE,
    date_of_birth date,
    nationality char(2),
    role varchar(10) NOT NULL CHECK (role IN ('user', 'admin')),
    status varchar(10) NOT NULL CHECK (status IN ('active', 'suspended')),
    show_user_name boolean NOT NULL DEFAULT false,
    show_boat_info boolean NOT NULL DEFAULT false,
    notifications_enabled boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);

CREATE TABLE boats (
    id uuid PRIMARY KEY NOT NULL,
    user_id uuid NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    name varchar(100),
    boat_type varchar(20) NOT NULL CHECK (boat_type IN ('voilier', 'bateau_moteur', 'catamaran', 'semi_rigide', 'jet_ski', 'autre')),
    flag_country char(2),
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);

CREATE TABLE devices (
    id uuid PRIMARY KEY NOT NULL,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    installation_id uuid NOT NULL UNIQUE,
    fcm_token text UNIQUE,
    platform varchar(10) NOT NULL CHECK (platform IN ('android', 'ios')),
    is_active boolean NOT NULL,
    last_seen_at timestamptz NOT NULL
);

CREATE TABLE device_positions (
    device_id uuid PRIMARY KEY NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    position geography(Point,4326) NOT NULL CHECK (NOT ST_IsEmpty(position::geometry)),
    accuracy_m double precision NOT NULL CHECK (accuracy_m BETWEEN 0 AND 50),
    heading_deg double precision CHECK (heading_deg >= 0 AND heading_deg < 360),
    measured_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL
);

CREATE TABLE reports (
    id uuid PRIMARY KEY NOT NULL,
    author_id uuid REFERENCES users(id) ON DELETE SET NULL,
    client_report_id uuid NOT NULL,
    category varchar(20) NOT NULL CHECK (category IN ('marine_animal', 'obstruction', 'pollution')),
    positioning_mode varchar(10) NOT NULL CHECK (positioning_mode IN ('photo', 'manual')),
    description varchar(250),
    final_position geography(Point,4326) NOT NULL CHECK (NOT ST_IsEmpty(final_position::geometry)),
    observed_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    status varchar(10) NOT NULL CHECK (status IN ('active', 'removed', 'expired')),
    version integer NOT NULL DEFAULT 1 CHECK (version >= 1),
    updated_at timestamptz NOT NULL,
    removed_at timestamptz,
    CONSTRAINT reports_author_client_key UNIQUE (author_id, client_report_id),
    CONSTRAINT reports_lifetime CHECK (isfinite(observed_at) AND expires_at = observed_at + interval '24 hours')
);

CREATE TABLE report_positioning (
    report_id uuid PRIMARY KEY NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
    observer_position geography(Point,4326) NOT NULL CHECK (NOT ST_IsEmpty(observer_position::geometry)),
    gps_accuracy_m double precision NOT NULL CHECK (gps_accuracy_m BETWEEN 0 AND 50),
    azimuth_deg double precision NOT NULL CHECK (azimuth_deg >= 0 AND azimuth_deg < 360),
    inclination_deg double precision NOT NULL CHECK (inclination_deg > '-Infinity'::float8 AND inclination_deg < 'Infinity'::float8),
    camera_height_m numeric(6,2) NOT NULL CHECK (camera_height_m > 0 AND camera_height_m < 'Infinity'::numeric),
    camera_height_source varchar(30),
    camera_height_uncertainty_m double precision CHECK (camera_height_uncertainty_m >= 0 AND camera_height_uncertainty_m < 'Infinity'::float8),
    focal_length_mm double precision CHECK (focal_length_mm > 0 AND focal_length_mm < 'Infinity'::float8),
    zoom_ratio double precision CHECK (zoom_ratio > 0 AND zoom_ratio < 'Infinity'::float8),
    estimated_position geography(Point,4326) CHECK (NOT ST_IsEmpty(estimated_position::geometry)),
    estimated_distance_m double precision CHECK (estimated_distance_m >= 0 AND estimated_distance_m < 'Infinity'::float8),
    algorithm_version varchar(50),
    captured_at timestamptz NOT NULL
);

CREATE TABLE report_photos (
    report_id uuid PRIMARY KEY NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
    upload_status varchar(10) NOT NULL CHECK (upload_status IN ('pending', 'uploaded', 'failed')),
    object_key text UNIQUE,
    size_bytes integer CHECK (size_bytes > 0 AND size_bytes <= 500000),
    mime_type varchar(100) CHECK (mime_type = 'image/jpeg'),
    uploaded_at timestamptz,
    hidden_at timestamptz,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    CONSTRAINT report_photos_uploaded_metadata CHECK (upload_status <> 'uploaded' OR (object_key IS NOT NULL AND btrim(object_key) <> '' AND size_bytes IS NOT NULL AND mime_type IS NOT NULL AND uploaded_at IS NOT NULL))
);

CREATE TABLE notifications (
    id uuid PRIMARY KEY NOT NULL,
    report_id uuid NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
    device_id uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    report_version integer NOT NULL CHECK (report_version >= 1),
    status varchar(10) NOT NULL CHECK (status IN ('pending', 'sent', 'failed')),
    attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    next_attempt_at timestamptz,
    sent_at timestamptz,
    last_error_code text,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    CONSTRAINT notifications_delivery_key UNIQUE (report_id, device_id, report_version),
    CONSTRAINT notifications_pending_time CHECK (status <> 'pending' OR next_attempt_at IS NOT NULL),
    CONSTRAINT notifications_sent_time CHECK (status <> 'sent' OR sent_at IS NOT NULL)
);

CREATE TABLE alert_history (
    id uuid PRIMARY KEY NOT NULL,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    report_id uuid NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
    report_version integer NOT NULL CHECK (report_version >= 1),
    category varchar(20) NOT NULL CHECK (category IN ('marine_animal', 'obstruction', 'pollution')),
    position geography(Point,4326) NOT NULL CHECK (NOT ST_IsEmpty(position::geometry)),
    distance_m double precision NOT NULL CHECK (distance_m >= 0 AND distance_m < 'Infinity'::float8),
    alerted_at timestamptz NOT NULL,
    CONSTRAINT alert_history_recipient_key UNIQUE (user_id, report_id, report_version)
);

CREATE TABLE moderation_actions (
    id uuid PRIMARY KEY NOT NULL,
    admin_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
    target_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
    target_report_id uuid REFERENCES reports(id) ON DELETE SET NULL,
    target_photo_report_id uuid REFERENCES report_photos(report_id) ON DELETE SET NULL,
    action varchar(20) NOT NULL CHECK (action IN ('remove_report', 'restore_report', 'hide_photo', 'suspend_user', 'reactivate_user')),
    reason text NOT NULL CHECK (reason ~ '[^[:space:]]'),
    previous_status varchar(10),
    new_status varchar(10),
    created_at timestamptz NOT NULL,
    CONSTRAINT moderation_actions_at_most_one_target CHECK (
        num_nonnulls(target_user_id, target_report_id, target_photo_report_id) <= 1
    ),
    CONSTRAINT moderation_actions_target_matches_action CHECK (
        (target_user_id IS NULL AND target_report_id IS NULL AND target_photo_report_id IS NULL)
        OR (action IN ('suspend_user', 'reactivate_user') AND target_user_id IS NOT NULL)
        OR (action IN ('remove_report', 'restore_report') AND target_report_id IS NOT NULL)
        OR (action = 'hide_photo' AND target_photo_report_id IS NOT NULL)
    )
);

CREATE INDEX reports_final_position_gist ON reports USING gist (final_position);
CREATE INDEX reports_final_position_geometry_gist ON reports USING gist ((final_position::geometry));

CREATE INDEX device_positions_position_gist ON device_positions USING gist (position);

CREATE INDEX reports_author_idx ON reports (author_id);

CREATE INDEX reports_status_expiry_idx ON reports (status, expires_at);

CREATE INDEX devices_user_idx ON devices (user_id);

CREATE INDEX notifications_schedule_idx ON notifications (status, next_attempt_at);

-- Valide les enfants d'un rapport selon son mode de positionnement.
CREATE FUNCTION nowave.assert_photo_children(p_report_id uuid) RETURNS void
LANGUAGE plpgsql SET search_path = nowave, public AS $$
DECLARE
    report_mode text;
    has_photo boolean;
    has_positioning boolean;
BEGIN
    SELECT positioning_mode INTO report_mode FROM reports WHERE id = p_report_id;
    IF NOT FOUND THEN
        RETURN;
    END IF;

    SELECT EXISTS(SELECT 1 FROM report_photos WHERE report_id = p_report_id),
           EXISTS(SELECT 1 FROM report_positioning WHERE report_id = p_report_id)
    INTO has_photo, has_positioning;

    IF (report_mode = 'photo' AND NOT (has_photo AND has_positioning))
       OR (report_mode = 'manual' AND (has_photo OR has_positioning)) THEN
        RAISE EXCEPTION 'Report % has inconsistent photo children', p_report_id
            USING ERRCODE = '23514', CONSTRAINT = 'report_photo_children';
    END IF;
END $$;

-- Identifie les rapports affectés et déclenche leur validation différée.
CREATE FUNCTION nowave.check_photo_children() RETURNS trigger
LANGUAGE plpgsql SET search_path = nowave, public AS $$
DECLARE
    old_report_id uuid;
    new_report_id uuid;
    affected_report_id uuid;
BEGIN
    IF TG_TABLE_NAME = 'reports' THEN
        IF TG_OP <> 'INSERT' THEN old_report_id := OLD.id; END IF;
        IF TG_OP <> 'DELETE' THEN new_report_id := NEW.id; END IF;
    ELSE
        IF TG_OP <> 'INSERT' THEN old_report_id := OLD.report_id; END IF;
        IF TG_OP <> 'DELETE' THEN new_report_id := NEW.report_id; END IF;
    END IF;

    FOR affected_report_id IN
        SELECT DISTINCT report_id
        FROM unnest(ARRAY[old_report_id, new_report_id]) AS report_id
        WHERE report_id IS NOT NULL
        ORDER BY report_id
    LOOP
        PERFORM nowave.assert_photo_children(affected_report_id);
    END LOOP;
    RETURN NULL;
END $$;
-- Vérifient l'état final des rapports et de leurs enfants au COMMIT.
CREATE CONSTRAINT TRIGGER report_photo_children AFTER INSERT OR UPDATE OR DELETE ON nowave.reports
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION nowave.check_photo_children();
CREATE CONSTRAINT TRIGGER report_photo_children AFTER INSERT OR UPDATE OR DELETE ON nowave.report_photos
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION nowave.check_photo_children();
CREATE CONSTRAINT TRIGGER report_photo_children AFTER INSERT OR UPDATE OR DELETE ON nowave.report_positioning
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION nowave.check_photo_children();

-- Empêche les changements interdits sur l'auteur, la durée et la restauration d'un rapport.
CREATE FUNCTION nowave.guard_report() RETURNS trigger
LANGUAGE plpgsql SET search_path = nowave, public AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.author_id IS NULL THEN
        RAISE EXCEPTION 'An author is required at creation' USING ERRCODE = '23514';
    END IF;
    IF TG_OP = 'UPDATE' THEN
        IF NEW.observed_at IS DISTINCT FROM OLD.observed_at
           OR NEW.expires_at IS DISTINCT FROM OLD.expires_at THEN
            RAISE EXCEPTION 'Original report lifetime is immutable' USING ERRCODE = '23514';
        END IF;
        IF NEW.author_id IS DISTINCT FROM OLD.author_id AND NOT
           (NEW.author_id IS NULL AND NOT EXISTS (SELECT 1 FROM users WHERE id = OLD.author_id)) THEN
            RAISE EXCEPTION 'Author can only be cleared by account deletion' USING ERRCODE = '23514';
        END IF;
        IF OLD.status = 'removed' AND NEW.status <> 'removed' AND NEW.removed_at IS NOT NULL THEN
            RAISE EXCEPTION 'Restoration must clear removed_at' USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END $$;
-- Bloque une ligne de rapport invalide avant son écriture.
CREATE TRIGGER reports_guard BEFORE INSERT OR UPDATE ON nowave.reports
FOR EACH ROW EXECUTE FUNCTION nowave.guard_report();

-- Empêche la réattribution d'une installation à un autre utilisateur
CREATE FUNCTION nowave.guard_device_owner() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.user_id IS DISTINCT FROM OLD.user_id OR NEW.installation_id IS DISTINCT FROM OLD.installation_id THEN
        RAISE EXCEPTION 'Register a new installation on account change' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;
-- Bloque une mise à jour qui change le propriétaire ou l'identifiant d'installation.
CREATE TRIGGER device_owner_guard BEFORE UPDATE ON nowave.devices
FOR EACH ROW EXECUTE FUNCTION nowave.guard_device_owner();

-- Garantit un audit créé par un administrateur actif et conservé sans modification.
CREATE FUNCTION nowave.guard_audit() RETURNS trigger
LANGUAGE plpgsql SET search_path = nowave, public AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Audit entries cannot be deleted' USING ERRCODE = '23514';
    END IF;
    IF TG_OP = 'INSERT' THEN
        PERFORM 1 FROM users WHERE id = NEW.admin_user_id AND role = 'admin' AND status = 'active' FOR SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'An active administrator is required' USING ERRCODE = '23514';
        END IF;
        IF num_nonnulls(NEW.target_user_id, NEW.target_report_id, NEW.target_photo_report_id) <> 1 THEN
            RAISE EXCEPTION 'Exactly one target is required at creation' USING ERRCODE = '23514';
        END IF;
    ELSE
        IF (to_jsonb(NEW) - ARRAY['admin_user_id','target_user_id','target_report_id','target_photo_report_id'])
           IS DISTINCT FROM
           (to_jsonb(OLD) - ARRAY['admin_user_id','target_user_id','target_report_id','target_photo_report_id']) THEN
            RAISE EXCEPTION 'Audit content is immutable' USING ERRCODE = '23514';
        END IF;
        IF NEW.admin_user_id IS DISTINCT FROM OLD.admin_user_id AND NOT
           (NEW.admin_user_id IS NULL AND NOT EXISTS (SELECT 1 FROM users WHERE id = OLD.admin_user_id)) THEN
            RAISE EXCEPTION 'Audit administrator is immutable' USING ERRCODE = '23514';
        END IF;
        IF NEW.target_user_id IS DISTINCT FROM OLD.target_user_id AND NOT
           (NEW.target_user_id IS NULL AND NOT EXISTS (SELECT 1 FROM users WHERE id = OLD.target_user_id)) THEN
            RAISE EXCEPTION 'Audit user target is immutable' USING ERRCODE = '23514';
        END IF;
        IF NEW.target_report_id IS DISTINCT FROM OLD.target_report_id AND NOT
           (NEW.target_report_id IS NULL AND NOT EXISTS (SELECT 1 FROM reports WHERE id = OLD.target_report_id)) THEN
            RAISE EXCEPTION 'Audit report target is immutable' USING ERRCODE = '23514';
        END IF;
        IF NEW.target_photo_report_id IS DISTINCT FROM OLD.target_photo_report_id AND NOT
           (NEW.target_photo_report_id IS NULL AND NOT EXISTS (SELECT 1 FROM report_photos WHERE report_id = OLD.target_photo_report_id)) THEN
            RAISE EXCEPTION 'Audit photo target is immutable' USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END $$;
-- Bloque les créations, modifications et suppressions d'audit invalides.
CREATE TRIGGER audit_guard BEFORE INSERT OR UPDATE OR DELETE ON nowave.moderation_actions
FOR EACH ROW EXECUTE FUNCTION nowave.guard_audit();
