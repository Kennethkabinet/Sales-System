--
-- PostgreSQL database dump
--

\restrict hI3mG82F8dnGdxpCCqF6cWZ0Y4u7wVYxSwiDzqKBNpeOZnZh1XoxqlmxbpxZF0K

-- Dumped from database version 18.1
-- Dumped by pg_dump version 18.1

-- Started on 2026-04-05 00:35:21

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 2 (class 3079 OID 16487)
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- TOC entry 5562 (class 0 OID 0)
-- Dependencies: 2
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- TOC entry 296 (class 1255 OID 16919)
-- Name: cleanup_expired_locks(); Type: FUNCTION; Schema: public; Owner: synergygraphics
--

CREATE FUNCTION public.cleanup_expired_locks() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM row_locks WHERE expires_at < CURRENT_TIMESTAMP;
END;
$$;


ALTER FUNCTION public.cleanup_expired_locks() OWNER TO synergygraphics;

--
-- TOC entry 297 (class 1255 OID 16913)
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: synergygraphics
--

CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_updated_at_column() OWNER TO synergygraphics;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 275 (class 1259 OID 17306)
-- Name: active_users; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.active_users (
    id integer NOT NULL,
    user_id integer NOT NULL,
    sheet_id integer NOT NULL,
    last_active_timestamp timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.active_users OWNER TO synergygraphics;

--
-- TOC entry 274 (class 1259 OID 17305)
-- Name: active_users_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.active_users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.active_users_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5563 (class 0 OID 0)
-- Dependencies: 274
-- Name: active_users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.active_users_id_seq OWNED BY public.active_users.id;


--
-- TOC entry 239 (class 1259 OID 16734)
-- Name: applied_formulas; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.applied_formulas (
    id integer NOT NULL,
    file_id integer,
    formula_id integer,
    column_mapping jsonb DEFAULT '{}'::jsonb,
    applied_by integer,
    applied_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.applied_formulas OWNER TO synergygraphics;

--
-- TOC entry 238 (class 1259 OID 16733)
-- Name: applied_formulas_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.applied_formulas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.applied_formulas_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5564 (class 0 OID 0)
-- Dependencies: 238
-- Name: applied_formulas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.applied_formulas_id_seq OWNED BY public.applied_formulas.id;


--
-- TOC entry 241 (class 1259 OID 16763)
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.audit_logs (
    id integer NOT NULL,
    user_id integer,
    action character varying(50) NOT NULL,
    entity_type character varying(50) NOT NULL,
    entity_id integer,
    file_id integer,
    row_number integer,
    field_name character varying(100),
    old_value text,
    new_value text,
    metadata jsonb DEFAULT '{}'::jsonb,
    ip_address inet,
    user_agent text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    sheet_id integer,
    cell_reference character varying(20),
    role character varying(50),
    department_name character varying(100)
);


ALTER TABLE public.audit_logs OWNER TO synergygraphics;

--
-- TOC entry 227 (class 1259 OID 16563)
-- Name: files; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.files (
    id integer NOT NULL,
    uuid uuid DEFAULT public.uuid_generate_v4(),
    name character varying(255) NOT NULL,
    original_filename character varying(255),
    file_path text,
    file_type character varying(50) DEFAULT 'xlsx'::character varying,
    department_id integer,
    created_by integer,
    current_version integer DEFAULT 1,
    column_mapping jsonb DEFAULT '{}'::jsonb,
    columns jsonb DEFAULT '[]'::jsonb,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    source_sheet_id integer,
    folder_id integer
);


ALTER TABLE public.files OWNER TO synergygraphics;

--
-- TOC entry 225 (class 1259 OID 16529)
-- Name: users; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.users (
    id integer NOT NULL,
    username character varying(50) NOT NULL,
    email character varying(255) NOT NULL,
    password_hash character varying(255) NOT NULL,
    full_name character varying(100),
    role_id integer DEFAULT 2,
    department_id integer,
    is_active boolean DEFAULT true,
    last_login timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    created_by integer,
    deactivated_by integer,
    deactivated_at timestamp with time zone
);


ALTER TABLE public.users OWNER TO synergygraphics;

--
-- TOC entry 254 (class 1259 OID 16930)
-- Name: audit_log_details; Type: VIEW; Schema: public; Owner: synergygraphics
--

CREATE VIEW public.audit_log_details AS
 SELECT al.id,
    al.action,
    al.entity_type,
    al.entity_id,
    u.username,
    f.name AS file_name,
    al.row_number,
    al.field_name,
    al.old_value,
    al.new_value,
    al.created_at
   FROM ((public.audit_logs al
     LEFT JOIN public.users u ON ((al.user_id = u.id)))
     LEFT JOIN public.files f ON ((al.file_id = f.id)))
  ORDER BY al.created_at DESC;


ALTER VIEW public.audit_log_details OWNER TO synergygraphics;

--
-- TOC entry 240 (class 1259 OID 16762)
-- Name: audit_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.audit_logs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.audit_logs_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5565 (class 0 OID 0)
-- Dependencies: 240
-- Name: audit_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.audit_logs_id_seq OWNED BY public.audit_logs.id;


--
-- TOC entry 247 (class 1259 OID 16843)
-- Name: dashboard_cache; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.dashboard_cache (
    id integer NOT NULL,
    cache_key character varying(100) NOT NULL,
    data jsonb NOT NULL,
    department_id integer,
    computed_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    expires_at timestamp with time zone DEFAULT (CURRENT_TIMESTAMP + '01:00:00'::interval)
);


ALTER TABLE public.dashboard_cache OWNER TO synergygraphics;

--
-- TOC entry 246 (class 1259 OID 16842)
-- Name: dashboard_cache_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.dashboard_cache_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.dashboard_cache_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5566 (class 0 OID 0)
-- Dependencies: 246
-- Name: dashboard_cache_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.dashboard_cache_id_seq OWNED BY public.dashboard_cache.id;


--
-- TOC entry 221 (class 1259 OID 16499)
-- Name: departments; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.departments (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    description text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.departments OWNER TO synergygraphics;

--
-- TOC entry 220 (class 1259 OID 16498)
-- Name: departments_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.departments_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.departments_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5567 (class 0 OID 0)
-- Dependencies: 220
-- Name: departments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.departments_id_seq OWNED BY public.departments.id;


--
-- TOC entry 273 (class 1259 OID 17265)
-- Name: edit_requests; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.edit_requests (
    id integer NOT NULL,
    sheet_id integer NOT NULL,
    row_number integer NOT NULL,
    column_name character varying(100) NOT NULL,
    cell_reference character varying(20),
    current_value text,
    proposed_value text,
    requested_by integer NOT NULL,
    requester_role character varying(50),
    requester_dept character varying(100),
    requested_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    reviewed_by integer,
    reviewed_at timestamp with time zone,
    reject_reason text,
    expires_at timestamp with time zone
);


ALTER TABLE public.edit_requests OWNER TO synergygraphics;

--
-- TOC entry 272 (class 1259 OID 17264)
-- Name: edit_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.edit_requests_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.edit_requests_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5568 (class 0 OID 0)
-- Dependencies: 272
-- Name: edit_requests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.edit_requests_id_seq OWNED BY public.edit_requests.id;


--
-- TOC entry 231 (class 1259 OID 16621)
-- Name: file_data; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.file_data (
    id integer NOT NULL,
    file_id integer,
    row_number integer NOT NULL,
    data jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.file_data OWNER TO synergygraphics;

--
-- TOC entry 230 (class 1259 OID 16620)
-- Name: file_data_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.file_data_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.file_data_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5569 (class 0 OID 0)
-- Dependencies: 230
-- Name: file_data_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.file_data_id_seq OWNED BY public.file_data.id;


--
-- TOC entry 253 (class 1259 OID 16925)
-- Name: file_details; Type: VIEW; Schema: public; Owner: synergygraphics
--

CREATE VIEW public.file_details AS
 SELECT f.id,
    f.uuid,
    f.name,
    f.original_filename,
    f.file_type,
    d.name AS department_name,
    u.username AS created_by_username,
    f.current_version,
    f.columns,
    f.is_active,
    f.created_at,
    f.updated_at,
    ( SELECT count(*) AS count
           FROM public.file_data fd
          WHERE (fd.file_id = f.id)) AS row_count
   FROM ((public.files f
     LEFT JOIN public.departments d ON ((f.department_id = d.id)))
     LEFT JOIN public.users u ON ((f.created_by = u.id)));


ALTER VIEW public.file_details OWNER TO synergygraphics;

--
-- TOC entry 243 (class 1259 OID 16792)
-- Name: file_permissions; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.file_permissions (
    id integer NOT NULL,
    file_id integer,
    user_id integer,
    permission_level character varying(20) DEFAULT 'read'::character varying NOT NULL,
    granted_by integer,
    granted_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.file_permissions OWNER TO synergygraphics;

--
-- TOC entry 242 (class 1259 OID 16791)
-- Name: file_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.file_permissions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.file_permissions_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5570 (class 0 OID 0)
-- Dependencies: 242
-- Name: file_permissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.file_permissions_id_seq OWNED BY public.file_permissions.id;


--
-- TOC entry 229 (class 1259 OID 16596)
-- Name: file_versions; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.file_versions (
    id integer NOT NULL,
    file_id integer,
    version_number integer NOT NULL,
    file_path text,
    changes_summary text,
    created_by integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.file_versions OWNER TO synergygraphics;

--
-- TOC entry 228 (class 1259 OID 16595)
-- Name: file_versions_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.file_versions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.file_versions_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5571 (class 0 OID 0)
-- Dependencies: 228
-- Name: file_versions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.file_versions_id_seq OWNED BY public.file_versions.id;


--
-- TOC entry 226 (class 1259 OID 16562)
-- Name: files_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.files_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.files_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5572 (class 0 OID 0)
-- Dependencies: 226
-- Name: files_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.files_id_seq OWNED BY public.files.id;


--
-- TOC entry 264 (class 1259 OID 17108)
-- Name: folders; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.folders (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    parent_id integer,
    created_by integer,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    password_hash character varying(255)
);


ALTER TABLE public.folders OWNER TO synergygraphics;

--
-- TOC entry 263 (class 1259 OID 17107)
-- Name: folders_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.folders_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.folders_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5573 (class 0 OID 0)
-- Dependencies: 263
-- Name: folders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.folders_id_seq OWNED BY public.folders.id;


--
-- TOC entry 237 (class 1259 OID 16707)
-- Name: formula_versions; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.formula_versions (
    id integer NOT NULL,
    formula_id integer,
    version_number integer NOT NULL,
    expression text NOT NULL,
    input_columns jsonb DEFAULT '[]'::jsonb,
    output_column character varying(100) NOT NULL,
    created_by integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.formula_versions OWNER TO synergygraphics;

--
-- TOC entry 236 (class 1259 OID 16706)
-- Name: formula_versions_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.formula_versions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.formula_versions_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5574 (class 0 OID 0)
-- Dependencies: 236
-- Name: formula_versions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.formula_versions_id_seq OWNED BY public.formula_versions.id;


--
-- TOC entry 235 (class 1259 OID 16673)
-- Name: formulas; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.formulas (
    id integer NOT NULL,
    uuid uuid DEFAULT public.uuid_generate_v4(),
    name character varying(100) NOT NULL,
    description text,
    expression text NOT NULL,
    input_columns jsonb DEFAULT '[]'::jsonb,
    output_column character varying(100) NOT NULL,
    department_id integer,
    created_by integer,
    is_shared boolean DEFAULT false,
    is_active boolean DEFAULT true,
    version integer DEFAULT 1,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.formulas OWNER TO synergygraphics;

--
-- TOC entry 234 (class 1259 OID 16672)
-- Name: formulas_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.formulas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.formulas_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5575 (class 0 OID 0)
-- Dependencies: 234
-- Name: formulas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.formulas_id_seq OWNED BY public.formulas.id;


--
-- TOC entry 270 (class 1259 OID 17214)
-- Name: inventory_audit_log; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.inventory_audit_log (
    id integer NOT NULL,
    transaction_id integer,
    product_id integer,
    action character varying(20) NOT NULL,
    old_data jsonb,
    new_data jsonb,
    performed_by integer,
    performed_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.inventory_audit_log OWNER TO synergygraphics;

--
-- TOC entry 269 (class 1259 OID 17213)
-- Name: inventory_audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.inventory_audit_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.inventory_audit_log_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5576 (class 0 OID 0)
-- Dependencies: 269
-- Name: inventory_audit_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.inventory_audit_log_id_seq OWNED BY public.inventory_audit_log.id;


--
-- TOC entry 283 (class 1259 OID 17769)
-- Name: inventory_discrepancy_reports; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.inventory_discrepancy_reports (
    id integer NOT NULL,
    product_name character varying(255) NOT NULL,
    qc_code character varying(100),
    excel_stock numeric(14,2) NOT NULL,
    actual_stock numeric(14,2) NOT NULL,
    discrepancy_qty numeric(14,2) NOT NULL,
    notes text,
    status character varying(20) DEFAULT 'open'::character varying NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_by integer,
    resolved_by integer,
    resolved_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.inventory_discrepancy_reports OWNER TO synergygraphics;

--
-- TOC entry 282 (class 1259 OID 17768)
-- Name: inventory_discrepancy_reports_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.inventory_discrepancy_reports_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.inventory_discrepancy_reports_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5577 (class 0 OID 0)
-- Dependencies: 282
-- Name: inventory_discrepancy_reports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.inventory_discrepancy_reports_id_seq OWNED BY public.inventory_discrepancy_reports.id;


--
-- TOC entry 251 (class 1259 OID 16892)
-- Name: sheet_data; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.sheet_data (
    id integer NOT NULL,
    sheet_id integer,
    row_number integer NOT NULL,
    data jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.sheet_data OWNER TO synergygraphics;

--
-- TOC entry 249 (class 1259 OID 16864)
-- Name: sheets; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.sheets (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    columns jsonb DEFAULT '["A", "B", "C", "D", "E"]'::jsonb,
    created_by integer,
    department_id integer,
    is_shared boolean DEFAULT false,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    last_edited_by integer,
    shown_to_viewers boolean DEFAULT false,
    cell_styles jsonb DEFAULT '{}'::jsonb,
    column_widths jsonb DEFAULT '{}'::jsonb,
    row_heights jsonb DEFAULT '{}'::jsonb,
    merged_cells jsonb DEFAULT '{}'::jsonb,
    folder_id integer,
    password_hash character varying(255),
    grid_meta jsonb DEFAULT '{}'::jsonb
);


ALTER TABLE public.sheets OWNER TO synergygraphics;

--
-- TOC entry 285 (class 1259 OID 25931)
-- Name: inventory_tracker_rows; Type: VIEW; Schema: public; Owner: synergygraphics
--

CREATE VIEW public.inventory_tracker_rows AS
 WITH inv_keys AS (
         SELECT s_1.id AS sheet_id,
            ( SELECT c.value AS c
                   FROM jsonb_array_elements_text(COALESCE(s_1.columns, '[]'::jsonb)) c(value)
                  WHERE (c.value ~~ 'INV:product_name|%'::text)
                 LIMIT 1) AS inv_product_key,
            ( SELECT c.value AS c
                   FROM jsonb_array_elements_text(COALESCE(s_1.columns, '[]'::jsonb)) c(value)
                  WHERE (c.value ~~ 'INV:code|%'::text)
                 LIMIT 1) AS inv_code_key
           FROM public.sheets s_1
        )
 SELECT sd.id AS sheet_data_id,
    sd.sheet_id,
    s.name AS sheet_name,
    sd.row_number,
    COALESCE(NULLIF((sd.data ->> 'Material Name'::text), ''::text), NULLIF((sd.data ->> 'Product Name'::text), ''::text), NULLIF((sd.data ->> ik.inv_product_key), ''::text)) AS material_name,
    COALESCE(NULLIF((sd.data ->> 'QB Code'::text), ''::text), NULLIF((sd.data ->> 'QC Code'::text), ''::text), NULLIF((sd.data ->> ik.inv_code_key), ''::text)) AS qb_code,
    (sd.data ->> 'Stock'::text) AS stock_text,
        CASE
            WHEN (NULLIF((sd.data ->> 'Stock'::text), ''::text) ~ '^[+-]?[0-9]+([.][0-9]+)?$'::text) THEN ((sd.data ->> 'Stock'::text))::numeric
            ELSE NULL::numeric
        END AS stock_num,
    (sd.data ->> 'Maintaining Qty'::text) AS maintaining_qty,
    (sd.data ->> 'Maintaining Unit'::text) AS maintaining_unit,
    (sd.data ->> 'Maintaining'::text) AS maintaining_legacy,
    (sd.data ->> 'Critical'::text) AS critical_text,
        CASE
            WHEN (NULLIF((sd.data ->> 'Critical'::text), ''::text) ~ '^[+-]?[0-9]+([.][0-9]+)?$'::text) THEN ((sd.data ->> 'Critical'::text))::numeric
            ELSE NULL::numeric
        END AS critical_num,
    (sd.data ->> 'Total Quantity'::text) AS total_quantity_text,
        CASE
            WHEN (NULLIF((sd.data ->> 'Total Quantity'::text), ''::text) ~ '^[+-]?[0-9]+([.][0-9]+)?$'::text) THEN ((sd.data ->> 'Total Quantity'::text))::numeric
            ELSE NULL::numeric
        END AS total_quantity_num,
    sd.data AS raw_data,
    sd.created_at,
    sd.updated_at
   FROM ((public.sheet_data sd
     JOIN public.sheets s ON ((s.id = sd.sheet_id)))
     LEFT JOIN inv_keys ik ON ((ik.sheet_id = s.id)))
  WHERE ((s.is_active = true) AND (s.columns ? 'Stock'::text) AND (s.columns ? 'Total Quantity'::text) AND ((s.columns ? 'Material Name'::text) OR (s.columns ? 'Product Name'::text) OR (ik.inv_product_key IS NOT NULL)) AND ((s.columns ? 'QB Code'::text) OR (s.columns ? 'QC Code'::text) OR (ik.inv_code_key IS NOT NULL)));


ALTER VIEW public.inventory_tracker_rows OWNER TO synergygraphics;

--
-- TOC entry 268 (class 1259 OID 17174)
-- Name: inventory_transactions; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.inventory_transactions (
    id integer NOT NULL,
    product_id integer NOT NULL,
    transaction_date date DEFAULT CURRENT_DATE NOT NULL,
    qty_in integer DEFAULT 0 NOT NULL,
    qty_out integer DEFAULT 0 NOT NULL,
    reference_no character varying(255),
    remarks text,
    created_by integer,
    updated_by integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT inventory_transactions_qty_in_check CHECK ((qty_in >= 0)),
    CONSTRAINT inventory_transactions_qty_out_check CHECK ((qty_out >= 0))
);


ALTER TABLE public.inventory_transactions OWNER TO synergygraphics;

--
-- TOC entry 267 (class 1259 OID 17173)
-- Name: inventory_transactions_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.inventory_transactions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.inventory_transactions_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5578 (class 0 OID 0)
-- Dependencies: 267
-- Name: inventory_transactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.inventory_transactions_id_seq OWNED BY public.inventory_transactions.id;


--
-- TOC entry 266 (class 1259 OID 17145)
-- Name: product_master; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.product_master (
    id integer NOT NULL,
    product_name character varying(255) NOT NULL,
    qc_code character varying(100),
    maintaining_qty integer DEFAULT 0 NOT NULL,
    critical_qty integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true,
    created_by integer,
    updated_by integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.product_master OWNER TO synergygraphics;

--
-- TOC entry 265 (class 1259 OID 17144)
-- Name: product_master_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.product_master_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.product_master_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5579 (class 0 OID 0)
-- Dependencies: 265
-- Name: product_master_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.product_master_id_seq OWNED BY public.product_master.id;


--
-- TOC entry 271 (class 1259 OID 17246)
-- Name: product_stock_snapshot; Type: VIEW; Schema: public; Owner: synergygraphics
--

CREATE VIEW public.product_stock_snapshot AS
 SELECT p.id,
    p.product_name,
    p.qc_code,
    p.maintaining_qty,
    p.critical_qty,
    p.is_active,
    COALESCE(sum(t.qty_in), (0)::bigint) AS total_in,
    COALESCE(sum(t.qty_out), (0)::bigint) AS total_out,
    (COALESCE(sum(t.qty_in), (0)::bigint) - COALESCE(sum(t.qty_out), (0)::bigint)) AS current_stock,
        CASE
            WHEN ((COALESCE(sum(t.qty_in), (0)::bigint) - COALESCE(sum(t.qty_out), (0)::bigint)) <= p.critical_qty) THEN 'critical'::text
            WHEN ((COALESCE(sum(t.qty_in), (0)::bigint) - COALESCE(sum(t.qty_out), (0)::bigint)) <= p.maintaining_qty) THEN 'warning'::text
            ELSE 'ok'::text
        END AS stock_status
   FROM (public.product_master p
     LEFT JOIN public.inventory_transactions t ON ((p.id = t.product_id)))
  WHERE (p.is_active = true)
  GROUP BY p.id, p.product_name, p.qc_code, p.maintaining_qty, p.critical_qty, p.is_active
  ORDER BY p.product_name;


ALTER VIEW public.product_stock_snapshot OWNER TO synergygraphics;

--
-- TOC entry 281 (class 1259 OID 17584)
-- Name: production_lines; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.production_lines (
    id integer NOT NULL,
    name character varying(120) NOT NULL,
    description text,
    is_active boolean DEFAULT true NOT NULL,
    created_by integer,
    updated_by integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.production_lines OWNER TO synergygraphics;

--
-- TOC entry 280 (class 1259 OID 17583)
-- Name: production_lines_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.production_lines_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.production_lines_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5580 (class 0 OID 0)
-- Dependencies: 280
-- Name: production_lines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.production_lines_id_seq OWNED BY public.production_lines.id;


--
-- TOC entry 223 (class 1259 OID 16514)
-- Name: roles; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.roles (
    id integer NOT NULL,
    name character varying(50) NOT NULL,
    description text,
    permissions jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.roles OWNER TO synergygraphics;

--
-- TOC entry 222 (class 1259 OID 16513)
-- Name: roles_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.roles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.roles_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5581 (class 0 OID 0)
-- Dependencies: 222
-- Name: roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.roles_id_seq OWNED BY public.roles.id;


--
-- TOC entry 233 (class 1259 OID 16644)
-- Name: row_locks; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.row_locks (
    id integer NOT NULL,
    file_id integer,
    row_id integer,
    locked_by integer,
    locked_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    expires_at timestamp with time zone DEFAULT (CURRENT_TIMESTAMP + '00:05:00'::interval)
);


ALTER TABLE public.row_locks OWNER TO synergygraphics;

--
-- TOC entry 232 (class 1259 OID 16643)
-- Name: row_locks_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.row_locks_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.row_locks_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5582 (class 0 OID 0)
-- Dependencies: 232
-- Name: row_locks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.row_locks_id_seq OWNED BY public.row_locks.id;


--
-- TOC entry 262 (class 1259 OID 17072)
-- Name: sheet_access; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.sheet_access (
    id integer NOT NULL,
    sheet_id integer,
    user_id integer,
    granted_by integer,
    granted_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.sheet_access OWNER TO synergygraphics;

--
-- TOC entry 5583 (class 0 OID 0)
-- Dependencies: 262
-- Name: TABLE sheet_access; Type: COMMENT; Schema: public; Owner: synergygraphics
--

COMMENT ON TABLE public.sheet_access IS 'Controls which users have access to specific sheets';


--
-- TOC entry 5584 (class 0 OID 0)
-- Dependencies: 262
-- Name: COLUMN sheet_access.sheet_id; Type: COMMENT; Schema: public; Owner: synergygraphics
--

COMMENT ON COLUMN public.sheet_access.sheet_id IS 'Reference to the sheet';


--
-- TOC entry 5585 (class 0 OID 0)
-- Dependencies: 262
-- Name: COLUMN sheet_access.user_id; Type: COMMENT; Schema: public; Owner: synergygraphics
--

COMMENT ON COLUMN public.sheet_access.user_id IS 'User who has access to the sheet';


--
-- TOC entry 5586 (class 0 OID 0)
-- Dependencies: 262
-- Name: COLUMN sheet_access.granted_by; Type: COMMENT; Schema: public; Owner: synergygraphics
--

COMMENT ON COLUMN public.sheet_access.granted_by IS 'User who granted the access';


--
-- TOC entry 261 (class 1259 OID 17071)
-- Name: sheet_access_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.sheet_access_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sheet_access_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5588 (class 0 OID 0)
-- Dependencies: 261
-- Name: sheet_access_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.sheet_access_id_seq OWNED BY public.sheet_access.id;


--
-- TOC entry 250 (class 1259 OID 16891)
-- Name: sheet_data_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.sheet_data_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sheet_data_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5589 (class 0 OID 0)
-- Dependencies: 250
-- Name: sheet_data_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.sheet_data_id_seq OWNED BY public.sheet_data.id;


--
-- TOC entry 284 (class 1259 OID 25927)
-- Name: sheet_data_kv; Type: VIEW; Schema: public; Owner: synergygraphics
--

CREATE VIEW public.sheet_data_kv AS
 SELECT sd.id AS sheet_data_id,
    sd.sheet_id,
    sd.row_number,
    kv.key AS column_name,
    kv.value AS cell_value,
    sd.created_at,
    sd.updated_at
   FROM (public.sheet_data sd
     CROSS JOIN LATERAL jsonb_each_text(COALESCE(sd.data, '{}'::jsonb)) kv(key, value));


ALTER VIEW public.sheet_data_kv OWNER TO synergygraphics;

--
-- TOC entry 260 (class 1259 OID 16984)
-- Name: sheet_edit_history; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.sheet_edit_history (
    id integer NOT NULL,
    sheet_id integer,
    row_number integer,
    column_name character varying(100),
    old_value text,
    new_value text,
    edited_by integer,
    edited_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    action character varying(50) NOT NULL
);


ALTER TABLE public.sheet_edit_history OWNER TO synergygraphics;

--
-- TOC entry 259 (class 1259 OID 16983)
-- Name: sheet_edit_history_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.sheet_edit_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sheet_edit_history_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5590 (class 0 OID 0)
-- Dependencies: 259
-- Name: sheet_edit_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.sheet_edit_history_id_seq OWNED BY public.sheet_edit_history.id;


--
-- TOC entry 258 (class 1259 OID 16961)
-- Name: sheet_edit_sessions; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.sheet_edit_sessions (
    id integer NOT NULL,
    sheet_id integer,
    user_id integer,
    started_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    last_activity timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    is_active boolean DEFAULT true
);


ALTER TABLE public.sheet_edit_sessions OWNER TO synergygraphics;

--
-- TOC entry 257 (class 1259 OID 16960)
-- Name: sheet_edit_sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.sheet_edit_sessions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sheet_edit_sessions_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5591 (class 0 OID 0)
-- Dependencies: 257
-- Name: sheet_edit_sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.sheet_edit_sessions_id_seq OWNED BY public.sheet_edit_sessions.id;


--
-- TOC entry 279 (class 1259 OID 17537)
-- Name: sheet_links; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.sheet_links (
    link_id integer NOT NULL,
    source_sheet_id integer NOT NULL,
    target_sheet_id integer NOT NULL,
    link_type character varying(64) NOT NULL,
    column_mapping jsonb DEFAULT '{}'::jsonb NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    created_by integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.sheet_links OWNER TO synergygraphics;

--
-- TOC entry 278 (class 1259 OID 17533)
-- Name: sheet_links_link_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.sheet_links_link_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sheet_links_link_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5592 (class 0 OID 0)
-- Dependencies: 278
-- Name: sheet_links_link_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.sheet_links_link_id_seq OWNED BY public.sheet_links.link_id;


--
-- TOC entry 256 (class 1259 OID 16937)
-- Name: sheet_locks; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.sheet_locks (
    id integer NOT NULL,
    sheet_id integer,
    locked_by integer,
    locked_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    expires_at timestamp with time zone DEFAULT (CURRENT_TIMESTAMP + '00:30:00'::interval)
);


ALTER TABLE public.sheet_locks OWNER TO synergygraphics;

--
-- TOC entry 255 (class 1259 OID 16936)
-- Name: sheet_locks_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.sheet_locks_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sheet_locks_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5593 (class 0 OID 0)
-- Dependencies: 255
-- Name: sheet_locks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.sheet_locks_id_seq OWNED BY public.sheet_locks.id;


--
-- TOC entry 277 (class 1259 OID 17331)
-- Name: sheet_versions; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.sheet_versions (
    id integer NOT NULL,
    sheet_id integer NOT NULL,
    user_id integer,
    version_data jsonb NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.sheet_versions OWNER TO synergygraphics;

--
-- TOC entry 276 (class 1259 OID 17330)
-- Name: sheet_versions_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.sheet_versions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sheet_versions_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5594 (class 0 OID 0)
-- Dependencies: 276
-- Name: sheet_versions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.sheet_versions_id_seq OWNED BY public.sheet_versions.id;


--
-- TOC entry 248 (class 1259 OID 16863)
-- Name: sheets_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.sheets_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sheets_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5595 (class 0 OID 0)
-- Dependencies: 248
-- Name: sheets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.sheets_id_seq OWNED BY public.sheets.id;


--
-- TOC entry 252 (class 1259 OID 16920)
-- Name: user_details; Type: VIEW; Schema: public; Owner: synergygraphics
--

CREATE VIEW public.user_details AS
 SELECT u.id,
    u.username,
    u.email,
    u.full_name,
    r.name AS role_name,
    d.name AS department_name,
    u.is_active,
    u.last_login,
    u.created_at
   FROM ((public.users u
     LEFT JOIN public.roles r ON ((u.role_id = r.id)))
     LEFT JOIN public.departments d ON ((u.department_id = d.id)));


ALTER VIEW public.user_details OWNER TO synergygraphics;

--
-- TOC entry 245 (class 1259 OID 16822)
-- Name: user_sessions; Type: TABLE; Schema: public; Owner: synergygraphics
--

CREATE TABLE public.user_sessions (
    id integer NOT NULL,
    user_id integer,
    token_hash character varying(255) NOT NULL,
    device_info text,
    ip_address inet,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    expires_at timestamp with time zone,
    last_activity timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.user_sessions OWNER TO synergygraphics;

--
-- TOC entry 244 (class 1259 OID 16821)
-- Name: user_sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.user_sessions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.user_sessions_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5596 (class 0 OID 0)
-- Dependencies: 244
-- Name: user_sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.user_sessions_id_seq OWNED BY public.user_sessions.id;


--
-- TOC entry 224 (class 1259 OID 16528)
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: synergygraphics
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.users_id_seq OWNER TO synergygraphics;

--
-- TOC entry 5597 (class 0 OID 0)
-- Dependencies: 224
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: synergygraphics
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- TOC entry 5142 (class 2604 OID 17309)
-- Name: active_users id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.active_users ALTER COLUMN id SET DEFAULT nextval('public.active_users_id_seq'::regclass);


--
-- TOC entry 5078 (class 2604 OID 16737)
-- Name: applied_formulas id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.applied_formulas ALTER COLUMN id SET DEFAULT nextval('public.applied_formulas_id_seq'::regclass);


--
-- TOC entry 5081 (class 2604 OID 16766)
-- Name: audit_logs id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.audit_logs ALTER COLUMN id SET DEFAULT nextval('public.audit_logs_id_seq'::regclass);


--
-- TOC entry 5091 (class 2604 OID 16846)
-- Name: dashboard_cache id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.dashboard_cache ALTER COLUMN id SET DEFAULT nextval('public.dashboard_cache_id_seq'::regclass);


--
-- TOC entry 5039 (class 2604 OID 16502)
-- Name: departments id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.departments ALTER COLUMN id SET DEFAULT nextval('public.departments_id_seq'::regclass);


--
-- TOC entry 5139 (class 2604 OID 17268)
-- Name: edit_requests id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.edit_requests ALTER COLUMN id SET DEFAULT nextval('public.edit_requests_id_seq'::regclass);


--
-- TOC entry 5061 (class 2604 OID 16624)
-- Name: file_data id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.file_data ALTER COLUMN id SET DEFAULT nextval('public.file_data_id_seq'::regclass);


--
-- TOC entry 5084 (class 2604 OID 16795)
-- Name: file_permissions id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.file_permissions ALTER COLUMN id SET DEFAULT nextval('public.file_permissions_id_seq'::regclass);


--
-- TOC entry 5059 (class 2604 OID 16599)
-- Name: file_versions id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.file_versions ALTER COLUMN id SET DEFAULT nextval('public.file_versions_id_seq'::regclass);


--
-- TOC entry 5050 (class 2604 OID 16566)
-- Name: files id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.files ALTER COLUMN id SET DEFAULT nextval('public.files_id_seq'::regclass);


--
-- TOC entry 5121 (class 2604 OID 17111)
-- Name: folders id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.folders ALTER COLUMN id SET DEFAULT nextval('public.folders_id_seq'::regclass);


--
-- TOC entry 5075 (class 2604 OID 16710)
-- Name: formula_versions id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.formula_versions ALTER COLUMN id SET DEFAULT nextval('public.formula_versions_id_seq'::regclass);


--
-- TOC entry 5067 (class 2604 OID 16676)
-- Name: formulas id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.formulas ALTER COLUMN id SET DEFAULT nextval('public.formulas_id_seq'::regclass);


--
-- TOC entry 5137 (class 2604 OID 17217)
-- Name: inventory_audit_log id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.inventory_audit_log ALTER COLUMN id SET DEFAULT nextval('public.inventory_audit_log_id_seq'::regclass);


--
-- TOC entry 5155 (class 2604 OID 17772)
-- Name: inventory_discrepancy_reports id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.inventory_discrepancy_reports ALTER COLUMN id SET DEFAULT nextval('public.inventory_discrepancy_reports_id_seq'::regclass);


--
-- TOC entry 5131 (class 2604 OID 17177)
-- Name: inventory_transactions id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.inventory_transactions ALTER COLUMN id SET DEFAULT nextval('public.inventory_transactions_id_seq'::regclass);


--
-- TOC entry 5125 (class 2604 OID 17148)
-- Name: product_master id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.product_master ALTER COLUMN id SET DEFAULT nextval('public.product_master_id_seq'::regclass);


--
-- TOC entry 5151 (class 2604 OID 17587)
-- Name: production_lines id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.production_lines ALTER COLUMN id SET DEFAULT nextval('public.production_lines_id_seq'::regclass);


--
-- TOC entry 5042 (class 2604 OID 16517)
-- Name: roles id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.roles ALTER COLUMN id SET DEFAULT nextval('public.roles_id_seq'::regclass);


--
-- TOC entry 5064 (class 2604 OID 16647)
-- Name: row_locks id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.row_locks ALTER COLUMN id SET DEFAULT nextval('public.row_locks_id_seq'::regclass);


--
-- TOC entry 5119 (class 2604 OID 17075)
-- Name: sheet_access id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_access ALTER COLUMN id SET DEFAULT nextval('public.sheet_access_id_seq'::regclass);


--
-- TOC entry 5106 (class 2604 OID 16895)
-- Name: sheet_data id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_data ALTER COLUMN id SET DEFAULT nextval('public.sheet_data_id_seq'::regclass);


--
-- TOC entry 5117 (class 2604 OID 16987)
-- Name: sheet_edit_history id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_edit_history ALTER COLUMN id SET DEFAULT nextval('public.sheet_edit_history_id_seq'::regclass);


--
-- TOC entry 5113 (class 2604 OID 16964)
-- Name: sheet_edit_sessions id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_edit_sessions ALTER COLUMN id SET DEFAULT nextval('public.sheet_edit_sessions_id_seq'::regclass);


--
-- TOC entry 5146 (class 2604 OID 17543)
-- Name: sheet_links link_id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_links ALTER COLUMN link_id SET DEFAULT nextval('public.sheet_links_link_id_seq'::regclass);


--
-- TOC entry 5110 (class 2604 OID 16940)
-- Name: sheet_locks id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_locks ALTER COLUMN id SET DEFAULT nextval('public.sheet_locks_id_seq'::regclass);


--
-- TOC entry 5144 (class 2604 OID 17334)
-- Name: sheet_versions id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_versions ALTER COLUMN id SET DEFAULT nextval('public.sheet_versions_id_seq'::regclass);


--
-- TOC entry 5094 (class 2604 OID 16867)
-- Name: sheets id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheets ALTER COLUMN id SET DEFAULT nextval('public.sheets_id_seq'::regclass);


--
-- TOC entry 5087 (class 2604 OID 16825)
-- Name: user_sessions id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.user_sessions ALTER COLUMN id SET DEFAULT nextval('public.user_sessions_id_seq'::regclass);


--
-- TOC entry 5045 (class 2604 OID 16532)
-- Name: users id; Type: DEFAULT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- TOC entry 5306 (class 2606 OID 17316)
-- Name: active_users active_users_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.active_users
    ADD CONSTRAINT active_users_pkey PRIMARY KEY (id);


--
-- TOC entry 5308 (class 2606 OID 17318)
-- Name: active_users active_users_user_id_sheet_id_key; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.active_users
    ADD CONSTRAINT active_users_user_id_sheet_id_key UNIQUE (user_id, sheet_id);


--
-- TOC entry 5214 (class 2606 OID 16746)
-- Name: applied_formulas applied_formulas_file_id_formula_id_key; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.applied_formulas
    ADD CONSTRAINT applied_formulas_file_id_formula_id_key UNIQUE (file_id, formula_id);


--
-- TOC entry 5216 (class 2606 OID 16744)
-- Name: applied_formulas applied_formulas_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.applied_formulas
    ADD CONSTRAINT applied_formulas_pkey PRIMARY KEY (id);


--
-- TOC entry 5218 (class 2606 OID 16775)
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- TOC entry 5237 (class 2606 OID 16857)
-- Name: dashboard_cache dashboard_cache_cache_key_key; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.dashboard_cache
    ADD CONSTRAINT dashboard_cache_cache_key_key UNIQUE (cache_key);


--
-- TOC entry 5239 (class 2606 OID 16855)
-- Name: dashboard_cache dashboard_cache_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.dashboard_cache
    ADD CONSTRAINT dashboard_cache_pkey PRIMARY KEY (id);


--
-- TOC entry 5163 (class 2606 OID 16512)
-- Name: departments departments_name_key; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_name_key UNIQUE (name);


--
-- TOC entry 5165 (class 2606 OID 16510)
-- Name: departments departments_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_pkey PRIMARY KEY (id);


--
-- TOC entry 5299 (class 2606 OID 17280)
-- Name: edit_requests edit_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.edit_requests
    ADD CONSTRAINT edit_requests_pkey PRIMARY KEY (id);


--
-- TOC entry 5192 (class 2606 OID 16635)
-- Name: file_data file_data_file_id_row_number_key; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.file_data
    ADD CONSTRAINT file_data_file_id_row_number_key UNIQUE (file_id, row_number);


--
-- TOC entry 5194 (class 2606 OID 16633)
-- Name: file_data file_data_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.file_data
    ADD CONSTRAINT file_data_pkey PRIMARY KEY (id);


--
-- TOC entry 5227 (class 2606 OID 16803)
-- Name: file_permissions file_permissions_file_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.file_permissions
    ADD CONSTRAINT file_permissions_file_id_user_id_key UNIQUE (file_id, user_id);


--
-- TOC entry 5229 (class 2606 OID 16801)
-- Name: file_permissions file_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.file_permissions
    ADD CONSTRAINT file_permissions_pkey PRIMARY KEY (id);


--
-- TOC entry 5187 (class 2606 OID 16608)
-- Name: file_versions file_versions_file_id_version_number_key; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.file_versions
    ADD CONSTRAINT file_versions_file_id_version_number_key UNIQUE (file_id, version_number);


--
-- TOC entry 5189 (class 2606 OID 16606)
-- Name: file_versions file_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.file_versions
    ADD CONSTRAINT file_versions_pkey PRIMARY KEY (id);


--
-- TOC entry 5180 (class 2606 OID 16580)
-- Name: files files_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.files
    ADD CONSTRAINT files_pkey PRIMARY KEY (id);


--
-- TOC entry 5182 (class 2606 OID 16582)
-- Name: files files_uuid_key; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.files
    ADD CONSTRAINT files_uuid_key UNIQUE (uuid);


--
-- TOC entry 5278 (class 2606 OID 17118)
-- Name: folders folders_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.folders
    ADD CONSTRAINT folders_pkey PRIMARY KEY (id);


--
-- TOC entry 5210 (class 2606 OID 16722)
-- Name: formula_versions formula_versions_formula_id_version_number_key; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.formula_versions
    ADD CONSTRAINT formula_versions_formula_id_version_number_key UNIQUE (formula_id, version_number);


--
-- TOC entry 5212 (class 2606 OID 16720)
-- Name: formula_versions formula_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.formula_versions
    ADD CONSTRAINT formula_versions_pkey PRIMARY KEY (id);


--
-- TOC entry 5204 (class 2606 OID 16691)
-- Name: formulas formulas_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.formulas
    ADD CONSTRAINT formulas_pkey PRIMARY KEY (id);


--
-- TOC entry 5206 (class 2606 OID 16693)
-- Name: formulas formulas_uuid_key; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.formulas
    ADD CONSTRAINT formulas_uuid_key UNIQUE (uuid);


--
-- TOC entry 5297 (class 2606 OID 17224)
-- Name: inventory_audit_log inventory_audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.inventory_audit_log
    ADD CONSTRAINT inventory_audit_log_pkey PRIMARY KEY (id);


--
-- TOC entry 5328 (class 2606 OID 17792)
-- Name: inventory_discrepancy_reports inventory_discrepancy_reports_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.inventory_discrepancy_reports
    ADD CONSTRAINT inventory_discrepancy_reports_pkey PRIMARY KEY (id);


--
-- TOC entry 5291 (class 2606 OID 17193)
-- Name: inventory_transactions inventory_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.inventory_transactions
    ADD CONSTRAINT inventory_transactions_pkey PRIMARY KEY (id);


--
-- TOC entry 5285 (class 2606 OID 17159)
-- Name: product_master product_master_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.product_master
    ADD CONSTRAINT product_master_pkey PRIMARY KEY (id);


--
-- TOC entry 5322 (class 2606 OID 17601)
-- Name: production_lines production_lines_name_key; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.production_lines
    ADD CONSTRAINT production_lines_name_key UNIQUE (name);


--
-- TOC entry 5324 (class 2606 OID 17599)
-- Name: production_lines production_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.production_lines
    ADD CONSTRAINT production_lines_pkey PRIMARY KEY (id);


--
-- TOC entry 5167 (class 2606 OID 16527)
-- Name: roles roles_name_key; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_name_key UNIQUE (name);


--
-- TOC entry 5169 (class 2606 OID 16525)
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- TOC entry 5200 (class 2606 OID 16654)
-- Name: row_locks row_locks_file_id_row_id_key; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.row_locks
    ADD CONSTRAINT row_locks_file_id_row_id_key UNIQUE (file_id, row_id);


--
-- TOC entry 5202 (class 2606 OID 16652)
-- Name: row_locks row_locks_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.row_locks
    ADD CONSTRAINT row_locks_pkey PRIMARY KEY (id);


--
-- TOC entry 5274 (class 2606 OID 17079)
-- Name: sheet_access sheet_access_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_access
    ADD CONSTRAINT sheet_access_pkey PRIMARY KEY (id);


--
-- TOC entry 5276 (class 2606 OID 17081)
-- Name: sheet_access sheet_access_sheet_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_access
    ADD CONSTRAINT sheet_access_sheet_id_user_id_key UNIQUE (sheet_id, user_id);


--
-- TOC entry 5251 (class 2606 OID 16904)
-- Name: sheet_data sheet_data_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_data
    ADD CONSTRAINT sheet_data_pkey PRIMARY KEY (id);


--
-- TOC entry 5253 (class 2606 OID 16906)
-- Name: sheet_data sheet_data_sheet_id_row_number_key; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_data
    ADD CONSTRAINT sheet_data_sheet_id_row_number_key UNIQUE (sheet_id, row_number);


--
-- TOC entry 5270 (class 2606 OID 16994)
-- Name: sheet_edit_history sheet_edit_history_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_edit_history
    ADD CONSTRAINT sheet_edit_history_pkey PRIMARY KEY (id);


--
-- TOC entry 5263 (class 2606 OID 16970)
-- Name: sheet_edit_sessions sheet_edit_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_edit_sessions
    ADD CONSTRAINT sheet_edit_sessions_pkey PRIMARY KEY (id);


--
-- TOC entry 5265 (class 2606 OID 17062)
-- Name: sheet_edit_sessions sheet_edit_sessions_sheet_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_edit_sessions
    ADD CONSTRAINT sheet_edit_sessions_sheet_id_user_id_key UNIQUE (sheet_id, user_id);


--
-- TOC entry 5317 (class 2606 OID 17562)
-- Name: sheet_links sheet_links_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_links
    ADD CONSTRAINT sheet_links_pkey PRIMARY KEY (link_id);


--
-- TOC entry 5319 (class 2606 OID 17564)
-- Name: sheet_links sheet_links_source_sheet_id_target_sheet_id_link_type_key; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_links
    ADD CONSTRAINT sheet_links_source_sheet_id_target_sheet_id_link_type_key UNIQUE (source_sheet_id, target_sheet_id, link_type);


--
-- TOC entry 5257 (class 2606 OID 16945)
-- Name: sheet_locks sheet_locks_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_locks
    ADD CONSTRAINT sheet_locks_pkey PRIMARY KEY (id);


--
-- TOC entry 5259 (class 2606 OID 16947)
-- Name: sheet_locks sheet_locks_sheet_id_key; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_locks
    ADD CONSTRAINT sheet_locks_sheet_id_key UNIQUE (sheet_id);


--
-- TOC entry 5312 (class 2606 OID 17343)
-- Name: sheet_versions sheet_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_versions
    ADD CONSTRAINT sheet_versions_pkey PRIMARY KEY (id);


--
-- TOC entry 5248 (class 2606 OID 16878)
-- Name: sheets sheets_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheets
    ADD CONSTRAINT sheets_pkey PRIMARY KEY (id);


--
-- TOC entry 5304 (class 2606 OID 17282)
-- Name: edit_requests uq_edit_request_pending; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.edit_requests
    ADD CONSTRAINT uq_edit_request_pending UNIQUE NULLS NOT DISTINCT (sheet_id, row_number, column_name, requested_by, status);


--
-- TOC entry 5235 (class 2606 OID 16834)
-- Name: user_sessions user_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.user_sessions
    ADD CONSTRAINT user_sessions_pkey PRIMARY KEY (id);


--
-- TOC entry 5174 (class 2606 OID 16548)
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- TOC entry 5176 (class 2606 OID 16544)
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- TOC entry 5178 (class 2606 OID 16546)
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- TOC entry 5309 (class 1259 OID 17329)
-- Name: idx_active_users_sheet_last_active; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_active_users_sheet_last_active ON public.active_users USING btree (sheet_id, last_active_timestamp DESC);


--
-- TOC entry 5219 (class 1259 OID 16787)
-- Name: idx_audit_action; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_audit_action ON public.audit_logs USING btree (action);


--
-- TOC entry 5220 (class 1259 OID 16790)
-- Name: idx_audit_created; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_audit_created ON public.audit_logs USING btree (created_at);


--
-- TOC entry 5221 (class 1259 OID 16788)
-- Name: idx_audit_entity; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_audit_entity ON public.audit_logs USING btree (entity_type, entity_id);


--
-- TOC entry 5222 (class 1259 OID 16789)
-- Name: idx_audit_file; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_audit_file ON public.audit_logs USING btree (file_id);


--
-- TOC entry 5223 (class 1259 OID 17263)
-- Name: idx_audit_logs_cell_ref; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_audit_logs_cell_ref ON public.audit_logs USING btree (cell_reference);


--
-- TOC entry 5224 (class 1259 OID 17262)
-- Name: idx_audit_logs_sheet_id; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_audit_logs_sheet_id ON public.audit_logs USING btree (sheet_id);


--
-- TOC entry 5225 (class 1259 OID 16786)
-- Name: idx_audit_user; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_audit_user ON public.audit_logs USING btree (user_id);


--
-- TOC entry 5325 (class 1259 OID 17806)
-- Name: idx_discrepancy_reports_product; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_discrepancy_reports_product ON public.inventory_discrepancy_reports USING btree (lower(TRIM(BOTH FROM product_name)), lower(COALESCE(TRIM(BOTH FROM qc_code), ''::text)));


--
-- TOC entry 5326 (class 1259 OID 17807)
-- Name: idx_discrepancy_reports_status; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_discrepancy_reports_status ON public.inventory_discrepancy_reports USING btree (status, is_active, created_at DESC);


--
-- TOC entry 5300 (class 1259 OID 17300)
-- Name: idx_edit_requests_requester; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_edit_requests_requester ON public.edit_requests USING btree (requested_by);


--
-- TOC entry 5301 (class 1259 OID 17298)
-- Name: idx_edit_requests_sheet; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_edit_requests_sheet ON public.edit_requests USING btree (sheet_id);


--
-- TOC entry 5302 (class 1259 OID 17299)
-- Name: idx_edit_requests_status; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_edit_requests_status ON public.edit_requests USING btree (status);


--
-- TOC entry 5195 (class 1259 OID 16641)
-- Name: idx_file_data_file; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_file_data_file ON public.file_data USING btree (file_id);


--
-- TOC entry 5196 (class 1259 OID 16642)
-- Name: idx_file_data_row; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_file_data_row ON public.file_data USING btree (file_id, row_number);


--
-- TOC entry 5230 (class 1259 OID 16819)
-- Name: idx_file_permissions_file; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_file_permissions_file ON public.file_permissions USING btree (file_id);


--
-- TOC entry 5231 (class 1259 OID 16820)
-- Name: idx_file_permissions_user; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_file_permissions_user ON public.file_permissions USING btree (user_id);


--
-- TOC entry 5190 (class 1259 OID 16619)
-- Name: idx_file_versions_file; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_file_versions_file ON public.file_versions USING btree (file_id);


--
-- TOC entry 5183 (class 1259 OID 16594)
-- Name: idx_files_created_by; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_files_created_by ON public.files USING btree (created_by);


--
-- TOC entry 5184 (class 1259 OID 16593)
-- Name: idx_files_department; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_files_department ON public.files USING btree (department_id);


--
-- TOC entry 5185 (class 1259 OID 17136)
-- Name: idx_files_folder; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_files_folder ON public.files USING btree (folder_id);


--
-- TOC entry 5279 (class 1259 OID 17129)
-- Name: idx_folders_parent; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_folders_parent ON public.folders USING btree (parent_id);


--
-- TOC entry 5280 (class 1259 OID 17130)
-- Name: idx_folders_user; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_folders_user ON public.folders USING btree (created_by);


--
-- TOC entry 5207 (class 1259 OID 16705)
-- Name: idx_formulas_created_by; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_formulas_created_by ON public.formulas USING btree (created_by);


--
-- TOC entry 5208 (class 1259 OID 16704)
-- Name: idx_formulas_department; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_formulas_department ON public.formulas USING btree (department_id);


--
-- TOC entry 5292 (class 1259 OID 17243)
-- Name: idx_inv_audit_date; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_inv_audit_date ON public.inventory_audit_log USING btree (performed_at);


--
-- TOC entry 5293 (class 1259 OID 17241)
-- Name: idx_inv_audit_product; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_inv_audit_product ON public.inventory_audit_log USING btree (product_id);


--
-- TOC entry 5294 (class 1259 OID 17240)
-- Name: idx_inv_audit_tx; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_inv_audit_tx ON public.inventory_audit_log USING btree (transaction_id);


--
-- TOC entry 5295 (class 1259 OID 17242)
-- Name: idx_inv_audit_user; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_inv_audit_user ON public.inventory_audit_log USING btree (performed_by);


--
-- TOC entry 5286 (class 1259 OID 17212)
-- Name: idx_inv_tx_created_by; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_inv_tx_created_by ON public.inventory_transactions USING btree (created_by);


--
-- TOC entry 5287 (class 1259 OID 17210)
-- Name: idx_inv_tx_date; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_inv_tx_date ON public.inventory_transactions USING btree (transaction_date);


--
-- TOC entry 5288 (class 1259 OID 17209)
-- Name: idx_inv_tx_product; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_inv_tx_product ON public.inventory_transactions USING btree (product_id);


--
-- TOC entry 5289 (class 1259 OID 17211)
-- Name: idx_inv_tx_product_date; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_inv_tx_product_date ON public.inventory_transactions USING btree (product_id, transaction_date);


--
-- TOC entry 5281 (class 1259 OID 17171)
-- Name: idx_product_master_active; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_product_master_active ON public.product_master USING btree (is_active);


--
-- TOC entry 5282 (class 1259 OID 17172)
-- Name: idx_product_master_created_by; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_product_master_created_by ON public.product_master USING btree (created_by);


--
-- TOC entry 5283 (class 1259 OID 17170)
-- Name: idx_product_master_name; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_product_master_name ON public.product_master USING btree (product_name);


--
-- TOC entry 5320 (class 1259 OID 17612)
-- Name: idx_production_lines_active; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_production_lines_active ON public.production_lines USING btree (is_active);


--
-- TOC entry 5197 (class 1259 OID 16670)
-- Name: idx_row_locks_file; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_row_locks_file ON public.row_locks USING btree (file_id);


--
-- TOC entry 5198 (class 1259 OID 16671)
-- Name: idx_row_locks_user; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_row_locks_user ON public.row_locks USING btree (locked_by);


--
-- TOC entry 5232 (class 1259 OID 16841)
-- Name: idx_sessions_token; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_sessions_token ON public.user_sessions USING btree (token_hash);


--
-- TOC entry 5233 (class 1259 OID 16840)
-- Name: idx_sessions_user; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_sessions_user ON public.user_sessions USING btree (user_id);


--
-- TOC entry 5271 (class 1259 OID 17097)
-- Name: idx_sheet_access_sheet; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_sheet_access_sheet ON public.sheet_access USING btree (sheet_id);


--
-- TOC entry 5272 (class 1259 OID 17098)
-- Name: idx_sheet_access_user; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_sheet_access_user ON public.sheet_access USING btree (user_id);


--
-- TOC entry 5249 (class 1259 OID 16912)
-- Name: idx_sheet_data_sheet; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_sheet_data_sheet ON public.sheet_data USING btree (sheet_id);


--
-- TOC entry 5266 (class 1259 OID 17007)
-- Name: idx_sheet_edit_history_date; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_sheet_edit_history_date ON public.sheet_edit_history USING btree (edited_at);


--
-- TOC entry 5267 (class 1259 OID 17005)
-- Name: idx_sheet_edit_history_sheet; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_sheet_edit_history_sheet ON public.sheet_edit_history USING btree (sheet_id);


--
-- TOC entry 5268 (class 1259 OID 17006)
-- Name: idx_sheet_edit_history_user; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_sheet_edit_history_user ON public.sheet_edit_history USING btree (edited_by);


--
-- TOC entry 5260 (class 1259 OID 16981)
-- Name: idx_sheet_edit_sessions_sheet; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_sheet_edit_sessions_sheet ON public.sheet_edit_sessions USING btree (sheet_id);


--
-- TOC entry 5261 (class 1259 OID 16982)
-- Name: idx_sheet_edit_sessions_user; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_sheet_edit_sessions_user ON public.sheet_edit_sessions USING btree (user_id);


--
-- TOC entry 5313 (class 1259 OID 17582)
-- Name: idx_sheet_links_enabled; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_sheet_links_enabled ON public.sheet_links USING btree (enabled);


--
-- TOC entry 5314 (class 1259 OID 17580)
-- Name: idx_sheet_links_source; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_sheet_links_source ON public.sheet_links USING btree (source_sheet_id);


--
-- TOC entry 5315 (class 1259 OID 17581)
-- Name: idx_sheet_links_target; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_sheet_links_target ON public.sheet_links USING btree (target_sheet_id);


--
-- TOC entry 5254 (class 1259 OID 16958)
-- Name: idx_sheet_locks_sheet; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_sheet_locks_sheet ON public.sheet_locks USING btree (sheet_id);


--
-- TOC entry 5255 (class 1259 OID 16959)
-- Name: idx_sheet_locks_user; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_sheet_locks_user ON public.sheet_locks USING btree (locked_by);


--
-- TOC entry 5310 (class 1259 OID 17354)
-- Name: idx_sheet_versions_sheet_created; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_sheet_versions_sheet_created ON public.sheet_versions USING btree (sheet_id, created_at DESC);


--
-- TOC entry 5240 (class 1259 OID 17100)
-- Name: idx_sheets_cell_styles; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_sheets_cell_styles ON public.sheets USING gin (cell_styles);


--
-- TOC entry 5241 (class 1259 OID 17103)
-- Name: idx_sheets_column_widths; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_sheets_column_widths ON public.sheets USING gin (column_widths);


--
-- TOC entry 5242 (class 1259 OID 16889)
-- Name: idx_sheets_created_by; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_sheets_created_by ON public.sheets USING btree (created_by);


--
-- TOC entry 5243 (class 1259 OID 16890)
-- Name: idx_sheets_department; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_sheets_department ON public.sheets USING btree (department_id);


--
-- TOC entry 5244 (class 1259 OID 17142)
-- Name: idx_sheets_folder; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_sheets_folder ON public.sheets USING btree (folder_id);


--
-- TOC entry 5245 (class 1259 OID 17106)
-- Name: idx_sheets_merged_cells; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_sheets_merged_cells ON public.sheets USING gin (merged_cells);


--
-- TOC entry 5246 (class 1259 OID 17104)
-- Name: idx_sheets_row_heights; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_sheets_row_heights ON public.sheets USING gin (row_heights);


--
-- TOC entry 5170 (class 1259 OID 16561)
-- Name: idx_users_department; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_users_department ON public.users USING btree (department_id);


--
-- TOC entry 5171 (class 1259 OID 16560)
-- Name: idx_users_email; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_users_email ON public.users USING btree (email);


--
-- TOC entry 5172 (class 1259 OID 16559)
-- Name: idx_users_username; Type: INDEX; Schema: public; Owner: synergygraphics
--

CREATE INDEX idx_users_username ON public.users USING btree (username);


--
-- TOC entry 5396 (class 2620 OID 25923)
-- Name: departments update_departments_updated_at; Type: TRIGGER; Schema: public; Owner: synergygraphics
--

CREATE TRIGGER update_departments_updated_at BEFORE UPDATE ON public.departments FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5399 (class 2620 OID 25921)
-- Name: file_data update_file_data_updated_at; Type: TRIGGER; Schema: public; Owner: synergygraphics
--

CREATE TRIGGER update_file_data_updated_at BEFORE UPDATE ON public.file_data FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5398 (class 2620 OID 25920)
-- Name: files update_files_updated_at; Type: TRIGGER; Schema: public; Owner: synergygraphics
--

CREATE TRIGGER update_files_updated_at BEFORE UPDATE ON public.files FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5400 (class 2620 OID 25922)
-- Name: formulas update_formulas_updated_at; Type: TRIGGER; Schema: public; Owner: synergygraphics
--

CREATE TRIGGER update_formulas_updated_at BEFORE UPDATE ON public.formulas FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5402 (class 2620 OID 17252)
-- Name: inventory_transactions update_inventory_transactions_updated_at; Type: TRIGGER; Schema: public; Owner: synergygraphics
--

CREATE TRIGGER update_inventory_transactions_updated_at BEFORE UPDATE ON public.inventory_transactions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5401 (class 2620 OID 17251)
-- Name: product_master update_product_master_updated_at; Type: TRIGGER; Schema: public; Owner: synergygraphics
--

CREATE TRIGGER update_product_master_updated_at BEFORE UPDATE ON public.product_master FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5397 (class 2620 OID 25919)
-- Name: users update_users_updated_at; Type: TRIGGER; Schema: public; Owner: synergygraphics
--

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5385 (class 2606 OID 17324)
-- Name: active_users active_users_sheet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.active_users
    ADD CONSTRAINT active_users_sheet_id_fkey FOREIGN KEY (sheet_id) REFERENCES public.sheets(id) ON DELETE CASCADE;


--
-- TOC entry 5386 (class 2606 OID 17319)
-- Name: active_users active_users_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.active_users
    ADD CONSTRAINT active_users_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 5347 (class 2606 OID 16757)
-- Name: applied_formulas applied_formulas_applied_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.applied_formulas
    ADD CONSTRAINT applied_formulas_applied_by_fkey FOREIGN KEY (applied_by) REFERENCES public.users(id);


--
-- TOC entry 5348 (class 2606 OID 16747)
-- Name: applied_formulas applied_formulas_file_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.applied_formulas
    ADD CONSTRAINT applied_formulas_file_id_fkey FOREIGN KEY (file_id) REFERENCES public.files(id) ON DELETE CASCADE;


--
-- TOC entry 5349 (class 2606 OID 16752)
-- Name: applied_formulas applied_formulas_formula_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.applied_formulas
    ADD CONSTRAINT applied_formulas_formula_id_fkey FOREIGN KEY (formula_id) REFERENCES public.formulas(id) ON DELETE CASCADE;


--
-- TOC entry 5350 (class 2606 OID 16781)
-- Name: audit_logs audit_logs_file_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_file_id_fkey FOREIGN KEY (file_id) REFERENCES public.files(id) ON DELETE SET NULL;


--
-- TOC entry 5351 (class 2606 OID 17257)
-- Name: audit_logs audit_logs_sheet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_sheet_id_fkey FOREIGN KEY (sheet_id) REFERENCES public.sheets(id) ON DELETE SET NULL;


--
-- TOC entry 5352 (class 2606 OID 16776)
-- Name: audit_logs audit_logs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- TOC entry 5357 (class 2606 OID 16858)
-- Name: dashboard_cache dashboard_cache_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.dashboard_cache
    ADD CONSTRAINT dashboard_cache_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(id);


--
-- TOC entry 5382 (class 2606 OID 17288)
-- Name: edit_requests edit_requests_requested_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.edit_requests
    ADD CONSTRAINT edit_requests_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 5383 (class 2606 OID 17293)
-- Name: edit_requests edit_requests_reviewed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.edit_requests
    ADD CONSTRAINT edit_requests_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES public.users(id);


--
-- TOC entry 5384 (class 2606 OID 17283)
-- Name: edit_requests edit_requests_sheet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.edit_requests
    ADD CONSTRAINT edit_requests_sheet_id_fkey FOREIGN KEY (sheet_id) REFERENCES public.sheets(id) ON DELETE CASCADE;


--
-- TOC entry 5339 (class 2606 OID 16636)
-- Name: file_data file_data_file_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.file_data
    ADD CONSTRAINT file_data_file_id_fkey FOREIGN KEY (file_id) REFERENCES public.files(id) ON DELETE CASCADE;


--
-- TOC entry 5353 (class 2606 OID 16804)
-- Name: file_permissions file_permissions_file_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.file_permissions
    ADD CONSTRAINT file_permissions_file_id_fkey FOREIGN KEY (file_id) REFERENCES public.files(id) ON DELETE CASCADE;


--
-- TOC entry 5354 (class 2606 OID 16814)
-- Name: file_permissions file_permissions_granted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.file_permissions
    ADD CONSTRAINT file_permissions_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES public.users(id);


--
-- TOC entry 5355 (class 2606 OID 16809)
-- Name: file_permissions file_permissions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.file_permissions
    ADD CONSTRAINT file_permissions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 5337 (class 2606 OID 16614)
-- Name: file_versions file_versions_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.file_versions
    ADD CONSTRAINT file_versions_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5338 (class 2606 OID 16609)
-- Name: file_versions file_versions_file_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.file_versions
    ADD CONSTRAINT file_versions_file_id_fkey FOREIGN KEY (file_id) REFERENCES public.files(id) ON DELETE CASCADE;


--
-- TOC entry 5333 (class 2606 OID 16588)
-- Name: files files_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.files
    ADD CONSTRAINT files_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5334 (class 2606 OID 16583)
-- Name: files files_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.files
    ADD CONSTRAINT files_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(id);


--
-- TOC entry 5335 (class 2606 OID 17131)
-- Name: files files_folder_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.files
    ADD CONSTRAINT files_folder_id_fkey FOREIGN KEY (folder_id) REFERENCES public.folders(id) ON DELETE SET NULL;


--
-- TOC entry 5336 (class 2606 OID 17056)
-- Name: files files_source_sheet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.files
    ADD CONSTRAINT files_source_sheet_id_fkey FOREIGN KEY (source_sheet_id) REFERENCES public.sheets(id) ON DELETE SET NULL;


--
-- TOC entry 5372 (class 2606 OID 17124)
-- Name: folders folders_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.folders
    ADD CONSTRAINT folders_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5373 (class 2606 OID 17119)
-- Name: folders folders_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.folders
    ADD CONSTRAINT folders_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.folders(id) ON DELETE CASCADE;


--
-- TOC entry 5345 (class 2606 OID 16728)
-- Name: formula_versions formula_versions_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.formula_versions
    ADD CONSTRAINT formula_versions_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5346 (class 2606 OID 16723)
-- Name: formula_versions formula_versions_formula_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.formula_versions
    ADD CONSTRAINT formula_versions_formula_id_fkey FOREIGN KEY (formula_id) REFERENCES public.formulas(id) ON DELETE CASCADE;


--
-- TOC entry 5343 (class 2606 OID 16699)
-- Name: formulas formulas_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.formulas
    ADD CONSTRAINT formulas_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5344 (class 2606 OID 16694)
-- Name: formulas formulas_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.formulas
    ADD CONSTRAINT formulas_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(id);


--
-- TOC entry 5379 (class 2606 OID 17235)
-- Name: inventory_audit_log inventory_audit_log_performed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.inventory_audit_log
    ADD CONSTRAINT inventory_audit_log_performed_by_fkey FOREIGN KEY (performed_by) REFERENCES public.users(id);


--
-- TOC entry 5380 (class 2606 OID 17230)
-- Name: inventory_audit_log inventory_audit_log_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.inventory_audit_log
    ADD CONSTRAINT inventory_audit_log_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.product_master(id) ON DELETE SET NULL;


--
-- TOC entry 5381 (class 2606 OID 17225)
-- Name: inventory_audit_log inventory_audit_log_transaction_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.inventory_audit_log
    ADD CONSTRAINT inventory_audit_log_transaction_id_fkey FOREIGN KEY (transaction_id) REFERENCES public.inventory_transactions(id) ON DELETE SET NULL;


--
-- TOC entry 5394 (class 2606 OID 17794)
-- Name: inventory_discrepancy_reports inventory_discrepancy_reports_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.inventory_discrepancy_reports
    ADD CONSTRAINT inventory_discrepancy_reports_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5395 (class 2606 OID 17801)
-- Name: inventory_discrepancy_reports inventory_discrepancy_reports_resolved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.inventory_discrepancy_reports
    ADD CONSTRAINT inventory_discrepancy_reports_resolved_by_fkey FOREIGN KEY (resolved_by) REFERENCES public.users(id);


--
-- TOC entry 5376 (class 2606 OID 17199)
-- Name: inventory_transactions inventory_transactions_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.inventory_transactions
    ADD CONSTRAINT inventory_transactions_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5377 (class 2606 OID 17194)
-- Name: inventory_transactions inventory_transactions_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.inventory_transactions
    ADD CONSTRAINT inventory_transactions_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.product_master(id) ON DELETE RESTRICT;


--
-- TOC entry 5378 (class 2606 OID 17204)
-- Name: inventory_transactions inventory_transactions_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.inventory_transactions
    ADD CONSTRAINT inventory_transactions_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 5374 (class 2606 OID 17160)
-- Name: product_master product_master_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.product_master
    ADD CONSTRAINT product_master_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5375 (class 2606 OID 17165)
-- Name: product_master product_master_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.product_master
    ADD CONSTRAINT product_master_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 5392 (class 2606 OID 17602)
-- Name: production_lines production_lines_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.production_lines
    ADD CONSTRAINT production_lines_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5393 (class 2606 OID 17607)
-- Name: production_lines production_lines_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.production_lines
    ADD CONSTRAINT production_lines_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5340 (class 2606 OID 16655)
-- Name: row_locks row_locks_file_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.row_locks
    ADD CONSTRAINT row_locks_file_id_fkey FOREIGN KEY (file_id) REFERENCES public.files(id) ON DELETE CASCADE;


--
-- TOC entry 5341 (class 2606 OID 16665)
-- Name: row_locks row_locks_locked_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.row_locks
    ADD CONSTRAINT row_locks_locked_by_fkey FOREIGN KEY (locked_by) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 5342 (class 2606 OID 16660)
-- Name: row_locks row_locks_row_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.row_locks
    ADD CONSTRAINT row_locks_row_id_fkey FOREIGN KEY (row_id) REFERENCES public.file_data(id) ON DELETE CASCADE;


--
-- TOC entry 5369 (class 2606 OID 17092)
-- Name: sheet_access sheet_access_granted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_access
    ADD CONSTRAINT sheet_access_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES public.users(id);


--
-- TOC entry 5370 (class 2606 OID 17082)
-- Name: sheet_access sheet_access_sheet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_access
    ADD CONSTRAINT sheet_access_sheet_id_fkey FOREIGN KEY (sheet_id) REFERENCES public.sheets(id) ON DELETE CASCADE;


--
-- TOC entry 5371 (class 2606 OID 17087)
-- Name: sheet_access sheet_access_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_access
    ADD CONSTRAINT sheet_access_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 5362 (class 2606 OID 16907)
-- Name: sheet_data sheet_data_sheet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_data
    ADD CONSTRAINT sheet_data_sheet_id_fkey FOREIGN KEY (sheet_id) REFERENCES public.sheets(id) ON DELETE CASCADE;


--
-- TOC entry 5367 (class 2606 OID 17000)
-- Name: sheet_edit_history sheet_edit_history_edited_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_edit_history
    ADD CONSTRAINT sheet_edit_history_edited_by_fkey FOREIGN KEY (edited_by) REFERENCES public.users(id);


--
-- TOC entry 5368 (class 2606 OID 16995)
-- Name: sheet_edit_history sheet_edit_history_sheet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_edit_history
    ADD CONSTRAINT sheet_edit_history_sheet_id_fkey FOREIGN KEY (sheet_id) REFERENCES public.sheets(id) ON DELETE CASCADE;


--
-- TOC entry 5365 (class 2606 OID 16971)
-- Name: sheet_edit_sessions sheet_edit_sessions_sheet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_edit_sessions
    ADD CONSTRAINT sheet_edit_sessions_sheet_id_fkey FOREIGN KEY (sheet_id) REFERENCES public.sheets(id) ON DELETE CASCADE;


--
-- TOC entry 5366 (class 2606 OID 16976)
-- Name: sheet_edit_sessions sheet_edit_sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_edit_sessions
    ADD CONSTRAINT sheet_edit_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- TOC entry 5389 (class 2606 OID 17575)
-- Name: sheet_links sheet_links_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_links
    ADD CONSTRAINT sheet_links_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5390 (class 2606 OID 17565)
-- Name: sheet_links sheet_links_source_sheet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_links
    ADD CONSTRAINT sheet_links_source_sheet_id_fkey FOREIGN KEY (source_sheet_id) REFERENCES public.sheets(id) ON DELETE CASCADE;


--
-- TOC entry 5391 (class 2606 OID 17570)
-- Name: sheet_links sheet_links_target_sheet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_links
    ADD CONSTRAINT sheet_links_target_sheet_id_fkey FOREIGN KEY (target_sheet_id) REFERENCES public.sheets(id) ON DELETE CASCADE;


--
-- TOC entry 5363 (class 2606 OID 16953)
-- Name: sheet_locks sheet_locks_locked_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_locks
    ADD CONSTRAINT sheet_locks_locked_by_fkey FOREIGN KEY (locked_by) REFERENCES public.users(id);


--
-- TOC entry 5364 (class 2606 OID 16948)
-- Name: sheet_locks sheet_locks_sheet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_locks
    ADD CONSTRAINT sheet_locks_sheet_id_fkey FOREIGN KEY (sheet_id) REFERENCES public.sheets(id) ON DELETE CASCADE;


--
-- TOC entry 5387 (class 2606 OID 17344)
-- Name: sheet_versions sheet_versions_sheet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_versions
    ADD CONSTRAINT sheet_versions_sheet_id_fkey FOREIGN KEY (sheet_id) REFERENCES public.sheets(id) ON DELETE CASCADE;


--
-- TOC entry 5388 (class 2606 OID 17349)
-- Name: sheet_versions sheet_versions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheet_versions
    ADD CONSTRAINT sheet_versions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5358 (class 2606 OID 16879)
-- Name: sheets sheets_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheets
    ADD CONSTRAINT sheets_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5359 (class 2606 OID 16884)
-- Name: sheets sheets_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheets
    ADD CONSTRAINT sheets_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(id);


--
-- TOC entry 5360 (class 2606 OID 17137)
-- Name: sheets sheets_folder_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheets
    ADD CONSTRAINT sheets_folder_id_fkey FOREIGN KEY (folder_id) REFERENCES public.folders(id) ON DELETE SET NULL;


--
-- TOC entry 5361 (class 2606 OID 17042)
-- Name: sheets sheets_last_edited_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.sheets
    ADD CONSTRAINT sheets_last_edited_by_fkey FOREIGN KEY (last_edited_by) REFERENCES public.users(id);


--
-- TOC entry 5356 (class 2606 OID 16835)
-- Name: user_sessions user_sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.user_sessions
    ADD CONSTRAINT user_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 5329 (class 2606 OID 17024)
-- Name: users users_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5330 (class 2606 OID 17029)
-- Name: users users_deactivated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_deactivated_by_fkey FOREIGN KEY (deactivated_by) REFERENCES public.users(id);


--
-- TOC entry 5331 (class 2606 OID 16554)
-- Name: users users_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(id);


--
-- TOC entry 5332 (class 2606 OID 16549)
-- Name: users users_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: synergygraphics
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id);


--
-- TOC entry 5561 (class 0 OID 0)
-- Dependencies: 6
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT ALL ON SCHEMA public TO synergygraphics;


--
-- TOC entry 5587 (class 0 OID 0)
-- Dependencies: 262
-- Name: TABLE sheet_access; Type: ACL; Schema: public; Owner: synergygraphics
--

GRANT SELECT ON TABLE public.sheet_access TO PUBLIC;


--
-- TOC entry 2234 (class 826 OID 16449)
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO synergygraphics;


-- Completed on 2026-04-05 00:35:21

--
-- PostgreSQL database dump complete
--

\unrestrict hI3mG82F8dnGdxpCCqF6cWZ0Y4u7wVYxSwiDzqKBNpeOZnZh1XoxqlmxbpxZF0K

