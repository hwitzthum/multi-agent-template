# Notizen

Hier stehen nur kuratierte Erkenntnisse. Neue Einträge verwenden eine eindeutige
ID und die Felder `tasks`, `date`, `source`, `confidence`, `status`, `evidence`
und `finding`. Zulässige Vertrauenswerte sind `hypothesis`, `observed`,
`verified` und `rejected`; der Status ist `active` oder `resolved`.

Verworfene und erledigte Einträge verschiebt `./scripts/archive-notes.sh`
oberhalb der Größenquote nach `notes-archive/`; der Befehl wird von Hand
gestartet. Fresh Worker erhalten ausschließlich Task-Kontext
und keine Einträge aus dieser Datei.
