-- BadbUI - Data/Guides: contenuto bundled della libreria guide (pack "BadbUI Starter").
-- Si carica dopo Modules/Guides.lua. Per aggiungere guide: nuove entry in questa tabella,
-- oppure Badb.Guides:Register(pack) da qualunque altro file/addon (vedi docs/guides.md).
-- Regole del contenuto: italiano, concreto, nessun dato di gioco non verificabile
-- (niente numeri di boss, loot, percentuali o nomi di abilita' inventati).
-- Ogni entry ha un campo confidence (A/B/C) come in docs/FOREVER_FACTS.md: A = confermato da
-- piu' fonti o fonte ufficiale, B = una fonte o fonti discordanti, C = ipotesi. Cio' che dipende
-- dal client e non e' A e' marcato nel testo con un blocco 'Da verificare in gioco'.
-- La confidenza di una entry e' la piu' bassa tra quelle delle affermazioni che contiene.
local _, ns = ...
local Badb = ns.Badb
local G = Badb and Badb.Guides
if not G then return end

G:Register({
    id = "starter",
    title = "BadbUI Starter",
    category = "BadbUI",
    version = 2,
    author = "BadbUI",
    entries = {

        ---------------------------------------------------------------------------
        {
            id = "primo-avvio",
            title = "Primo avvio: configurare BadbUI in pochi minuti",
            tags = { "avvio", "configurazione", "base", "guida rapida" },
            confidence = "A",
            body = {
                { type = "p", text = "BadbUI raccoglie in un unico posto profili, layout dell'Edit Mode, scala dell'interfaccia, barre azioni e cooldown. Questa guida ti porta da zero a una configurazione stabile, un passo alla volta." },
                { type = "h", text = "Passi consigliati" },
                { type = "step", text = "Digita /badb setup per la configurazione guidata: sceglie classe e ruolo, propone i template adatti e applica il consigliato in un nuovo profilo. Se preferisci fare a mano, salta al passo successivo." },
                { type = "step", text = "Digita /badb per aprire il pannello di configurazione. Ogni modulo ha un interruttore di attivazione: disattivarlo ripristina lo stato originale dell'interfaccia Blizzard." },
                { type = "step", text = "Nel modulo Scala interfaccia scegli tra scala pixel perfect (calcolata sull'altezza dello schermo) e scala manuale. Parti dalla pixel perfect: i bordi a 1 pixel restano nitidi." },
                { type = "step", text = "Nel modulo Nascondi elementi spegni quello che non usi: micro menu, barra delle borse, barra esperienza, tracker delle missioni, buff, minimappa. Ogni elemento nascosto si ripristina con lo stesso interruttore." },
                { type = "step", text = "Apri Barre azioni e Cooldown e regola icone, keybind e numeri dei cooldown. Le impostazioni valgono per il profilo attivo." },
                { type = "step", text = "Digita /badb unlock per sbloccare gli elementi gestiti da BadbUI (ad esempio l'icona al centro quando un'abilità torna pronta), spostali, poi ridigita /badb unlock per bloccarli." },
                { type = "step", text = "Posiziona barre e riquadri nativi con l'Edit Mode di Blizzard, poi usa Cattura layout attuale nel modulo Layout Edit Mode, così il layout viene salvato dentro il profilo." },
                { type = "step", text = "Esporta il profilo con /badb export e conserva la stringa in un file di testo: è il tuo backup più semplice." },
                { type = "tip", text = "Cambia una cosa alla volta e guarda il risultato in gioco. Se qualcosa non ti convince, disattiva il modulo: non devi reimpostare nulla a mano." },
                { type = "tip", text = "Prima di configurare BadbUI leggi anche la guida sull'interfaccia nativa di Forever: il client include già preset di interfaccia, click casting, damage meter e cooldown manager." },
                { type = "warn", text = "Alcune modifiche ai frame protetti non sono possibili in combattimento: BadbUI le mette in coda e le applica appena esci dal combattimento." },
            },
        },

        ---------------------------------------------------------------------------
        {
            id = "forever-ui-nativa",
            title = "L'interfaccia nativa di Forever: cosa c'è già prima degli addon",
            tags = { "forever", "interfaccia nativa", "edit mode", "preset", "classic", "enhanced", "click casting", "damage meter", "cooldown manager" },
            confidence = "B",
            body = {
                { type = "p", text = "WoW Forever usa un client con architettura moderna: molte funzioni che un tempo richiedevano addon sono ora integrate. Conoscerle ti evita di installare (e far litigare) strumenti che il gioco già offre." },
                { type = "h", text = "Preset di interfaccia e Edit Mode" },
                { type = "list", items = {
                    "Al primo accesso Blizzard propone un preset di interfaccia, Classic oppure Enhanced. Lo puoi cambiare in seguito da Opzioni, Sistema, Preset.",
                    "L'Edit Mode è integrato (barre azioni, riquadri unità, minimappa e altri elementi) e include il layout Classic (Preset): sposta i frame come nel gioco originale ma mantiene la grafica moderna.",
                    "I layout preset di Blizzard non si modificano direttamente: per personalizzarne uno crea una copia (duplica il layout) e lavora sulla copia.",
                } },
                { type = "h", text = "Funzioni integrate" },
                { type = "list", items = {
                    "Click casting e rimozione degli effetti (dispel) direttamente sui riquadri del gruppo e del raid.",
                    "Damage meter integrato.",
                    "Cooldown manager integrato.",
                    "I riquadri del gruppo possono usare lo stile dei raid frame: in BadbUI l'opzione si chiama Party in stile raid nel modulo Raid e party.",
                } },
                { type = "step", text = "Al primo accesso scegli il preset Blizzard che più si avvicina a come vuoi giocare: BadbUI lavora sopra quello." },
                { type = "step", text = "Prima di installare un addon per click casting, meter o cooldown, prova quelli nativi per qualche sessione." },
                { type = "step", text = "Sistema i layout con l'Edit Mode e poi catturali in BadbUI (guida sul layout) per portarli con il profilo." },
                { type = "warn", text = "Da verificare in gioco: queste informazioni arrivano da una sola fonte o da fonti discordanti (guide non ufficiali). Nomi dei menu, preset disponibili e funzioni integrate possono differire dalla tua versione del client." },
            },
        },

        ---------------------------------------------------------------------------
        {
            id = "profili-preset",
            title = "Profili e preset: come organizzare le configurazioni",
            tags = { "profili", "preset", "configurazione", "specializzazione" },
            confidence = "A",
            body = {
                { type = "p", text = "Un profilo contiene le opzioni di tutti i moduli e le posizioni dei frame gestiti da BadbUI. Ogni personaggio ricorda il proprio profilo attivo; più personaggi possono condividere lo stesso profilo." },
                { type = "h", text = "Gestire i profili" },
                { type = "list", items = {
                    "/badb profile elenca i profili esistenti e mostra quello attivo.",
                    "/badb profile <nome> passa a quel profilo. Se il nome non esiste, viene creato un profilo nuovo con i valori predefiniti: controlla di aver scritto bene il nome.",
                    "Il profilo attivo non può essere eliminato: passa prima a un altro profilo.",
                    "Con la doppia specializzazione (su Forever si sblocca al livello 40) a ogni specializzazione si può associare un profilo diverso: al cambio BadbUI cambia profilo da solo, fuori dal combattimento.",
                } },
                { type = "h", text = "Preset" },
                { type = "p", text = "Un preset è una configurazione pronta per una classe, un ruolo e un contesto: puoi applicarla senza costruirla da zero. Prima di applicarlo puoi vedere le differenze rispetto alla tua configurazione. La guida sui template di classe spiega come scegliere quello giusto." },
                { type = "list", items = {
                    "Nuovo profilo: crea un profilo a parte con il preset e lascia intatto il tuo. È la scelta più sicura.",
                    "Unisci: sovrascrive solo le opzioni che il preset definisce e conserva il resto.",
                    "Sostituisci: rimpiazza il profilo corrente con il preset.",
                    "Annulla: /badb undo riporta allo stato precedente all'ultima applicazione.",
                } },
                { type = "tip", text = "Applica un preset in modalità Nuovo profilo la prima volta. Se ti piace, tienilo; altrimenti torni al tuo profilo con /badb profile senza aver perso niente." },
                { type = "warn", text = "Sostituisci cancella le tue opzioni nel profilo corrente. Esporta il profilo (/badb export) prima di usarlo." },
            },
        },

        ---------------------------------------------------------------------------
        {
            id = "template-classe",
            title = "Come scegliere il template della tua classe",
            tags = { "template", "classe", "ruolo", "preset", "pve", "pvp", "role", "tank", "healer", "dps" },
            confidence = "B",
            body = {
                { type = "p", text = "Forever ha 9 classi (Guerriero, Paladino, Cacciatore, Ladro, Sacerdote, Sciamano, Mago, Stregone, Druido), ognuna con 3 alberi di talenti. BadbUI offre per ogni classe 6 template: 3 per il PvE e 3 per il PvP, con differenze motivate dal ruolo e dalla distanza di combattimento della classe." },
                { type = "h", text = "I 3 template PvE" },
                { type = "list", items = {
                    "Dungeon: gruppo da 5 giocatori.",
                    "Raid: con tre varianti per dimensione (10, 20 o 40 giocatori) che cambiano le dimensioni dei riquadri del gruppo: più compatti nel raid da 40, più ampi nel 10.",
                    "Solo: salita di livello e mondo aperto, interfaccia più pulita e tracker delle missioni visibile.",
                } },
                { type = "h", text = "I 3 template PvP" },
                { type = "list", items = {
                    "Campo di battaglia: partite da 10 a 15 giocatori per parte.",
                    "Alterac Valley: la battaglia da 40 contro 40.",
                    "World PvP: combattimenti in mondo aperto e duelli.",
                } },
                { type = "p", text = "Non esistono template per le arene: Forever non le ha." },
                { type = "h", text = "Scegliere il template" },
                { type = "step", text = "Digita /badb setup. BadbUI legge la tua classe e il ruolo che stai ricoprendo." },
                { type = "step", text = "Se la confidenza sul ruolo non è alta BadbUI te lo chiede: conferma o correggi il ruolo prima di proseguire." },
                { type = "step", text = "Scegli PvE, PvP o entrambi e guarda le differenze (Diff) prima di applicare." },
                { type = "step", text = "Applica in modalità Nuovo profilo. Se non ti convince, /badb undo annulla l'applicazione." },
                { type = "h", text = "Ruoli per classe" },
                { type = "list", items = {
                    "Guerriero: tank con l'albero Protezione, altrimenti dps.",
                    "Paladino: healer (Sacro), tank (Protezione) o dps (Retribuzione).",
                    "Sacerdote: healer (Disciplina e Sacro) o dps (Ombra).",
                    "Sciamano: healer con l'albero di restaurazione, altrimenti dps.",
                    "Druido: healer (Restaurazione) oppure dps; l'albero Feral può fare tank o dps.",
                    "Cacciatore, Ladro, Mago e Stregone: solo dps.",
                } },
                { type = "tip", text = "Se BadbUI ha scelto il ruolo sbagliato usa il comando /badb role per correggerlo: i template si adattano al ruolo che indichi. Digita /badb help per la sintassi." },
                { type = "warn", text = "Da verificare in gioco: le funzioni del client per leggere i talenti su Forever sono incerte (le fonti sono discordanti), quindi il ruolo rilevato può essere impreciso, specie per Druido Feral e Sciamano Potenziamento. I nomi esatti degli alberi in italiano possono differire da quelli scritti qui. Per questo BadbUI chiede conferma quando non è sicuro." },
            },
        },

        ---------------------------------------------------------------------------
        {
            id = "layout-edit-mode",
            title = "Layout ed Edit Mode: spostare gli elementi senza rompere nulla",
            tags = { "layout", "edit mode", "posizione", "sblocco", "classic preset" },
            confidence = "B",
            body = {
                { type = "p", text = "Su Forever la posizione di barre, riquadri e molti elementi nativi è gestita dall'Edit Mode di Blizzard. BadbUI non sposta mai questi frame con chiamate dirette (provocherebbero taint e conflitti): salva il layout dell'Edit Mode dentro il profilo e lo riattiva quando cambi profilo." },
                { type = "h", text = "Flusso di lavoro" },
                { type = "step", text = "Apri l'Edit Mode di Blizzard. Se parti dal layout Classic (Preset), duplicalo: i preset di Blizzard non si modificano, la copia sì." },
                { type = "step", text = "Sistema barre azioni, riquadri unità e il resto degli elementi nativi nella copia." },
                { type = "step", text = "Esci dall'Edit Mode e, nel pannello di BadbUI, premi Cattura layout attuale nel modulo Layout Edit Mode." },
                { type = "step", text = "Lascia attiva l'opzione Attiva il layout al cambio profilo: ogni profilo si porterà dietro il suo layout." },
                { type = "step", text = "Per gli elementi disegnati da BadbUI usa /badb unlock: compare una griglia, trascini gli elementi e ridigiti /badb unlock per bloccarli." },
                { type = "h", text = "Studio layout" },
                { type = "p", text = "Se il modulo Studio layout è presente, puoi annullare e ripetere gli spostamenti, muovere un elemento di un pixel alla volta, allineare e distribuire più elementi e bloccare interi gruppi per non spostarli per errore." },
                { type = "tip", text = "Dopo aver cambiato layout in Edit Mode ricordati di catturarlo di nuovo: BadbUI salva quello che c'era all'ultima cattura, non segue ogni modifica." },
                { type = "warn", text = "Non provare a posizionare le barre azioni con macro o script esterni: usa solo l'Edit Mode e la cattura del layout." },
                { type = "warn", text = "Da verificare in gioco: che il layout Classic (Preset) sia di sola lettura e vada duplicato per essere personalizzato è il comportamento abituale dell'Edit Mode moderno, ma non l'abbiamo confermato su Forever." },
            },
        },

        ---------------------------------------------------------------------------
        {
            id = "import-export",
            title = "Import ed export: condividere e proteggere la configurazione",
            tags = { "import", "export", "backup", "condivisione", "stringa" },
            confidence = "A",
            body = {
                { type = "p", text = "BadbUI esporta un profilo come una stringa di testo che inizia con BADB1: seguita dai dati codificati e da un checksum. La stringa contiene le opzioni dei moduli e il layout dell'Edit Mode catturato, ed è l'unico formato che serve per condividere o salvare una configurazione." },
                { type = "h", text = "Esportare" },
                { type = "step", text = "Digita /badb export: si apre una finestra con la stringa del profilo attivo." },
                { type = "step", text = "Seleziona tutto il testo, copialo con Ctrl+C e incollalo in un file di testo o in un messaggio." },
                { type = "h", text = "Importare" },
                { type = "list", items = {
                    "L'import crea sempre un profilo nuovo: scegli un nome che non esista già, altrimenti BadbUI rifiuta l'operazione e non tocca nulla.",
                    "Le stringhe sono verificate con il checksum e interpretate da un lettore dedicato: BadbUI non esegue mai codice contenuto in una stringa importata.",
                    "Una stringa incompleta, modificata a mano o di un tipo diverso (per esempio un layout al posto di un profilo) viene scartata con un messaggio nel log.",
                } },
                { type = "h", text = "Backup" },
                { type = "p", text = "Se il modulo Backup è presente, prima di operazioni distruttive (applicare un preset, importare, ripristinare) viene creato in automatico un punto di ripristino. Puoi anche crearne uno a mano prima di sperimentare." },
                { type = "tip", text = "Copia la stringa quando la configurazione ti soddisfa e datala nel nome del file: avere più versioni ti permette di tornare indietro." },
                { type = "warn", text = "Quando condividi una stringa con altri, controlla che non contenga nomi o impostazioni personali che non vuoi diffondere." },
            },
        },

        ---------------------------------------------------------------------------
        {
            id = "regole-contesto",
            title = "Cambio profilo automatico: le regole per contesto",
            tags = { "contesto", "regole", "profili", "automatico", "ruolo", "istanza" },
            confidence = "A",
            body = {
                { type = "p", text = "Se il modulo Contesti è presente, puoi far cambiare profilo a BadbUI in base a dove ti trovi e a cosa stai facendo, per esempio un'interfaccia più essenziale in raid e una più ricca in solitaria." },
                { type = "h", text = "Come è fatta una regola" },
                { type = "list", items = {
                    "Condizioni (tutte opzionali, valgono in AND): tipo di istanza (nessuna, gruppo, raid, campo di battaglia, scenario), ruolo (tank, healer, dps), tipo di gruppo (solo, gruppo, raid), specializzazione, classe.",
                    "Profilo: il profilo da attivare quando le condizioni sono vere.",
                    "Priorità: se più regole corrispondono vince quella con priorità maggiore.",
                    "Ogni regola si può disattivare senza cancellarla.",
                } },
                { type = "p", text = "Su Forever non ci sono arene: i campi di battaglia (Warsong Gulch, Arathi Basin, Alterac Valley, Darkspear Islands) sono il contesto PvP organizzato, il resto è World PvP." },
                { type = "h", text = "Esempio di impostazione" },
                { type = "step", text = "Crea i profili che ti servono, ad esempio uno per il raid, uno per i campi di battaglia e uno per tutto il resto (o applica i template della tua classe, che creano profili già pronti)." },
                { type = "step", text = "Aggiungi una regola con istanza uguale a raid che attiva il profilo del raid." },
                { type = "step", text = "Aggiungi una regola con istanza uguale a campo di battaglia che attiva il profilo PvP." },
                { type = "step", text = "Aggiungi una regola generica con priorità più bassa che riporta al profilo di tutti i giorni." },
                { type = "tip", text = "Tieni poche regole e chiare. Se non sai perché è stato scelto un profilo, disattiva le regole una alla volta." },
                { type = "warn", text = "Il cambio di profilo avviene fuori dal combattimento: se cambi contesto durante uno scontro, BadbUI aspetta che finisca." },
            },
        },

        ---------------------------------------------------------------------------
        {
            id = "integrazioni",
            title = "Integrazioni con altri addon: catturare e riapplicare i loro profili",
            tags = { "integrazioni", "addon", "profili", "elvui", "details", "plater", "bartender", "weakauras", "dbm", "bigwigs" },
            confidence = "B",
            body = {
                { type = "p", text = "Se il modulo Integrazioni è presente, BadbUI può ricordare quale profilo usi in alcuni addon di terze parti e riapplicarlo insieme al tuo profilo BadbUI, così un cambio di configurazione non lascia gli altri addon indietro. Tutto è best-effort: nessuna integrazione è stata verificata in gioco." },
                { type = "list", items = {
                    "Adattatori previsti: ElvUI, Details, Plater, Bartender4, WeakAuras. L'elenco mostra solo quelli che hai installato e che BadbUI sa gestire.",
                    "WeakAuras: non supportato, perché su Forever lo stato dell'addon è incerto (in giro ci sono build non ufficiali).",
                    "Details: esiste una versione per Forever, ma il meter in tempo reale è limitato dentro le istanze.",
                    "DBM e BigWigs: i timer degli incontri arrivano dalla timeline nativa del gioco.",
                    "Plater: nessun dato sul comportamento su Forever.",
                    "Cattura: salva nel profilo BadbUI lo stato scelto dell'addon. Applica: lo riporta a quanto catturato.",
                } },
                { type = "step", text = "Configura l'addon di terze parti come preferisci, con i suoi strumenti." },
                { type = "step", text = "Apri la pagina Integrazioni di BadbUI e usa Cattura per quell'addon." },
                { type = "step", text = "Cambia profilo e verifica che l'addon torni allo stato catturato con Applica." },
                { type = "tip", text = "Cattura dopo ogni modifica importante all'addon esterno: BadbUI conserva l'ultima cattura, non osserva i cambiamenti." },
                { type = "warn", text = "Da verificare in gioco: lo stato degli addon di terze parti su Forever cambia in fretta e le nostre informazioni vengono da fonti non ufficiali. Se Applica fallisce, controlla /badb log e ricattura lo stato." },
            },
        },

        ---------------------------------------------------------------------------
        {
            id = "restrizioni-addon",
            title = "Restrizioni degli addon su Forever: secret values e niente combat log",
            tags = { "restrizioni", "secret values", "combat log", "addon", "midnight", "limiti" },
            confidence = "B",
            body = {
                { type = "p", text = "Secondo le informazioni disponibili, Forever eredita le restrizioni sugli addon introdotte con Midnight. Sono la ragione per cui BadbUI ristilizza l'interfaccia ma non prova a leggere o calcolare ciò che accade in combattimento." },
                { type = "h", text = "Cosa cambia per te" },
                { type = "list", items = {
                    "Il combat log non è leggibile dagli addon: strumenti che si basano su di esso (calcolo del danno, avvisi su eventi di combattimento) non possono funzionare come su altri client.",
                    "Gli snippet di codice sicuri (secure snippets) non funzionano.",
                    "Valori come la salute delle unità e la minaccia sono secret values: l'addon può mostrarli ma non confrontarli o fare calcoli. In combattimento il client può nasconderli del tutto.",
                    "In istanza anche la chat può essere secret.",
                    "Gli addon possono comunque ristilizzare raid frame, nameplate, barre azioni, pannelli, font e grafica: è quello che fa BadbUI.",
                } },
                { type = "h", text = "Cosa fa BadbUI" },
                { type = "list", items = {
                    "Non legge mai il combat log e non usa snippet sicuri.",
                    "Controlla i valori del client prima di leggerli: se un valore è secret, la funzione che lo usava si disattiva per quel valore, senza errori.",
                    "Il countdown dei cooldown è quello del client, stilizzato da BadbUI: funziona anche quando la durata è opaca.",
                    "Le modifiche ai frame protetti aspettano la fine del combattimento.",
                } },
                { type = "tip", text = "Se un tuo addon smette di funzionare solo in combattimento o nelle istanze, probabilmente dipende da queste restrizioni e non da BadbUI. Cerca se l'autore offre una versione per Forever." },
                { type = "warn", text = "Da verificare in gioco: la fonte principale è una dichiarazione di un rappresentante di Blizzard riportata di seconda mano, e le fonti sui singoli dettagli (chat, minaccia, nameplate) non sono tutte concordi. Le regole possono cambiare con le patch." },
            },
        },

        ---------------------------------------------------------------------------
        {
            id = "conflitti-addon",
            title = "Conflitti con altri addon di interfaccia",
            tags = { "conflitti", "addon", "classicui", "elvui", "clique", "bartender", "dominos", "diagnostica" },
            confidence = "B",
            body = {
                { type = "p", text = "Due addon che modificano lo stesso elemento dell'interfaccia si disturbano a vicenda: posizioni che saltano, stili che si sovrascrivono, errori che compaiono solo con entrambi attivi. Su Forever circolano diversi addon di interfaccia che possono entrare in conflitto con BadbUI." },
                { type = "h", text = "Addon da tenere d'occhio" },
                { type = "list", items = {
                    "ClassicUI Forever, Classic UI Forever Reframed e Forevermore Classic UI: cambiano l'aspetto e la disposizione dell'interfaccia in stile classico.",
                    "Forever Unit Frames: sostituisce i riquadri delle unità.",
                    "EllesmereUI ed ElvUI: sostituiscono gran parte dell'interfaccia.",
                    "Bartender4 e Dominos: sostituiscono le barre azioni, che il modulo Barre azioni di BadbUI stilizza.",
                    "Clique: click casting, che il client ora offre già in forma integrata.",
                } },
                { type = "h", text = "Come procedere" },
                { type = "step", text = "Scegli un solo addon per ogni funzione: un solo gestore delle barre azioni, un solo gestore dei riquadri unità." },
                { type = "step", text = "Se usi un addon in stile classico, lascia a lui l'aspetto e usa BadbUI per profili, ruoli, cooldown e backup, disattivando i moduli di BadbUI che toccano gli stessi elementi (/badb disable <modulo>)." },
                { type = "step", text = "Se noti comportamenti strani, disattiva gli addon sospetti uno alla volta finché trovi il colpevole." },
                { type = "step", text = "Se è presente il modulo Diagnostica, eseguilo: elenca gli addon in conflitto che ha riconosciuto." },
                { type = "tip", text = "Prima di cambiare addon esporta il profilo (/badb export): ti permette di tornare indietro." },
                { type = "warn", text = "Da verificare in gioco: l'elenco viene da guide non ufficiali e non abbiamo provato ogni combinazione. Considera i conflitti indicati come possibili, non certi." },
            },
        },

        ---------------------------------------------------------------------------
        {
            id = "ui-tank",
            title = "Interfaccia per tank: cosa deve restare sempre visibile",
            tags = { "tank", "ruolo", "interfaccia", "cooldown", "difensivi", "nameplate" },
            confidence = "B",
            body = {
                { type = "p", text = "Il tank prende decisioni sul tempo di reazione: l'interfaccia deve mostrare subito lo stato dei propri cooldown difensivi, i nemici e il resto del gruppo, senza farti distogliere lo sguardo dal combattimento. Su Forever possono fare il tank il Guerriero, il Paladino e (secondo alcune fonti) il Druido." },
                { type = "h", text = "Priorità" },
                { type = "list", items = {
                    "Cooldown difensivi nelle barre che guardi di più, mai nascosti dalla dissolvenza.",
                    "Nameplate dei nemici ben leggibili: è lì che controlli chi sta attaccando chi.",
                    "Riquadro del bersaglio grande e leggibile.",
                    "Riquadri del gruppo visibili ma più piccoli di quelli di un healer.",
                    "Pochi avvisi a schermo: troppi segnali fanno perdere quelli importanti.",
                } },
                { type = "h", text = "Con BadbUI" },
                { type = "step", text = "Nel modulo Barre azioni attiva Mostra sempre in combattimento per la dissolvenza: le barre con i difensivi non devono sparire quando serve premerli." },
                { type = "step", text = "Nel modulo Cooldown tieni attivo il colore per tempo rimanente e imposta la soglia di scadenza a un valore che ti dia tempo di reagire." },
                { type = "step", text = "Nel modulo Nameplate rendi visibili i nemici e regola scala e trasparenza dei non bersagliati finché leggi a colpo d'occhio chi hai davanti." },
                { type = "step", text = "Attiva il pulse: l'icona al centro dello schermo ti avvisa quando un'abilità lunga torna pronta. Posizionala con /badb unlock vicino al punto in cui guardi." },
                { type = "tip", text = "Il template di classe per tank (dungeon o raid) imposta già barre, cooldown e nameplate in questa direzione: guarda la guida sui template." },
                { type = "warn", text = "La minaccia è un secret value su Forever: non aspettarti indicatori di aggro numerici da addon. Usa i segnali dei nameplate e dei riquadri nativi." },
                { type = "warn", text = "Da verificare in gioco: che il Druido Feral possa fare il tank e la disponibilità degli indicatori di aggro dipendono da fonti non uniformi." },
            },
        },

        ---------------------------------------------------------------------------
        {
            id = "ui-healer",
            title = "Interfaccia per healer: riquadri del gruppo e feedback delle cure",
            tags = { "healer", "ruolo", "interfaccia", "riquadri", "click casting", "raid frame" },
            confidence = "B",
            body = {
                { type = "p", text = "Il healer guarda soprattutto i riquadri del gruppo e le proprie barre. Un'interfaccia efficace riduce i movimenti dello sguardo e del mouse. Su Forever curano il Paladino, il Sacerdote, lo Sciamano e il Druido." },
                { type = "h", text = "Priorità" },
                { type = "list", items = {
                    "Riquadri del gruppo o del raid al centro o poco sotto, vicino al personaggio, non agli angoli dello schermo.",
                    "Riquadri più grandi e leggibili di quelli di un dps; nel raid da 40 devono diventare compatti, nel raid da 10 possono restare ampi.",
                    "Barre azioni con tutte le abilità di cura a portata di tasto, senza dissolvenza.",
                    "Cooldown con numeri grandi e colorati per stato: devi leggerli con la coda dell'occhio.",
                    "Elementi superflui (minimappa gigante, tracker missioni, barra esperienza) nascosti o ridotti.",
                } },
                { type = "h", text = "Con BadbUI" },
                { type = "step", text = "Nel modulo Raid e party attiva Party in stile raid, colore di classe e il testo della vita che preferisci: i frame sono quelli di Blizzard, BadbUI li ristilizza." },
                { type = "step", text = "Prova prima il click casting e la rimozione degli effetti integrati nei riquadri, prima di aggiungere un addon." },
                { type = "step", text = "Nel modulo Nascondi elementi spegni il tracker delle missioni e la barra esperienza quando sei in contenuti di gruppo." },
                { type = "step", text = "Nel modulo Cooldown aumenta la dimensione del testo rispetto al pulsante, finché i numeri si leggono senza fissarli." },
                { type = "tip", text = "Il template di classe per healer sistema i riquadri per la dimensione del raid (10, 20 o 40): scegli la variante giusta." },
                { type = "warn", text = "La salute delle unità può essere un secret value in combattimento: gli addon che la confrontano per costruire indicatori possono smettere di funzionare proprio durante lo scontro. Affidati ai riquadri nativi." },
                { type = "warn", text = "Da verificare in gioco: click casting e dispel integrati nei raid frame sono riportati da una sola fonte." },
            },
        },

        ---------------------------------------------------------------------------
        {
            id = "ui-dps",
            title = "Interfaccia per dps: ridurre il rumore, leggere la rotazione",
            tags = { "dps", "ruolo", "interfaccia", "rotazione", "cooldown", "mischia", "distanza" },
            confidence = "A",
            body = {
                { type = "p", text = "Per un dps conta la pulizia: meno elementi, più grandi e collocati dove guardi già. La rotazione deve essere leggibile con un colpo d'occhio. Cacciatore, Ladro, Mago e Stregone fanno sempre dps; le altre classi lo fanno con alcuni dei loro alberi di talenti." },
                { type = "h", text = "Priorità" },
                { type = "list", items = {
                    "Barre azioni vicine al centro, con tasti abbreviati leggibili.",
                    "Cooldown offensivi riconoscibili dai colori e da un avviso al ritorno.",
                    "Informazioni di bersaglio e proprie risorse ravvicinate.",
                    "Tutto il resto minimizzato o nascosto.",
                } },
                { type = "h", text = "Mischia e distanza" },
                { type = "p", text = "Chi combatte a distanza può permettersi barre più compatte e riquadri del gruppo più piccoli, perché guarda meno il bersaglio da vicino; chi combatte in mischia si muove di più e ha bisogno di avvisi più grandi e vicini al personaggio. I template di classe di BadbUI tengono conto di questa differenza." },
                { type = "h", text = "Con BadbUI" },
                { type = "step", text = "Nel modulo Barre azioni attiva i keybind abbreviati e regola dimensione e font fino a leggerli senza sforzo." },
                { type = "step", text = "Attiva i colori di stato: rosso fuori portata, blu senza risorsa, grigio se non utilizzabile. Ti dicono perché un tasto non funziona senza dover cercare il motivo." },
                { type = "step", text = "Imposta nel pulse una durata minima in modo che l'avviso compaia solo per i cooldown lunghi e non a ogni abilità." },
                { type = "tip", text = "Se usi la dissolvenza al mouseover per le barre che usi poco, lascia sempre visibili quelle con la rotazione principale." },
                { type = "tip", text = "Il cooldown manager e il damage meter integrati nel client possono bastare: provali prima di installare altri addon." },
                { type = "warn", text = "Il combat log non è disponibile agli addon su Forever: i meter di terze parti possono essere limitati. Non nascondere comunque elementi che ti servono per sopravvivere." },
            },
        },

        ---------------------------------------------------------------------------
        {
            id = "forever-pvp",
            title = "PvP su Forever: campi di battaglia e world PvP",
            tags = { "pvp", "campo di battaglia", "warsong", "arathi", "alterac", "darkspear", "world pvp", "arena" },
            confidence = "B",
            body = {
                { type = "p", text = "Il PvP di Forever è diverso da altri client moderni: al lancio non ci sono arene né PvP classificato. Quello che c'è sono i campi di battaglia e il World PvP." },
                { type = "h", text = "I quattro campi di battaglia" },
                { type = "list", items = {
                    "Warsong Gulch: 10 contro 10, per livelli da 10 a 60.",
                    "Arathi Basin: 15 contro 15, per livelli da 20 a 60.",
                    "Alterac Valley: 40 contro 40, per livelli da 51 a 60.",
                    "Darkspear Islands: 15 contro 15, per livelli da 30 a 60 (nuovo campo di battaglia).",
                } },
                { type = "h", text = "World PvP" },
                { type = "p", text = "I reami hanno quattro regole: Normale, PvP, Gioco di ruolo e Gioco di ruolo PvP. Il World PvP è obbligatorio solo nelle zone contese." },
                { type = "h", text = "Interfaccia consigliata" },
                { type = "list", items = {
                    "Spazio libero al centro: non coprire il personaggio e gli avversari con riquadri o finestre.",
                    "Nameplate dei nemici ben visibili e distanza di visualizzazione maggiore, riquadri degli alleati ridotti.",
                    "Cooldown di controllo e di fuga chiaramente distinguibili dagli altri.",
                    "Avvisi centrali per le abilità che tornano pronte, brevi e poco invadenti.",
                    "Un profilo separato dal PvE, da attivare in automatico nei campi di battaglia.",
                } },
                { type = "step", text = "Applica il template PvP della tua classe: campo di battaglia per le partite da 10-15, Alterac Valley per le 40 contro 40, World PvP per il mondo aperto e i duelli." },
                { type = "step", text = "Se è presente il modulo Contesti, aggiungi una regola che attiva il profilo PvP quando sei in un campo di battaglia." },
                { type = "step", text = "Nel profilo PvP riduci o nascondi tracker delle missioni, barra esperienza e altri elementi PvE." },
                { type = "tip", text = "Rendi il pulse abbastanza grande da vederlo mentre guardi il bersaglio e posizionalo con /badb unlock vicino al punto in cui tieni lo sguardo." },
                { type = "warn", text = "Cambi di profilo o di layout possono essere rimandati finché sei in combattimento: preparati prima dell'inizio della partita." },
                { type = "warn", text = "Da verificare in gioco: le informazioni sulle regole dei reami vengono da una sola fonte, e il modo in cui il client segnala di essere in World PvP non è confermato (BadbUI usa il tuo stato PvP). Arene e PvP classificato potrebbero arrivare in futuro." },
            },
        },

        ---------------------------------------------------------------------------
        {
            id = "forever-pve",
            title = "PvE su Forever: dungeon a 5 e raid da 10, 20 e 40",
            tags = { "pve", "dungeon", "raid", "barrow deeps", "hyjal summit", "onyxia", "attunement", "10", "20", "40" },
            confidence = "B",
            body = {
                { type = "p", text = "Il contenuto di gruppo di Forever si divide in dungeon da 5 giocatori e raid con dimensioni diverse. La dimensione del gruppo cambia molto cosa serve all'interfaccia." },
                { type = "h", text = "Raid (fonte ufficiale Blizzard)" },
                { type = "list", items = {
                    "I primi raid sono per il livello 60 e si sbloccano il 9 dicembre 2026.",
                    "Barrow Deeps: raid da 10 giocatori.",
                    "Hyjal Summit: raid da 20 giocatori.",
                    "Onyxia's Lair: raid da 40 giocatori, con attunement (sul sito Blizzard è legato al Drakefire Amulet).",
                    "Molten Core, Blackwing Lair e Naxxramas non fanno parte del primo gruppo di raid.",
                } },
                { type = "h", text = "Dungeon" },
                { type = "p", text = "Sono gruppi da 5: nove dungeon nuovi, dal livello 13 al 60, più i dungeon originali del gioco con bottino rivisto." },
                { type = "h", text = "Cosa cambia per l'interfaccia" },
                { type = "list", items = {
                    "Dungeon: riquadri del gruppo ampi e leggibili, poche cose a schermo.",
                    "Raid da 10: riquadri ancora abbastanza grandi da leggere nomi e stati.",
                    "Raid da 20 e da 40: riquadri compatti, niente elementi superflui, più attenzione alla leggibilità dei nameplate.",
                } },
                { type = "step", text = "Applica il template di classe per dungeon o raid; per il raid scegli la variante 10, 20 o 40 in base al contenuto." },
                { type = "step", text = "Con Contesti attivo, aggiungi regole per istanza gruppo (dungeon) e istanza raid, così il profilo cambia da solo." },
                { type = "warn", text = "Da verificare in gioco: i dati sui raid vengono dall'annuncio ufficiale ma le date e i dettagli possono cambiare; la descrizione dei dungeon (numero, livelli, bottino) viene da una sola guida non ufficiale. Controlla le fonti ufficiali per i dettagli aggiornati." },
            },
        },

        ---------------------------------------------------------------------------
        {
            id = "ui-raid",
            title = "Ottimizzare l'interfaccia per il raid",
            tags = { "raid", "prestazioni", "ottimizzazione", "interfaccia", "gruppo", "riquadri" },
            confidence = "A",
            body = {
                { type = "p", text = "In raid ci sono molti giocatori e molti effetti: ogni elemento dell'interfaccia in più è lavoro per il client. Questa guida ti aiuta a tenere solo ciò che serve, senza rinunciare a leggibilità." },
                { type = "h", text = "Alleggerire" },
                { type = "list", items = {
                    "Disattiva i moduli che non usi: un modulo spento non fa lavoro e ripristina l'interfaccia nativa.",
                    "Nascondi gli elementi non necessari durante lo scontro: tracker delle missioni, minimappa grande, barre che non guardi.",
                    "Tieni limitata l'opzione che applica lo stile a tutti i cooldown (buff, oggetti): attivala solo se ti serve.",
                    "Evita di sovrapporre più addon che fanno la stessa cosa: scegline uno per funzione.",
                } },
                { type = "h", text = "Procedura" },
                { type = "step", text = "Applica il template di raid della tua classe con la variante giusta (10, 20 o 40) oppure crea un profilo raid (/badb profile raid) a partire dal tuo profilo normale." },
                { type = "step", text = "Nel modulo Raid e party regola larghezza e altezza dei riquadri: più compatti con 40 giocatori, più ampi con 10." },
                { type = "step", text = "Spegni nel profilo raid i moduli e gli elementi non essenziali." },
                { type = "step", text = "Entra in un contenuto semplice e controlla se qualcosa è difficile da leggere o troppo piccolo." },
                { type = "step", text = "Se noti rallentamenti, riattiva i moduli uno alla volta finché trovi quello responsabile. Il log (/badb log) ti dice se un modulo segnala errori." },
                { type = "step", text = "Esporta il profilo raid con /badb export quando sei soddisfatto." },
                { type = "tip", text = "Misura sempre in modo ripetibile: stesso contenuto, stesse impostazioni grafiche. Cambia una cosa per volta, altrimenti non sai cosa ha migliorato o peggiorato." },
                { type = "warn", text = "Non esistono numeri magici validi per tutti: la differenza dipende dal computer, dalle impostazioni grafiche e dagli altri addon installati." },
            },
        },

        ---------------------------------------------------------------------------
        {
            id = "problemi-comuni",
            title = "Risoluzione problemi: /badb log e diagnostica",
            tags = { "problemi", "log", "errori", "diagnostica", "debug", "supporto" },
            confidence = "A",
            body = {
                { type = "p", text = "Quando qualcosa non funziona, BadbUI ti dà strumenti per capire cosa succede senza dover indovinare. Segui l'ordine: log, disattivazione mirata, diagnostica." },
                { type = "h", text = "Il log" },
                { type = "step", text = "Digita /badb log: si apre una finestra con gli ultimi messaggi di BadbUI (il buffer conserva le ultime 200 righe)." },
                { type = "step", text = "Cerca le righe con ERROR e WARN: indicano quale modulo o funzione ha avuto un problema e perché." },
                { type = "step", text = "Per più dettaglio digita /badb debug: attiva i messaggi di debug. Ridigitalo per tornare al livello normale." },
                { type = "h", text = "Isolare il problema" },
                { type = "list", items = {
                    "Disattiva il modulo sospetto con /badb disable <modulo> e verifica se il problema sparisce. /badb enable <modulo> lo riattiva.",
                    "Se un modulo non parte, nel log trovi la richiesta di un altro modulo da cui dipende e che è spento: riattiva quello.",
                    "Un elemento che non si sposta in combattimento non è un errore: BadbUI rimanda l'operazione a fine combattimento.",
                    "Se dopo un cambio di profilo il layout è sbagliato, ricattura il layout dell'Edit Mode nel profilo giusto.",
                    "Se un elemento è modificato da due addon, vedi la guida sui conflitti.",
                    "Se un valore non appare solo in combattimento o in istanza, vedi la guida sulle restrizioni degli addon.",
                } },
                { type = "h", text = "Diagnostica" },
                { type = "p", text = "Se il modulo Diagnostica è presente, esegue una serie di controlli (moduli, dati salvati, conflitti con altri addon, ruolo rilevato) e produce un rapporto testuale che puoi copiare e allegare quando chiedi aiuto." },
                { type = "tip", text = "Quando segnali un problema, copia le righe del log attorno all'errore e indica cosa stavi facendo: sono le informazioni più utili." },
                { type = "warn", text = "Il log non conserva i dati dopo il caricamento successivo dell'interfaccia: se vuoi tenere un errore, copialo prima di ricaricare." },
            },
        },

        ---------------------------------------------------------------------------
        {
            id = "usare-guide",
            title = "Usare la libreria di guide: ricerca, segnalibri e progresso",
            tags = { "guide", "libreria", "ricerca", "segnalibri", "video", "link", "confidenza" },
            confidence = "A",
            body = {
                { type = "p", text = "Questa libreria raccoglie guide testuali. Un addon non può riprodurre video: quando una guida rimanda a un video trovi il link come testo da copiare e incollare nel browser." },
                { type = "h", text = "Come muoversi" },
                { type = "list", items = {
                    "/badb guide apre la libreria; /badb guide search <testo> la apre già con la ricerca; /badb guide bookmarks elenca i segnalibri.",
                    "La ricerca ignora maiuscole e accenti e cerca tutte le parole che scrivi: più parole restringono i risultati. Titolo e tag pesano più del testo.",
                    "La stella accanto al titolo aggiunge o toglie il segnalibro. Con Solo segnalibri vedi soltanto quelli.",
                    "I passi con la casella si possono spuntare: il progresso (per esempio 3/7) resta salvato per tutto l'account.",
                } },
                { type = "h", text = "Confidenza delle informazioni" },
                { type = "p", text = "Sotto il titolo di ogni guida compare la confidenza: A significa confermato da più fonti o da fonte ufficiale, B una sola fonte o fonti discordanti, C ipotesi. Ciò che dipende dal client e non è A è segnato nel testo come da verificare in gioco." },
                { type = "step", text = "Apri la libreria con /badb guide." },
                { type = "step", text = "Cerca una parola chiave, ad esempio profili, e apri una guida dall'elenco." },
                { type = "step", text = "Spunta i passi man mano che li completi e metti un segnalibro alle guide che vuoi ritrovare." },
                { type = "step", text = "Per un link, clicca nella casella del link, premi Ctrl+C e incollalo nel browser." },
                { type = "tip", text = "Se una guida è legata a una zona, BadbUI te lo ricorda una sola volta per sessione quando ci entri, senza aprire finestre. Puoi disattivare l'avviso nelle opzioni del modulo Guide." },
                { type = "warn", text = "Controlla sempre l'indirizzo di un link prima di aprirlo: BadbUI lo mostra soltanto, non lo apre mai da solo." },
            },
        },
    },
})
