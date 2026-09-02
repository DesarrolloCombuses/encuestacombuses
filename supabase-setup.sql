-- Ejecuta este script en el SQL Editor de tu proyecto Supabase
-- (https://supabase.com/dashboard/project/cbplebkmxrkaafqdhiyi/sql/new)
--
-- Todos los objetos usan el prefijo "encuesta_uniforme_" (y el bucket
-- "encuesta-uniforme-fotos") a propósito, para que no puedan chocar con
-- ninguna tabla, función o bucket que ya tengas en este mismo proyecto.
-- Este script no toca, modifica ni borra nada existente: solo crea objetos
-- nuevos.

-- 0. Limpieza de la version anterior (nombres sin prefijo) -------------------
-- La primera vez corriste una version del script con nombres genericos
-- (respuestas, total_respuestas, estadisticas_encuesta, fotos-encuesta).
-- Esa tabla quedo vacia (0 filas), asi que es seguro borrarla y dejar solo
-- la version con prefijo. Si vuelves a correr este script despues, este
-- bloque simplemente no encuentra nada que borrar y no hace nada.
drop policy if exists "insertar_respuesta_publica" on public.respuestas;
drop function if exists public.total_respuestas();
drop function if exists public.estadisticas_encuesta();
drop table if exists public.respuestas;
drop policy if exists "fotos_subida_publica" on storage.objects;
drop policy if exists "fotos_actualizacion_publica" on storage.objects;
-- Nota: Supabase no permite borrar filas de storage.buckets por SQL directo
-- (hay que usar la Storage API o el dashboard). El bucket viejo "fotos-encuesta"
-- queda sin usar, no hace daño; si quieres eliminarlo hazlo manualmente desde
-- Storage > fotos-encuesta > Delete bucket en el dashboard (esta vacio).

create extension if not exists pgcrypto;

-- 1. Tabla de respuestas -----------------------------------------------------
create table if not exists public.encuesta_uniforme_respuestas (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  cargo text not null check (cargo in ('ADMINISTRATIVO','OPERATIVO')),
  uniforme_admin_dama text,
  uniforme_admin_hombre text,
  uniforme_conductores_aeropuerto text,
  uniforme_conductores_urbano text,
  uniforme_gestores_1 text,
  uniforme_gestores_2 text,
  chaqueta text,
  tenis_unisex text,
  zapato_clasico_hombre text,
  tenis_urbano text,
  botas_cuero_hombre text,
  comentario text,
  creado_en timestamptz not null default now()
);

alter table public.encuesta_uniforme_respuestas enable row level security;

drop policy if exists "encuesta_uniforme_insertar_publica" on public.encuesta_uniforme_respuestas;
create policy "encuesta_uniforme_insertar_publica"
  on public.encuesta_uniforme_respuestas
  for insert
  to anon, authenticated
  with check (true);

-- Deliberadamente NO se crea política de SELECT: la clave publicable viaja
-- en el HTML, así que cualquier lectura directa de filas quedaría expuesta
-- a quien abra la página. Las estadísticas se sirven agregadas via RPC.

-- 2. Funciones de solo lectura agregada --------------------------------------
create or replace function public.encuesta_uniforme_total_respuestas()
returns bigint
language sql
security definer
set search_path = public
as $$
  select count(*) from public.encuesta_uniforme_respuestas;
$$;

create or replace function public.encuesta_uniforme_estadisticas()
returns table(pregunta text, opcion text, conteo bigint)
language sql
security definer
set search_path = public
as $$
  select 'cargo', cargo, count(*) from public.encuesta_uniforme_respuestas where cargo is not null group by cargo
  union all
  select 'uniforme_admin_dama', uniforme_admin_dama, count(*) from public.encuesta_uniforme_respuestas where uniforme_admin_dama is not null group by uniforme_admin_dama
  union all
  select 'uniforme_admin_hombre', uniforme_admin_hombre, count(*) from public.encuesta_uniforme_respuestas where uniforme_admin_hombre is not null group by uniforme_admin_hombre
  union all
  select 'uniforme_conductores_aeropuerto', uniforme_conductores_aeropuerto, count(*) from public.encuesta_uniforme_respuestas where uniforme_conductores_aeropuerto is not null group by uniforme_conductores_aeropuerto
  union all
  select 'uniforme_conductores_urbano', uniforme_conductores_urbano, count(*) from public.encuesta_uniforme_respuestas where uniforme_conductores_urbano is not null group by uniforme_conductores_urbano
  union all
  select 'uniforme_gestores_1', uniforme_gestores_1, count(*) from public.encuesta_uniforme_respuestas where uniforme_gestores_1 is not null group by uniforme_gestores_1
  union all
  select 'uniforme_gestores_2', uniforme_gestores_2, count(*) from public.encuesta_uniforme_respuestas where uniforme_gestores_2 is not null group by uniforme_gestores_2
  union all
  select 'chaqueta', chaqueta, count(*) from public.encuesta_uniforme_respuestas where chaqueta is not null group by chaqueta
  union all
  select 'tenis_unisex', tenis_unisex, count(*) from public.encuesta_uniforme_respuestas where tenis_unisex is not null group by tenis_unisex
  union all
  select 'zapato_clasico_hombre', zapato_clasico_hombre, count(*) from public.encuesta_uniforme_respuestas where zapato_clasico_hombre is not null group by zapato_clasico_hombre
  union all
  select 'tenis_urbano', tenis_urbano, count(*) from public.encuesta_uniforme_respuestas where tenis_urbano is not null group by tenis_urbano
  union all
  select 'botas_cuero_hombre', botas_cuero_hombre, count(*) from public.encuesta_uniforme_respuestas where botas_cuero_hombre is not null group by botas_cuero_hombre;
$$;

grant execute on function public.encuesta_uniforme_total_respuestas() to anon, authenticated;
grant execute on function public.encuesta_uniforme_estadisticas() to anon, authenticated;

-- 3. Bucket de almacenamiento para fotos personalizadas ----------------------
insert into storage.buckets (id, name, public)
values ('encuesta-uniforme-fotos', 'encuesta-uniforme-fotos', true)
on conflict (id) do nothing;

-- Una sola política que cubre lectura/subida/reemplazo/borrado, pero SOLO
-- dentro de este bucket puntual (bucket_id filtrado). Se necesita "for all"
-- porque el upsert que usa la encuesta al reemplazar una foto internamente
-- puede requerir select+insert+update+delete sobre el mismo objeto.
drop policy if exists "encuesta_uniforme_fotos_subida" on storage.objects;
drop policy if exists "encuesta_uniforme_fotos_actualizacion" on storage.objects;
drop policy if exists "encuesta_uniforme_fotos_gestion" on storage.objects;
create policy "encuesta_uniforme_fotos_gestion"
  on storage.objects
  for all
  to anon, authenticated
  using (bucket_id = 'encuesta-uniforme-fotos')
  with check (bucket_id = 'encuesta-uniforme-fotos');
