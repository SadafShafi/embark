//
//  SeedDecks.swift
//  Emberdeck
//
//  Two small decks so a fresh install has something to study on day one.
//  Replace or delete them freely — they are ordinary decks once inserted.
//

import Foundation
import SwiftData

enum SeedDecks {

    static func installIfEmpty(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        guard existing.isEmpty else { return }

        for spec in all {
            let deck = Deck(name: spec.name)
            deck.speechLanguage = spec.language
            deck.speechSide = .front
            context.insert(deck)
            for (index, row) in spec.rows.enumerated() {
                let parts = row.components(separatedBy: "|")
                guard parts.count >= 2 else { continue }
                let card = Card(front: parts[0].trimmingCharacters(in: .whitespaces),
                                back: parts[1].trimmingCharacters(in: .whitespaces),
                                tags: spec.tag,
                                position: index,
                                deck: deck)
                context.insert(card)
            }
        }
        try? context.save()
    }

    struct Spec {
        let name: String
        let tag: String
        let language: String
        let rows: [String]
    }

    static let all: [Spec] = [german, spanish]

    static let german = Spec(name: "German A1 — Everyday Core", tag: "a1", language: "de-DE", rows: [
        "der Bahnhof|the train station (m.)",
        "die Wohnung|the flat, apartment (f.)",
        "das Rathaus|the town hall (n.)",
        "die Rechnung|the bill, invoice (f.)",
        "der Termin|the appointment (m.)",
        "die Krankenkasse|the health insurance fund (f.)",
        "das Formular|the form (n.)",
        "die Anmeldung|the registration (f.)",
        "der Ausweis|the ID card (m.)",
        "die Miete|the rent (f.)",
        "der Schlüssel|the key (m.)",
        "die Haltestelle|the bus or tram stop (f.)",
        "das Fahrrad|the bicycle (n.)",
        "die Bäckerei|the bakery (f.)",
        "der Kühlschrank|the fridge (m.)",
        "die Quittung|the receipt (f.)",
        "das Semester|the semester (n.)",
        "die Vorlesung|the lecture (f.)",
        "die Bibliothek|the library (f.)",
        "die Prüfung|the exam (f.)",
        "sein — ich …|ich bin",
        "sein — du …|du bist",
        "sein — er/sie/es …|er ist",
        "haben — ich …|ich habe",
        "haben — du …|du hast",
        "werden — ich …|ich werde",
        "können — ich …|ich kann",
        "müssen — ich …|ich muss",
        "möchten — ich …|ich möchte",
        "dürfen — ich …|ich darf",
        "gehen (past participle)|gegangen (ist)",
        "sprechen (past participle)|gesprochen (hat)",
        "essen (past participle)|gegessen (hat)",
        "fahren (past participle)|gefahren (ist)",
        "schreiben (past participle)|geschrieben (hat)",
        "Entschuldigung, wo ist …?|Excuse me, where is …?",
        "Ich hätte gern …|I'd like … (polite, in a shop)",
        "Was kostet das?|How much is that?",
        "Können Sie das bitte wiederholen?|Could you repeat that, please?",
        "Ich verstehe nur Bahnhof.|I don't understand a word (idiom).",
        "Ich komme aus …|I come from …",
        "Wie geht es Ihnen?|How are you? (formal)",
        "Mir geht's gut, danke.|I'm well, thanks.",
        "Ich lerne seit einem Jahr Deutsch.|I've been learning German for a year.",
        "Das macht nichts.|It doesn't matter.",
        "Kein Problem.|No problem.",
        "Ich bin fertig.|I'm done, finished.",
        "Bis später!|See you later!",
        "Guten Appetit!|Enjoy your meal!",
        "Viel Erfolg!|Good luck! (with something you work at)",
        "mit + case?|dative — mit dem Bus, mit der Bahn",
        "für + case?|accusative — für dich, für den Kurs",
        "wegen + case?|genitive — wegen des Wetters",
        "in (where to?) + case?|accusative — ich gehe in die Stadt",
        "in (where at?) + case?|dative — ich bin in der Stadt",
        "weil …|… because (verb goes to the end)",
        "dass …|… that (verb goes to the end)",
        "aber …|… but (word order unchanged)",
        "deshalb …|… therefore (verb second, subject third)",
        "obwohl …|… although (verb goes to the end)",
    ])

    static let spanish = Spec(name: "Spanish Starter — First 40", tag: "a1", language: "es-ES", rows: [
        "la casa|the house",
        "el trabajo|the work, job",
        "la ciudad|the city",
        "el agua (f.)|the water — el agua fría",
        "la gente|the people (singular in Spanish)",
        "el dinero|the money",
        "la llave|the key",
        "el pueblo|the town; the people",
        "la calle|the street",
        "el tiempo|the time; the weather",
        "ser — yo …|yo soy",
        "ser — tú …|tú eres",
        "estar — yo …|yo estoy",
        "estar — él …|él está",
        "tener — yo …|yo tengo",
        "ir — yo …|yo voy",
        "hacer — yo …|yo hago",
        "poder — yo …|yo puedo",
        "querer — yo …|yo quiero",
        "saber — yo …|yo sé",
        "ser vs. estar: permanent traits|ser — soy alto, es médico",
        "ser vs. estar: states and location|estar — estoy cansado, está en casa",
        "Tengo 24 años.|I'm 24 years old (literally 'I have').",
        "Tengo hambre.|I'm hungry.",
        "Hace frío.|It's cold out.",
        "Hay …|There is / there are …",
        "¿Cómo se dice …?|How do you say …?",
        "¿Puedes repetir, por favor?|Can you repeat that, please?",
        "No pasa nada.|It's nothing, don't worry.",
        "Vale.|OK. (Spain)",
        "por vs. para: reason, cause|por — gracias por tu ayuda",
        "por vs. para: purpose, destination|para — este regalo es para ti",
        "pretérito of hablar (yo)|hablé — a finished action",
        "imperfecto of hablar (yo)|hablaba — ongoing or habitual past",
        "Me gusta el café.|I like coffee (literally 'coffee pleases me').",
        "Me gustan los libros.|I like books — plural subject takes gustan.",
        "Se me olvidó.|I forgot (literally 'it forgot itself to me').",
        "Llevo dos años aquí.|I've been here two years.",
        "Acabo de llegar.|I've just arrived.",
        "Ojalá que sí.|I hope so — takes the subjunctive.",
    ])
}
