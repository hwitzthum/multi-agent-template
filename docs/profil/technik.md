# Technik-Vorgaben (Profil: landingpage-fabrik)

<!-- Profil-Datei. Der Initializer liest sie zusätzlich zu produkt.md.
     Hier steht alles Technische, das vom Produkt abhängt — der Kern-Prompt
     in docs/templates/initializer-prompt.md bleibt projektunabhängig. -->

## Stack & Werkzeuge

- Einfachster Stack, der Landingpages sauber erzeugt. Keine Datenbank,
  kein Login, kein Server, wenn nicht zwingend nötig.
- Werkzeuge, die der Auftraggeber ohne Terminal-Wissen bedienen kann
  (z.B. Hosting per Git-Push, Formulare über einen Dienst).

## Feature-Test & Gruppierung

- Test "ist es ein Feature": Merkt ein Besucher der Seite das?
- Gruppierung in features.md: "Fabrik" (gilt für alle Seiten) und je
  eine Gruppe pro Brief.
- Erster Meilenstein (docs/state/current-milestone): "## Fabrik".

## Akzeptanz — Profilbeispiel

- Formulare und Endpunkte: JEDES Feld einzeln aufzählen (Name,
  E-Mail, ...) — nie nur "das Formular funktioniert".

## verify.sh — Stufen

- Standard: build, lint, tests, HTML-Validierung, Link-Check.
- Teuer (nur --deep): Lighthouse, Audits.

## Standard-Befehle

- new (neue Seite aus einem Brief), dev, build, test — gehören ins
  Toolchain-Manifest (package.json) und in CLAUDE.md.
