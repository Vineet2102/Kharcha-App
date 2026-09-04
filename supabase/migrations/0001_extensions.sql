create extension if not exists "pgcrypto";      -- gen_random_uuid()
create extension if not exists "pg_trgm";       -- fuzzy note search

create type public.member_role      as enum ('admin', 'member');
create type public.category_kind    as enum ('expense', 'income');
create type public.pay_method_type  as enum ('cash', 'upi', 'card', 'bank', 'wallet', 'other');
create type public.budget_scope     as enum ('household', 'user', 'category', 'user_category');
create type public.recur_frequency  as enum ('daily', 'weekly', 'monthly', 'yearly');
create type public.txn_kind         as enum ('expense', 'income');
