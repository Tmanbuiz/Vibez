create table if not exists items (
  id text primary key,
  kind text not null,          -- music | image | video | speech
  title text,
  prompt text,
  model text,
  status text not null,        -- PROCESSING | DONE | FAILED
  queue_id text,
  key text,                    -- R2 object key once finished
  mime text,
  cost real,                   -- quoted USD
  created integer not null,
  meta text default '{}'
);
create index if not exists items_created on items(created desc);

create table if not exists singers (
  id text primary key,
  name text not null,
  key text not null,
  mime text not null,
  created integer not null
);
create index if not exists singers_created on singers(created desc);

create table if not exists voices (
  id text primary key,         -- Venice vv_... handle (expires after 7 days)
  name text,
  created integer not null
);
