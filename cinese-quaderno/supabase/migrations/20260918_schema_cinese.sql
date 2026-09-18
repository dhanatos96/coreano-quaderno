-- ============================================================================
-- Schema "cinese": l'equivalente dello schema "coreano" del Quaderno di coreano,
-- adattato al cinese mandarino.
--
-- Differenze rispetto al coreano:
--   * il campo del testo si chiama "zh" (hanzi semplificati) invece di "ko";
--   * accanto c'e' sempre "py", il pinyin con i toni (es. "ni3 hao3" -> "nǐ hǎo");
--   * le frasi possono portare "seg", la segmentazione in parole, perche' il
--     cinese si scrive senza spazi e l'esercizio "Ricomponi la frase" non puo'
--     ricavare le tessere spezzando il testo.
--
-- Il "tag lingua" del quaderno e' lo schema stesso: sullo stesso progetto
-- Supabase convivono gia' "coreano" e "italiano", e questo aggiunge "cinese".
--
-- Da lanciare una volta sola. Ricordarsi poi di esporre lo schema "cinese" in
-- Settings -> API -> Exposed schemas (accanto a public, graphql_public, coreano,
-- italiano), altrimenti PostgREST risponde
--   PGRST106 "Invalid schema: cinese"
-- alle richieste con Accept-Profile: cinese.
-- ============================================================================

create schema if not exists cinese;

grant usage on schema cinese to anon, authenticated;

-- ---------------------------------------------------------------- curriculum
-- Stesse colonne di coreano.curriculum / italiano.curriculum: e' il programma
-- del corso, una riga per argomento, che le lezioni poi spuntano.
create table if not exists cinese.curriculum (
  id             bigserial primary key,
  tipo           text    not null check (tipo in ('GRAMMATICA','SITUAZIONE')),
  blocco         text,
  ordine         integer,
  titolo         text    not null,
  livello        text    not null check (livello in ('A1','A2','B1','B2','C1')),
  completata     boolean not null default false,
  lezione_numero integer
);

create index if not exists curriculum_ordine_idx  on cinese.curriculum (ordine);
create index if not exists curriculum_livello_idx on cinese.curriculum (livello);

-- ------------------------------------------------------------------ lezioni
-- contenuto (jsonb):
--   {
--     "vocaboli":  [ {"zh":"菜单","py":"càidān","it":"menu"} ],
--     "frasi":     [ {"zh":"我想喝水","py":"wǒ xiǎng hē shuǐ","it":"Voglio bere acqua",
--                     "seg":[{"zh":"我","py":"wǒ"},{"zh":"想","py":"xiǎng"},
--                            {"zh":"喝","py":"hē"},{"zh":"水","py":"shuǐ"}]} ],
--     "grammatica":[ {"regola":"想 + verbo = volere fare qualcosa",
--                     "esempio_zh":"我想吃饭","esempio_py":"wǒ xiǎng chī fàn",
--                     "esempio_it":"Voglio mangiare",
--                     "pronuncia":"两个三声连读: 你好 si legge ní hǎo"} ],
--     "dialogo":   [ {"chi":"cameriere","zh":"您好","py":"nín hǎo","it":"Salve"},
--                    {"chi":"studente","zh":"我想喝水","py":"wǒ xiǎng hē shuǐ","it":"Vorrei acqua"} ]
--   }
-- esercizi (jsonb): elenco di
--   {"tipo":"scelta","consegna":"...","opzioni":["..."],"corretta":0,"spiegazione":"..."}
--   {"tipo":"correzione","consegna":"...","frase":"...","risposta":"...","risposta_py":"...","spiegazione":"..."}
--   {"tipo":"produzione","consegna":"...","risposta":"...","risposta_py":"...","spiegazione":"..."}
create table if not exists cinese.lezioni (
  numero        integer primary key,
  data          date not null,
  tipo          text not null check (tipo in ('GRAMMATICA','SITUAZIONE')),
  titolo        text not null,
  curriculum_id bigint references cinese.curriculum(id) on delete set null,
  contenuto     jsonb not null default '{}'::jsonb,
  esercizi      jsonb not null default '[]'::jsonb,
  recall        jsonb not null default '{}'::jsonb,
  riepilogo     jsonb not null default '[]'::jsonb,
  created_at    timestamptz not null default now()
);

create index if not exists lezioni_data_idx       on cinese.lezioni (data desc);
create index if not exists lezioni_curriculum_idx on cinese.lezioni (curriculum_id);

-- ------------------------------------------------------------------ ripassi
-- deck (jsonb):      [ {"n":1,"card_n":3,"lezione_numero":1,
--                       "zh":"你好","py":"nǐ hǎo","it":"ciao"} ]
-- contenuto (jsonb): { "lezioni_ripassate":[...], "grammatica_coperta":[...],
--                      "esercizi":[...], "riepilogo":[...] }
create table if not exists cinese.ripassi (
  id          bigserial primary key,
  data        date not null,
  da_lezione  integer not null,
  a_lezione   integer not null,
  deck        jsonb not null default '[]'::jsonb,
  contenuto   jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);

create index if not exists ripassi_data_idx on cinese.ripassi (data desc);

-- --------------------------------------------------------- flashcard_stash
-- Stash permanente delle flashcard + stato di studio (imparata / sbagliata / mai vista).
create table if not exists cinese.flashcard_stash (
  id               bigserial primary key,
  lezione_numero   integer not null references cinese.lezioni(numero) on delete cascade,
  card_n           integer not null,
  zh               text not null,
  py               text,
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
  unique (lezione_numero, tipo, zh)
);

create index if not exists flashcard_stash_stato_idx   on cinese.flashcard_stash (stato);
create index if not exists flashcard_stash_data_idx    on cinese.flashcard_stash (data_lezione desc);
create index if not exists flashcard_stash_livello_idx on cinese.flashcard_stash (livello);

-- Popola/riallinea lo stash a partire dal contenuto jsonb di una lezione.
-- Lo stato di studio delle carte gia' presenti non viene mai toccato.
create or replace function cinese.sync_flashcard_stash(p_numero integer)
returns void
language plpgsql
security definer
set search_path = cinese, public
as $$
declare
  l record;
begin
  select le.numero, le.data, le.contenuto, c.livello
    into l
    from cinese.lezioni le
    left join cinese.curriculum c on c.id = le.curriculum_id
   where le.numero = p_numero;
  if not found then
    return;
  end if;

  insert into cinese.flashcard_stash (lezione_numero, card_n, zh, py, it, tipo, livello, data_lezione)
  select l.numero,
         (row_number() over (order by t.ord, t.i))::int,
         t.zh, t.py, t.it, t.tipo, l.livello, l.data
    from (
      select 1 as ord, x.i as i, x.v->>'zh' as zh, x.v->>'py' as py, x.v->>'it' as it, 'vocabolo' as tipo
        from jsonb_array_elements(coalesce(l.contenuto->'vocaboli', '[]'::jsonb)) with ordinality as x(v, i)
      union all
      select 2, x.i, x.v->>'zh', x.v->>'py', x.v->>'it', 'frase'
        from jsonb_array_elements(coalesce(l.contenuto->'frasi', '[]'::jsonb)) with ordinality as x(v, i)
    ) t
   where t.zh is not null and btrim(t.zh) <> ''
  on conflict (lezione_numero, tipo, zh) do update
     set py           = excluded.py,
         it           = excluded.it,
         livello      = excluded.livello,
         data_lezione = excluded.data_lezione,
         card_n       = excluded.card_n;
end;
$$;

create or replace function cinese.trg_lezioni_flashcard_stash()
returns trigger
language plpgsql
security definer
set search_path = cinese, public
as $$
begin
  perform cinese.sync_flashcard_stash(new.numero);
  return new;
end;
$$;

drop trigger if exists lezioni_sync_flashcard_stash on cinese.lezioni;
create trigger lezioni_sync_flashcard_stash
after insert or update on cinese.lezioni
for each row execute function cinese.trg_lezioni_flashcard_stash();

-- Registra l'esito di una carta durante l'esercizio di ripasso.
--   'giusto'    -> +1 giusta; diventa 'imparata' dopo 2 giuste di fila
--   'sbagliato' -> stato 'sbagliata', azzera la striscia
--   'azzera'    -> riporta la carta a 'nuova'
create or replace function cinese.segna_flashcard(p_id bigint, p_esito text)
returns cinese.flashcard_stash
language plpgsql
security definer
set search_path = cinese, public
as $$
declare
  r cinese.flashcard_stash;
begin
  if p_esito not in ('giusto','sbagliato','azzera') then
    raise exception 'esito non valido: %', p_esito;
  end if;

  if p_esito = 'azzera' then
    update cinese.flashcard_stash
       set stato = 'nuova', volte_giusta = 0, volte_sbagliata = 0,
           giuste_di_fila = 0, ultima_revisione = now()
     where id = p_id
     returning * into r;
  elsif p_esito = 'giusto' then
    update cinese.flashcard_stash
       set volte_giusta     = volte_giusta + 1,
           giuste_di_fila   = giuste_di_fila + 1,
           stato            = case when giuste_di_fila + 1 >= 2 then 'imparata' else stato end,
           ultima_revisione = now()
     where id = p_id
     returning * into r;
  else
    update cinese.flashcard_stash
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

-- ------------------------------------------------------------------- accessi
-- L'app e' pubblica e usa la chiave anon: anon puo' solo LEGGERE le lezioni e
-- chiamare segna_flashcard. Nessun INSERT/UPDATE/DELETE diretto, quindi non puo'
-- cancellare o inventare carte.
alter table cinese.curriculum      enable row level security;
alter table cinese.lezioni         enable row level security;
alter table cinese.ripassi         enable row level security;
alter table cinese.flashcard_stash enable row level security;

drop policy if exists "lettura pubblica curriculum" on cinese.curriculum;
create policy "lettura pubblica curriculum" on cinese.curriculum
  for select to anon using (true);

drop policy if exists "lettura pubblica lezioni" on cinese.lezioni;
create policy "lettura pubblica lezioni" on cinese.lezioni
  for select to anon using (true);

drop policy if exists "lettura pubblica ripassi" on cinese.ripassi;
create policy "lettura pubblica ripassi" on cinese.ripassi
  for select to anon using (true);

drop policy if exists "lettura pubblica flashcard_stash" on cinese.flashcard_stash;
create policy "lettura pubblica flashcard_stash" on cinese.flashcard_stash
  for select to anon using (true);

grant select on cinese.curriculum      to anon;
grant select on cinese.lezioni         to anon;
grant select on cinese.ripassi         to anon;
grant select on cinese.flashcard_stash to anon;

-- Postgres concede EXECUTE a PUBLIC su ogni nuova funzione: senza queste revoche
-- sync_flashcard_stash e la funzione del trigger finirebbero esposte su
-- /rest/v1/rpc/ appena lo schema viene aggiunto agli Exposed schemas (e' quello
-- che succede oggi nello schema "coreano", dove il linter di Supabase le segnala).
-- Sono funzioni interne: l'unica RPC che l'app deve poter chiamare e' segna_flashcard.
revoke all on function cinese.sync_flashcard_stash(integer) from public, anon, authenticated;
revoke all on function cinese.trg_lezioni_flashcard_stash() from public, anon, authenticated;
revoke all on function cinese.segna_flashcard(bigint, text) from public;

grant execute on function cinese.segna_flashcard(bigint, text) to anon, authenticated;

-- Riallinea lo stash per le lezioni gia' presenti (no-op su schema vuoto).
select cinese.sync_flashcard_stash(numero) from cinese.lezioni;
