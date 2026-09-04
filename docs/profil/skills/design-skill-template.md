<!-- Vorlage für .claude/skills/fabrik-design/SKILL.md
     Ausfüllen mit Hilfe von docs/profil/skills/design-skill-interview-prompt.md.
     Schreibregel: Jeder Satz VERBIETET, VERORTET,
     WARNT oder ORDNET AN. Sätze, die nur beschreiben, werden gestrichen.
     Ziel: unter 500 Tokens. Nicht-Verhandelbares ganz oben. -->
---
name: fabrik-design
description: >
  Use WHENEVER the task creates or changes anything a visitor sees:
  page layout, sections, hero, CTA buttons, forms, colors, typography,
  spacing, images, or files in src/pages/*, src/components/*,
  src/styles/*. Does NOT fire for build scripts, tests, or docs/.
---

# <Organisation> — Design-Regeln für Landingpages

## Nicht verhandelbar (Verstoss = Aufgabe falsch, auch bei grünem verify)
- Genau EIN primärer Call-to-Action pro Seite: <Formular / Termin / …>.
  Sekundäre Links sind erlaubt, aber nie als Button gestaltet.
- Farben: Primär <#hex> (nur für CTA und Hervorhebung), Hintergrund
  <#hex>, Text <#hex>. Keine weiteren Akzentfarben ohne Freigabe.
- Kontrast Text/Hintergrund mindestens 4.5:1 (WCAG AA). Prüfen, nicht
  schätzen.
- Schrift: <Name> für Überschriften, <Name> für Fliesstext. Keine
  dritte Schrift.
- Mobil zuerst: Alles muss auf 375 px Breite ohne horizontales
  Scrollen lesbar sein.
- Tonalität der Texte: <Du/Sie>, <sachlich / warm / direkt>. Keine
  Superlative ohne Beleg ("beste", "einzigartig").

## Aufbau einer Seite (Reihenfolge ist verbindlich)
1. Hero: Headline (max. <N> Wörter), Subline (1 Satz), CTA, <Bild ja/nein>
2. <Problem / Nutzen — 3 Punkte, je max. 2 Sätze>
3. <Vertrauen: Logos / Zitate / Zahlen — nur echte, nie Platzhalter live>
4. <CTA-Wiederholung>
5. Footer: Impressum, Datenschutz, <Kontakt>

## Abstände & Grössen
- Abschnittsabstand: <z.B. 96 px Desktop / 64 px mobil>
- Maximale Textbreite: <z.B. 65 Zeichen pro Zeile>
- Buttons: <Höhe, Eckenradius, Grossschreibung ja/nein>

## Bilder & Logo
- Logo: <Pfad>; Mindestgrösse <px>; Schutzzone <px>. Nie verzerren.
- Bilder: <Stil: Fotos / Illustrationen>, immer mit Alt-Text.

## Bereits bezahlte Fallen
- (leer — wächst durch erlebte Fehler beim Meilenstein-Review, nicht durch Vorhersage)

## Referenzen (nur lesen, wenn die Aufgabe es verlangt)
- <docs/design/brand-guide.pdf — nur bei Fragen, die oben nicht stehen>
