create table items (
    id bigserial primary key,
    name text not null,
    created_at timestamptz not null default now()
);
