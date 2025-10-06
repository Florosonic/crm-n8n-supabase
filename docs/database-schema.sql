-- CRM Database Schema
-- Generated: 2025-10-06

-- Companies table
CREATE TABLE companies (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  domain text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT timezone('utc'::text, now()),
  updated_at timestamptz NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT companies_pkey PRIMARY KEY (id)
);

-- Contacts table
CREATE TABLE contacts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  company_id uuid,
  email text,
  first_name text,
  last_name text,
  phone text,
  position text,
  created_at timestamptz NOT NULL DEFAULT timezone('utc'::text, now()),
  updated_at timestamptz NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT contacts_pkey PRIMARY KEY (id),
  CONSTRAINT contacts_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id)
);

-- Pipeline stages table
CREATE TABLE pipeline_stages (
  id int4 NOT NULL,
  name text NOT NULL,
  ping_interval interval NOT NULL,
  ping_type text NOT NULL,
  ping_action text NOT NULL,
  description text,
  CONSTRAINT pipeline_stages_pkey PRIMARY KEY (id)
);

-- Deals table
CREATE TABLE deals (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  contact_id uuid,
  product_name text NOT NULL,
  product_description text,
  price numeric,
  stage int4 NOT NULL DEFAULT 1,
  sample_shipment_date date,
  notes text,
  closed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT timezone('utc'::text, now()),
  updated_at timestamptz NOT NULL DEFAULT timezone('utc'::text, now()),
  status varchar(20) DEFAULT 'open'::character varying,
  CONSTRAINT deals_pkey PRIMARY KEY (id),
  CONSTRAINT deals_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id),
  CONSTRAINT deals_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES contacts(id),
  CONSTRAINT deals_stage_fkey FOREIGN KEY (stage) REFERENCES pipeline_stages(id)
);

-- Pings table
CREATE TABLE pings (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  deal_id uuid NOT NULL,
  ping_date date NOT NULL,
  type text NOT NULL,
  action text NOT NULL,
  is_completed bool DEFAULT false,
  completed_at timestamptz,
  notes text,
  created_at timestamptz NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT pings_pkey PRIMARY KEY (id),
  CONSTRAINT pings_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES deals(id)
);