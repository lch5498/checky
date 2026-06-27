-- Favis Supabase reset script
-- WARNING: This deletes every app table, function, trigger, and row in public.
-- Run this only when rebuilding a fresh Supabase database for development.
--
-- Recommended order:
-- 1. Run this file in the Supabase SQL Editor.
-- 2. Run supabase/migrations/202606260001_initial_schema.sql.

begin;

drop schema if exists public cascade;

create schema public;
comment on schema public is 'standard public schema';

grant usage on schema public to postgres, anon, authenticated, service_role;
grant all on schema public to postgres, anon, authenticated, service_role;

alter default privileges for role postgres in schema public
  grant all on tables to postgres, anon, authenticated, service_role;

alter default privileges for role postgres in schema public
  grant all on functions to postgres, anon, authenticated, service_role;

alter default privileges for role postgres in schema public
  grant all on sequences to postgres, anon, authenticated, service_role;

create extension if not exists "pgcrypto" with schema extensions;

commit;
