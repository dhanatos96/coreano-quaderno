-- Stash permanente delle flashcard + stato di studio (imparata / sbagliata / mai vista).
-- Applicata al progetto zhmdzumtvqlirbcnsciz il 2026-09-13.
--
-- Nota: nello schema coreano esiste gia' una VISTA "flashcard" che ricalcola al volo
-- le carte dal jsonb delle lezioni. Resta invariata: qui si aggiunge una TABELLA
-- separata, "flashcard_stash", che e' l'unica a conservare lo stato di studio.

create table if not exists coreano.flashcard_stash (
  id               bigserial primary key,
  lezione_numero   integer not null references coreano.lezioni(numero) on delete cascade,
  card_n           integer not null,
  ko               text not null,
  it               text,
  tipo             text not null check (tipo in ('vocabolo','frase')),
  livello          text,
  data_lezione     date,
  stato            text not null default 'nuova' check (stato in ('nuova','imparata','sbagliata')),
  volte_giusta     integer not null default 0,
  volte_sbagliata  integer not null default 0,
  giuste_di_fila   integer not null default 0,
  ultima_revisione timestamptz,
  created_at       timestamptz not null default now(),
  unique (lezione_numero, tipo, ko)
);

create index if not exists flashcard_stash_stato_idx   on coreano.flashcard_stash (stato);
create index if not exists flashcard_stash_data_idx    on coreano.flashcard_stash (data_lezione desc);
create index if not exists flashcard_stash_livello_idx on coreano.flashcard_stash (livello);

-- Popola/riallinea lo stash a partire dal contenuto jsonb di una lezione.
-- Lo stato di studio delle carte gia' presenti non viene mai toccato.
create or replace function coreano.sync_flashcard_stash(p_numero integer)
returns void
language plpgsql
security definer
set search_path = coreano, public
as $$
declare
  l record;
begin
  select le.numero, le.data, le.contenuto, c.livello
    into l
    from coreano.lezioni le
    left join coreano.curriculum c on c.id = le.curriculum_id
   where le.numero = p_numero;
  if not found then
    return;
  end if;

  insert into coreano.flashcard_stash (lezione_numero, card_n, ko, it, tipo, livello, data_lezione)
  select l.numero,
         (row_number() over (order by t.ord, t.i))::int,
         t.ko, t.it, t.tipo, l.livello, l.data
    from (
      select 1 as ord, x.i as i, x.v->>'ko' as ko, x.v->>'it' as it, 'vocabolo' as tipo
        from jsonb_array_elements(coalesce(l.contenuto->'vocaboli', '[]'::jsonb)) with ordinality as x(v, i)
      union all
      select 2, x.i, x.v->>'ko', x.v->>'it', 'frase'
        from jsonb_array_elements(coalesce(l.contenuto->'frasi', '[]'::jsonb)) with ordinality as x(v, i)
    ) t
   where t.ko is not null and btrim(t.ko) <> ''
  on conflict (lezione_numero, tipo, ko) do update
     set it           = excluded.it,
         livello      = excluded.livello,
         data_lezione = excluded.data_lezione,
         card_n       = excluded.card_n;
end;
$$;

create or replace function coreano.trg_lezioni_flashcard_stash()
returns trigger
language plpgsql
security definer
set search_path = coreano, public
as $$
begin
  perform coreano.sync_flashcard_stash(new.numero);
  return new;
end;
$$;

drop trigger if exists lezioni_sync_flashcard_stash on coreano.lezioni;
create trigger lezioni_sync_flashcard_stash
after insert or update on coreano.lezioni
for each row execute function coreano.trg_lezioni_flashcard_stash();

-- Registra l'esito di una carta durante l'esercizio di ripasso.
--   'giusto'    -> +1 giusta; diventa 'imparata' dopo 2 giuste di fila
--   'sbagliato' -> stato 'sbagliata', azzera la striscia
--   'azzera'    -> riporta la carta a 'nuova'
create or replace function coreano.segna_flashcard(p_id bigint, p_esito text)
returns coreano.flashcard_stash
language plpgsql
security definer
set search_path = coreano, public
as $$
declare
  r coreano.flashcard_stash;
begin
  if p_esito not in ('giusto','sbagliato','azzera') then
    raise exception 'esito non valido: %', p_esito;
  end if;

  if p_esito = 'azzera' then
    update coreano.flashcard_stash
       set stato = 'nuova', volte_giusta = 0, volte_sbagliata = 0,
           giuste_di_fila = 0, ultima_revisione = now()
     where id = p_id
     returning * into r;
  elsif p_esito = 'giusto' then
    update coreano.flashcard_stash
       set volte_giusta     = volte_giusta + 1,
           giuste_di_fila   = giuste_di_fila + 1,
           stato            = case when giuste_di_fila + 1 >= 2 then 'imparata' else stato end,
           ultima_revisione = now()
     where id = p_id
     returning * into r;
  else
    update coreano.flashcard_stash
       set volte_sbagliata  = volte_sbagliata + 1,
           giuste_di_fila   = 0,
           stato            = 'sbagliata',
           ultima_revisione = now()
     where id = p_id
     returning * into r;
  end if;

  return r;
end;
$$;

alter table coreano.flashcard_stash enable row level security;

drop policy if exists "lettura pubblica flashcard_stash" on coreano.flashcard_stash;
create policy "lettura pubblica flashcard_stash" on coreano.flashcard_stash
  for select to anon using (true);

-- anon puo' solo leggere la tabella e chiamare la funzione:
-- nessun INSERT/UPDATE/DELETE diretto, quindi non puo' cancellare o inventare carte.
grant select on coreano.flashcard_stash to anon;
grant execute on function coreano.segna_flashcard(bigint, text) to anon;

-- Backfill dalle lezioni gia' presenti.
select coreano.sync_flashcard_stash(numero) from coreano.lezioni;
