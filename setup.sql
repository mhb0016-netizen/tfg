-- Pega TODO este archivo en Supabase > SQL Editor > New query > Run

create table places (
  id bigint generated always as identity primary key,
  name text not null check (char_length(name) between 2 and 80),
  category text not null default 'otros',
  description text check (char_length(description) <= 300),
  lat double precision not null,
  lng double precision not null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  visible boolean not null default true,
  created_at timestamptz not null default now()
);

create table ratings (
  place_id bigint references places(id) on delete cascade,
  user_id uuid default auth.uid() references auth.users(id) on delete cascade,
  stars int not null check (stars between 1 and 5),
  primary key (place_id, user_id)
);

create table visits (
  place_id bigint references places(id) on delete cascade,
  user_id uuid default auth.uid() references auth.users(id) on delete cascade,
  day date not null default current_date,
  primary key (place_id, user_id, day)
);

create table photos (
  id bigint generated always as identity primary key,
  place_id bigint references places(id) on delete cascade,
  user_id uuid default auth.uid() references auth.users(id) on delete cascade,
  path text not null,
  created_at timestamptz not null default now()
);

alter table places  enable row level security;
alter table ratings enable row level security;
alter table visits  enable row level security;
alter table photos  enable row level security;

create policy "ver lugares"   on places  for select using (visible);
create policy "crear lugares" on places  for insert to authenticated with check (created_by = auth.uid());

create policy "ver votos"     on ratings for select using (true);
create policy "votar"         on ratings for insert to authenticated with check (user_id = auth.uid());
create policy "cambiar voto"  on ratings for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "ver visitas"   on visits  for select using (true);
create policy "marcar visita" on visits  for insert to authenticated with check (user_id = auth.uid());

create policy "ver fotos"     on photos  for select using (true);
create policy "subir foto"    on photos  for insert to authenticated with check (user_id = auth.uid());
create policy "borrar foto"   on photos  for delete to authenticated using (user_id = auth.uid());

-- Estadísticas para ordenar por mejor valorados y más visitados
create view place_stats with (security_invoker = true) as
select p.*,
  (select coalesce(avg(stars), 0) from ratings r where r.place_id = p.id) as avg_rating,
  (select count(*) from ratings r where r.place_id = p.id) as n_ratings,
  (select count(*) from visits v where v.place_id = p.id) as n_visits,
  (select count(*) from photos f where f.place_id = p.id) as n_photos
from places p;

-- Almacén de fotos (público para verlas, solo usuarios registrados para subir)
insert into storage.buckets (id, name, public) values ('photos', 'photos', true) on conflict do nothing;
create policy "fotos publicas" on storage.objects for select using (bucket_id = 'photos');
create policy "subir fotos"    on storage.objects for insert to authenticated with check (bucket_id = 'photos');




alter table places add constraint dentro_sevilla_este
check (lat between 37.372 and 37.432 and lng between -5.964 and -5.835);


alter table places drop constraint if exists dentro_sevilla_este;
alter table places add constraint dentro_sevilla_este
check (lat between 37.384 and 37.419 and lng between -5.950 and -5.882);

-- Editar: solo el creador, y solo nombre, categoría y descripción
revoke update on places from authenticated, anon;
grant update (name, category, description) on places to authenticated;
create policy "editar mis lugares" on places for update to authenticated
  using (created_by = auth.uid()) with check (created_by = auth.uid());

-- Eliminar: solo el creador (valoraciones, visitas y fotos se borran solas)
create policy "borrar mis lugares" on places for delete to authenticated
  using (created_by = auth.uid());

-- Poder borrar los archivos de las fotos que subió cada persona
create policy "borrar mis fotos" on storage.objects for delete to authenticated
  using (bucket_id = 'photos' and owner_id = auth.uid()::text);

-- Pega TODO esto en Supabase > SQL Editor > New query > Run

-- 1) Perfiles: nombre de usuario público
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null check (username ~ '^[A-Za-z0-9_]{3,20}$'),
  created_at timestamptz not null default now()
);
create unique index if not exists profiles_username_ci on profiles (lower(username));
alter table profiles enable row level security;
create policy "ver perfiles" on profiles for select using (true);

-- 2) El perfil se crea solo al registrarse una persona
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, username) values (new.id, new.raw_user_meta_data ->> 'username');
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- 3) Cuentas que ya existían: reciben un nombre provisional
insert into profiles (id, username)
select id, 'vecino_' || substr(replace(id::text, '-', ''), 1, 8) from auth.users
on conflict do nothing;

-- 4) Saber si un nombre de usuario está libre (sin revelar nada más)
create or replace function username_disponible(nombre text) returns boolean
language sql security definer set search_path = public as $$
  select not exists (select 1 from profiles where lower(username) = lower(nombre));
$$;
grant execute on function username_disponible(text) to anon, authenticated;

-- 5) Reseñas: estrellas + comentario + fecha, enlazadas al perfil
alter table ratings add column if not exists comment text check (char_length(comment) <= 500);
alter table ratings add column if not exists created_at timestamptz not null default now();
alter table ratings add constraint ratings_user_profile
  foreign key (user_id) references profiles(id) on delete cascade;
create policy "borrar mi reseña" on ratings for delete to authenticated using (user_id = auth.uid());


-- Pega TODO en Supabase > SQL Editor > New query > Run
-- ANTES de ejecutarlo, cambia TU_USUARIO (más abajo) por tu nombre de usuario.

-- ================= ROLES =================
alter table profiles add column if not exists rol text not null default 'usuario' check (rol in ('usuario','admin'));
revoke insert, update, delete on profiles from anon, authenticated;   -- nadie puede darse admin desde la web

create or replace function es_admin() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and rol = 'admin');
$$;
grant execute on function es_admin() to anon, authenticated;

-- >>>>>> AQUÍ ELIGES AL ADMIN: pon tu nombre de usuario <<<<<<
update profiles set rol = 'admin' where lower(username) = lower('Sevilla_Este');
-- (para quitar o añadir admins más tarde, repite esta línea con otro usuario, o pon rol = 'usuario')

-- El admin puede borrar/editar todo
create policy "admin borra lugares" on places  for delete to authenticated using (es_admin());
create policy "admin edita lugares" on places  for update to authenticated using (es_admin()) with check (es_admin());
create policy "admin borra resenas" on ratings for delete to authenticated using (es_admin());
create policy "admin borra fotos"   on photos  for delete to authenticated using (es_admin());
drop policy if exists "borrar mis fotos" on storage.objects;
create policy "borrar fotos" on storage.objects for delete to authenticated
  using (bucket_id = 'photos' and (owner_id = auth.uid()::text or es_admin()));

-- ================= OCULTAR RESEÑAS / FOTOS =================
create table ocultos (
  id bigint generated always as identity primary key,
  place_id bigint not null references places(id) on delete cascade,
  kind text not null check (kind in ('resena','foto')),
  ref text not null,
  unique (place_id, kind, ref)
);
alter table ocultos enable row level security;
create policy "ver ocultos" on ocultos for select using (true);
create policy "ocultar" on ocultos for insert to authenticated with check (
  es_admin() or exists (select 1 from places p where p.id = ocultos.place_id and p.created_by = auth.uid()));
create policy "mostrar" on ocultos for delete to authenticated using (
  es_admin() or exists (select 1 from places p where p.id = ocultos.place_id and p.created_by = auth.uid()));

-- ================= FILTRO DE ENLACES =================
create table dominios_permitidos (dominio text primary key);
alter table dominios_permitidos enable row level security;
create policy "ver dominios" on dominios_permitidos for select using (true);
insert into dominios_permitidos values
  ('google.com'),('google.es'),('maps.app.goo.gl'),('youtube.com'),('youtu.be'),('wikipedia.org'),
  ('openstreetmap.org'),('instagram.com'),('facebook.com'),('sevilla.org'),('juntadeandalucia.es')
on conflict do nothing;
-- Para permitir otro sitio:  insert into dominios_permitidos values ('ejemplo.com');

create or replace function texto_seguro(t text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare m text[]; host text;
begin
  if t is null or t = '' then return true; end if;
  if t ~* '(javascript|vbscript|data)\s*:' then return false; end if;
  -- enlaces con http(s):// o www.
  for m in select regexp_matches(t, '(?:https?://|www\.)([^\s/:?#]+)', 'gi') loop
    host := regexp_replace(lower(m[1]), '^www\.', '');
    if not exists (select 1 from dominios_permitidos d where host = d.dominio or host like '%.' || d.dominio) then return false; end if;
  end loop;
  -- dominios escritos sin http, tipo ejemplo.com (también bloquea emails)
  for m in select regexp_matches(t, '([a-z0-9][a-z0-9-]*(?:\.[a-z0-9-]+)*\.(?:com|es|net|org|info|xyz|ru|cn|tk|ml|ga|cf|gq|top|click|link|site|online|shop|app|io|co|me|ly|gl|to|cc|biz|us|uk|de|fr|it|eu|dev|page|store|live|cloud|club|vip|work|icu|buzz|rest|fun|pw|su|ws))(?![a-z0-9-])', 'gi') loop
    host := regexp_replace(lower(m[1]), '^www\.', '');
    if not exists (select 1 from dominios_permitidos d where host = d.dominio or host like '%.' || d.dominio) then return false; end if;
  end loop;
  return true;
end $$;

create or replace function validar_texto() returns trigger language plpgsql security definer set search_path = public as $$
declare campo text; j jsonb := to_jsonb(new);
begin
  if es_admin() then return new; end if;
  foreach campo in array tg_argv loop
    if not texto_seguro(j ->> campo) then raise exception 'enlace_no_permitido'; end if;
  end loop;
  return new;
end $$;

create trigger t_places_texto  before insert or update on places  for each row execute function validar_texto('name','description');
create trigger t_ratings_texto before insert or update on ratings for each row execute function validar_texto('comment');

-- ================= FORO =================
create table canales (
  id bigint generated always as identity primary key,
  tipo text not null check (tipo in ('noticias','general','chat')),
  nombre text not null check (char_length(nombre) between 3 and 40),
  creado_por uuid default auth.uid() references profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
insert into canales (tipo, nombre, creado_por) values ('noticias','Noticias',null), ('general','General',null);

create table mensajes (
  id bigint generated always as identity primary key,
  canal_id bigint not null references canales(id) on delete cascade,
  user_id uuid not null default auth.uid() references profiles(id) on delete cascade,
  titulo text check (char_length(titulo) <= 100),
  texto text check (char_length(texto) <= 1000),
  place_id bigint references places(id) on delete set null,
  created_at timestamptz not null default now(),
  check (texto is not null or place_id is not null)
);
create index on mensajes (canal_id, id desc);

alter table canales  enable row level security;
alter table mensajes enable row level security;

create policy "ver canales"   on canales  for select using (true);
create policy "crear chats"   on canales  for insert to authenticated
  with check (es_admin() or (tipo = 'chat' and creado_por = auth.uid()));
create policy "borrar chats"  on canales  for delete to authenticated
  using (es_admin() or (tipo = 'chat' and creado_por = auth.uid()));

create policy "ver mensajes"  on mensajes for select using (true);
create policy "escribir"      on mensajes for insert to authenticated with check (
  user_id = auth.uid() and (es_admin() or (select c.tipo from canales c where c.id = canal_id) <> 'noticias'));
create policy "borrar mensajes" on mensajes for delete to authenticated using (
  user_id = auth.uid() or es_admin()
  or exists (select 1 from canales c where c.id = mensajes.canal_id and c.creado_por = auth.uid()));

-- Anti-spam y filtro de enlaces
create or replace function limitar_mensajes() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if es_admin() then return new; end if;
  if (select count(*) from mensajes where user_id = new.user_id and created_at > now() - interval '1 minute') >= 8
    then raise exception 'demasiados_mensajes'; end if;
  return new;
end $$;
create or replace function limitar_chats() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.tipo = 'chat' and not es_admin()
     and (select count(*) from canales where creado_por = new.creado_por and tipo = 'chat') >= 5
    then raise exception 'limite_chats'; end if;
  return new;
end $$;
create trigger t_mensajes_texto  before insert or update on mensajes for each row execute function validar_texto('texto','titulo');
create trigger t_mensajes_limite before insert on mensajes for each row execute function limitar_mensajes();
create trigger t_canales_texto   before insert or update on canales  for each row execute function validar_texto('nombre');
create trigger t_canales_limite  before insert on canales  for each row execute function limitar_chats();




-- Pega TODO en Supabase > SQL Editor > New query > Run
-- (necesita que ya hayas ejecutado cuentas.sql y foro.sql)

-- ================= FAVORITOS (privados de cada persona) =================
create table favoritos (
  user_id uuid not null default auth.uid() references profiles(id) on delete cascade,
  place_id bigint not null references places(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, place_id)
);
alter table favoritos enable row level security;
create policy "ver mis favoritos" on favoritos for select to authenticated using (user_id = auth.uid());
create policy "anadir favorito"   on favoritos for insert to authenticated with check (user_id = auth.uid());
create policy "quitar favorito"   on favoritos for delete to authenticated using (user_id = auth.uid());

-- ================= DESTACADO MANUAL (solo admin) =================
alter table places add column if not exists destacado boolean not null default false;

drop view if exists place_stats;
create view place_stats with (security_invoker = true) as
select p.*,
  (select coalesce(avg(stars), 0) from ratings r where r.place_id = p.id) as avg_rating,
  (select count(*) from ratings r where r.place_id = p.id) as n_ratings,
  (select count(*) from visits v where v.place_id = p.id) as n_visits,
  (select count(*) from photos f where f.place_id = p.id) as n_photos
from places p;
grant select on place_stats to anon, authenticated;

create or replace function marcar_destacado(p_id bigint, valor boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not es_admin() then raise exception 'solo_admin'; end if;
  update places set destacado = valor where id = p_id;
end $$;
grant execute on function marcar_destacado(bigint, boolean) to authenticated;

-- ================= CHATS PRIVADOS CON INVITACIONES =================
create table miembros (
  canal_id bigint not null references canales(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  estado text not null default 'invitado' check (estado in ('invitado','miembro')),
  invitado_por uuid default auth.uid() references profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (canal_id, user_id)
);
alter table miembros enable row level security;

create or replace function es_miembro(c bigint) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from miembros where canal_id = c and user_id = auth.uid() and estado = 'miembro');
$$;
create or replace function es_creador(c bigint) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from canales where id = c and creado_por = auth.uid());
$$;
create or replace function tipo_canal(c bigint) returns text language sql stable security definer set search_path = public as $$
  select tipo from canales where id = c;
$$;
grant execute on function es_miembro(bigint), es_creador(bigint), tipo_canal(bigint) to anon, authenticated;

-- Quien crea un chat entra solo como miembro
create or replace function alta_creador() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.tipo = 'chat' and new.creado_por is not null then
    insert into miembros (canal_id, user_id, estado, invitado_por) values (new.id, new.creado_por, 'miembro', new.creado_por) on conflict do nothing;
  end if;
  return new;
end $$;
create trigger t_canales_alta after insert on canales for each row execute function alta_creador();

-- Chats que ya existían: sus creadores siguen dentro
insert into miembros (canal_id, user_id, estado)
select id, creado_por, 'miembro' from canales where tipo = 'chat' and creado_por is not null
on conflict do nothing;

-- Quién ve qué: los chats son solo para miembros (y para el admin)
drop policy if exists "ver canales" on canales;
create policy "ver canales" on canales for select using (
  tipo <> 'chat' or es_admin() or creado_por = auth.uid()
  or exists (select 1 from miembros m where m.canal_id = canales.id and m.user_id = auth.uid()));

drop policy if exists "ver mensajes" on mensajes;
create policy "ver mensajes" on mensajes for select using (
  tipo_canal(canal_id) <> 'chat' or es_admin() or es_miembro(canal_id));

drop policy if exists "escribir" on mensajes;
create policy "escribir" on mensajes for insert to authenticated with check (
  user_id = auth.uid() and (
    tipo_canal(canal_id) = 'general'
    or (tipo_canal(canal_id) = 'noticias' and es_admin())
    or (tipo_canal(canal_id) = 'chat' and es_miembro(canal_id))));

-- Invitaciones
create policy "ver miembros" on miembros for select using (user_id = auth.uid() or es_admin() or es_miembro(canal_id));
create policy "invitar" on miembros for insert to authenticated with check (
  estado = 'invitado' and invitado_por = auth.uid() and (es_admin() or es_creador(canal_id)));
revoke update on miembros from authenticated, anon;
grant update (estado) on miembros to authenticated;
create policy "aceptar" on miembros for update to authenticated
  using (user_id = auth.uid() and estado = 'invitado') with check (user_id = auth.uid() and estado = 'miembro');
create policy "salir o expulsar" on miembros for delete to authenticated
  using (user_id = auth.uid() or es_admin() or es_creador(canal_id));

-- ================= COMPROBACIÓN (ejecútala aparte, después) =================
-- Debe mostrar solo políticas de "ver"/"escribir"/borrar que reconozcas.
-- Si en 'mensajes' o 'canales' aparece alguna política de select o insert
-- que no sea "ver canales", "ver mensajes" o "escribir", pásamela: podría
-- dejar los chats abiertos a todo el mundo.
-- select tablename, policyname, cmd from pg_policies
--  where tablename in ('canales','mensajes','miembros') order by 1,3;
-- Supabase > SQL Editor > New query > Run
-- En el canal General: un mensaje cada 5 minutos por persona (el admin queda exento).
create or replace function espera_general() returns trigger
language plpgsql security definer set search_path = public as $$
declare ult timestamptz; falta int;
begin
  if tipo_canal(new.canal_id) = 'general' and not es_admin() then
    select max(created_at) into ult from mensajes
      where canal_id = new.canal_id and user_id = new.user_id;
    if ult is not null and ult > now() - interval '5 minutes' then
      falta := ceil(extract(epoch from (ult + interval '5 minutes' - now())));
      raise exception 'espera_general:%', falta;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists t_espera_general on mensajes;
create trigger t_espera_general before insert on mensajes
  for each row execute function espera_general();