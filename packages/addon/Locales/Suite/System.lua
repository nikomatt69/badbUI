local _, ns = ...
ns.Badb.Localization:RegisterLocale("enUS", {
    ["Profilo PC e grafica"] = "PC & graphics profile",
    ["Classifica il PC da risoluzione e FPS misurati e applica scala e qualita' consigliate."] = "Classify this PC from measured resolution and FPS, then apply recommended scale and quality.",
    ["Grafica"] = "Graphics", ["Prestazioni"] = "Performance",
    ["Dati dello schermo non disponibili su questo client."] = "Display data is unavailable on this client.",
    ["Profilo PC applicato: %s (scala consigliata %.2f, CVar: %s)"] = "PC profile applied: %s (recommended scale %.2f, CVars: %s)",
    ["nessuna"] = "none",
    ["Display %sx%s, FPS %s. Tier rilevato: %s. Un addon non puo' leggere GPU, CPU o sistema operativo: la classifica usa risoluzione e FPS reali."] = "Display %sx%s, FPS %s. Detected tier: %s. An addon cannot read GPU, CPU or OS: ranking uses real resolution and FPS.",
    ["Applica il profilo consigliato"] = "Apply recommended profile",
    ["Ripristina grafica originale"] = "Restore original graphics",
    ["system [apply] - mostra o applica il profilo PC/grafica"] = "system [apply] - show or apply the PC/graphics profile",
})
