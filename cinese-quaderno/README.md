# Quaderno di cinese

App web (PWA) per ripassare le lezioni di **cinese mandarino**: vocabolario, frasi,
grammatica, dialoghi, flashcard ed esercizi. È la sorella di
[`coreano-quaderno`](https://github.com/dhanatos96/coreano-quaderno), stessa struttura
e stessa interfaccia in italiano, adattata alla lingua cinese.

Tutto sta in `index.html`: nessuna build, nessuna dipendenza. Si apre da GitHub Pages
o da qualsiasi hosting statico, e si installa sul telefono come app.

## Cosa cambia rispetto al quaderno di coreano

| | coreano | cinese |
|---|---|---|
| Campo del testo | `ko` | `zh` (hanzi semplificati) |
| Pronuncia | — | `py`, il **pinyin** con i toni, mostrato sotto ogni hanzi |
| Sintesi vocale | `ko-KR` | `zh-CN` (esclude le voci cantonesi) |
| Carattere tipografico | Gowun Batang | Noto Serif SC |
| Schema Supabase | `coreano` | `cinese` |
| "Ricomponi la frase" | spezza la frase sugli spazi | usa la segmentazione `seg` dei dati |

Due aggiunte che il coreano non ha:

* **Interruttore del pinyin** (il tasto 拼 in alto): nasconde o mostra il pinyin
  ovunque nell'app, per ripassare leggendo solo i caratteri. La scelta resta salvata
  sul telefono.
* **Segmentazione esplicita delle frasi.** Il cinese si scrive senza spazi, quindi le
  tessere dell'esercizio "Ricomponi la frase" non si possono ricavare spezzando il
  testo. Vengono prese dal campo `seg`; in alternativa va bene una frase scritta con
  gli spazi fra le parole. Le frasi che non offrono né l'uno né l'altro restano fuori
  dall'esercizio. La verifica confronta la frase ricomposta **senza spazi**, così una
  segmentazione diversa ma che produce la stessa frase resta comunque corretta.

## Come si mette in piedi

Il progetto Supabase è lo stesso di tutti i quaderni: **il "tag lingua" è lo schema**.
Accanto a `coreano` e `italiano` si aggiunge `cinese`, e l'app lo chiede a ogni
richiesta con l'header `Accept-Profile: cinese`.

1. **Database.** Lanciare `supabase/migrations/20260918_schema_cinese.sql`: crea lo
   schema `cinese` con `curriculum`, `lezioni`, `ripassi`, `flashcard_stash` e le
   funzioni `sync_flashcard_stash` / `segna_flashcard`, con le stesse colonne degli
   schemi fratelli.
2. **Esporre lo schema.** Su Supabase, *Settings → API → Exposed schemas*: aggiungere
   `cinese` all'elenco (`public, graphql_public, coreano, italiano`). Senza questo
   passaggio PostgREST risponde `PGRST106 — Invalid schema: cinese` e l'app mostra
   "Non riesco a raggiungere il quaderno".
3. **Chiavi.** `SUPABASE_URL` e `SUPABASE_ANON_KEY`, in cima allo `<script>` di
   `index.html`, sono già quelle del progetto condiviso: non c'è niente da cambiare.
4. **Pubblicazione.** Ci pensa `.github/workflows/pages.yml`: a ogni push su `main`
   accende GitHub Pages (`enablement: true`) e pubblica la radice del repository, quindi
   non serve passare da *Settings → Pages*. Il sito finisce su
   <https://dhanatos96.github.io/cinese-quaderno/>. Il service worker non fa cache:
   serve solo a rendere l'app installabile.

## Forma dei dati

Una lezione (`cinese.lezioni`):

```json
{
  "numero": 1,
  "data": "2026-09-18",
  "tipo": "SITUAZIONE",
  "titolo": "Al ristorante",
  "contenuto": {
    "vocaboli": [ {"zh": "菜单", "py": "càidān", "it": "menu"} ],
    "frasi": [
      {"zh": "我想喝水", "py": "wǒ xiǎng hē shuǐ", "it": "Voglio bere acqua",
       "seg": [{"zh":"我","py":"wǒ"}, {"zh":"想","py":"xiǎng"},
               {"zh":"喝","py":"hē"}, {"zh":"水","py":"shuǐ"}]}
    ],
    "grammatica": [
      {"regola": "想 + verbo = volere fare qualcosa",
       "esempio_zh": "我想吃饭", "esempio_py": "wǒ xiǎng chī fàn",
       "esempio_it": "Voglio mangiare",
       "pronuncia": "两个三声连读: 你好 si legge ní hǎo"}
    ],
    "dialogo": [
      {"chi": "cameriere", "zh": "您好", "py": "nín hǎo", "it": "Salve"},
      {"chi": "studente",  "zh": "我想喝水", "py": "wǒ xiǎng hē shuǐ", "it": "Vorrei acqua"}
    ]
  },
  "esercizi": [
    {"tipo": "scelta", "consegna": "Come si dice \"acqua\"?",
     "opzioni": ["水", "菜单", "钱"], "corretta": 0, "spiegazione": "水 shuǐ = acqua."},
    {"tipo": "produzione", "consegna": "Traduci: Voglio bere acqua",
     "risposta": "我想喝水", "risposta_py": "wǒ xiǎng hē shuǐ", "spiegazione": "想 + verbo"}
  ],
  "riepilogo": ["Lezione 1 completata"]
}
```

Il campo `py` è sempre facoltativo: dove manca, l'app mostra solo gli hanzi.
`seg` accetta anche un semplice elenco di stringhe (`["我","想","喝","水"]`), ma con
gli oggetti `{zh, py}` ogni tessera porta il suo pinyin.

Le flashcard non si scrivono a mano: un trigger su `cinese.lezioni` riempie
`cinese.flashcard_stash` a ogni inserimento o modifica di una lezione, senza mai
toccare lo stato di studio delle carte già presenti.

Sui permessi: `anon` può solo leggere le tabelle e chiamare l'unica RPC che le serve,
`segna_flashcard`. `sync_flashcard_stash` e la funzione del trigger sono interne e
l'`EXECUTE` che Postgres concede a `PUBLIC` per default viene revocato — altrimenti
finirebbero raggiungibili su `/rest/v1/rpc/`, come succede oggi nello schema `coreano`.

## La voce

L'app usa la sintesi vocale del telefono con `lang="zh-CN"`. Il tasto altoparlante in
alto apre l'elenco delle voci cinesi installate (le voci cantonesi vengono escluse) e
la scelta resta salvata. Se non compare nessuna voce, va aggiunta dalle impostazioni
vocali del sistema. Nel dialogo c'è anche il tasto **Lento 0.7×**, comodo per sentire i
toni distintamente.
