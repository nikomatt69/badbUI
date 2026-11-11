/* BadbUI features showcase — lightweight, dependency-free except optional Three.js.
   Two independent widgets: (1) rotating class-colour crystals, (2) simulated panel. */
(function () {
  "use strict";

  var CLASSES = [
    { name: "Warrior", color: 0xc79c6e, css: "#c79c6e", role: "Tank · DPS" },
    { name: "Paladin", color: 0xf58cba, css: "#f58cba", role: "Healer · Tank · DPS" },
    { name: "Hunter", color: 0xabd473, css: "#abd473", role: "DPS" },
    { name: "Rogue", color: 0xfff569, css: "#fff569", role: "DPS" },
    { name: "Priest", color: 0xffffff, css: "#ffffff", role: "Healer · DPS" },
    { name: "Shaman", color: 0x0070de, css: "#0070de", role: "Healer · DPS" },
    { name: "Mage", color: 0x69ccf0, css: "#69ccf0", role: "DPS" },
    { name: "Warlock", color: 0x9482c9, css: "#9482c9", role: "DPS" },
    { name: "Druid", color: 0xff7d0a, css: "#ff7d0a", role: "Tank · Healer · DPS" }
  ];

  /* ---------- Legend (works even without WebGL) ---------- */
  var legend = document.getElementById("class-legend");
  if (legend) {
    legend.innerHTML = CLASSES.map(function (c) {
      return '<span><i class="dot" style="background:' + c.css + ';color:' + c.css + '"></i>' + c.name + " · " + c.role + "</span>";
    }).join("");
  }

  /* ---------- 1) Three.js crystals (falls back gracefully) ---------- */
  (function initCrystals() {
    var canvas = document.getElementById("crystal-canvas");
    var fallback = document.getElementById("crystal-fallback");
    if (!canvas) return;
    if (typeof THREE === "undefined") { if (fallback) fallback.style.display = "flex"; canvas.style.display = "none"; return; }

    var renderer;
    try {
      renderer = new THREE.WebGLRenderer({ canvas: canvas, antialias: true, alpha: true });
    } catch (e) {
      if (fallback) fallback.style.display = "flex"; canvas.style.display = "none"; return;
    }
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));

    var scene = new THREE.Scene();
    var camera = new THREE.PerspectiveCamera(42, 1, 0.1, 100);
    camera.position.set(0, 2.2, 9.5);
    camera.lookAt(0, 0, 0);

    scene.add(new THREE.AmbientLight(0x8899bb, 0.9));
    var key = new THREE.PointLight(0xf5b94d, 60, 30); key.position.set(4, 5, 4); scene.add(key);
    var rim = new THREE.PointLight(0x4466cc, 30, 30); rim.position.set(-5, 2, -3); scene.add(rim);

    var group = new THREE.Group(); scene.add(group);

    // Central amber core
    var core = new THREE.Mesh(
      new THREE.IcosahedronGeometry(0.85, 0),
      new THREE.MeshStandardMaterial({ color: 0xf5b94d, emissive: 0xf5b94d, emissiveIntensity: 0.55, roughness: 0.25, metalness: 0.35, flatShading: true })
    );
    group.add(core);

    // Nine class crystals on a ring
    var crystals = CLASSES.map(function (c, i) {
      var angle = (i / CLASSES.length) * Math.PI * 2;
      var mesh = new THREE.Mesh(
        new THREE.OctahedronGeometry(0.52, 0),
        new THREE.MeshStandardMaterial({ color: c.color, emissive: c.color, emissiveIntensity: 0.45, roughness: 0.2, metalness: 0.2, flatShading: true })
      );
      mesh.position.set(Math.cos(angle) * 3.1, Math.sin(i * 1.7) * 0.35, Math.sin(angle) * 3.1);
      mesh.userData = { angle: angle, offset: i * 0.7 };
      group.add(mesh);
      return mesh;
    });

    // Thin ring to ground the composition
    var ring = new THREE.Mesh(
      new THREE.TorusGeometry(3.1, 0.015, 8, 96),
      new THREE.MeshBasicMaterial({ color: 0xf5b94d, transparent: true, opacity: 0.35 })
    );
    ring.rotation.x = Math.PI / 2; group.add(ring);

    function resize() {
      var w = canvas.clientWidth || canvas.parentElement.clientWidth;
      var h = canvas.clientHeight || 340;
      if (!w) return;
      renderer.setSize(w, h, false);
      camera.aspect = w / h; camera.updateProjectionMatrix();
    }
    resize();
    window.addEventListener("resize", resize);

    var reduced = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    var visible = true;
    if ("IntersectionObserver" in window) {
      new IntersectionObserver(function (entries) { visible = entries[0].isIntersecting; }, { threshold: 0.05 }).observe(canvas);
    }

    var clock = new THREE.Clock();
    renderer.setAnimationLoop(function () {
      if (!visible) return;
      var t = clock.getElapsedTime();
      var speed = reduced ? 0 : 1;
      group.rotation.y = t * 0.22 * speed;
      core.rotation.y = -t * 0.35 * speed; core.rotation.x = Math.sin(t * 0.4) * 0.15 * speed;
      core.position.y = Math.sin(t * 0.9) * 0.08 * speed;
      crystals.forEach(function (m) {
        m.rotation.y = t * 0.8 * speed + m.userData.offset;
        m.rotation.x = t * 0.35 * speed;
        m.position.y = Math.sin(t * 1.1 + m.userData.offset) * 0.28 * speed + Math.sin(m.userData.offset * 2.4) * 0.3;
      });
      renderer.render(scene, camera);
    });
  })();

  /* ---------- 2) Simulated BadbUI panel ---------- */
  var mock = document.getElementById("panel-mock");
  if (!mock) return;

  // Theme switcher: scoped CSS variables on the mock only
  var THEMES = {
    polestar: { label: "Polestar", vars: { "--mock-bg": "#0a1122", "--mock-surface": "#0d1528", "--mock-text": "#eef1f8", "--mock-muted": "#9aa3b8", "--mock-accent": "#f5b94d", "--mock-border": "rgba(255,255,255,.08)" } },
    night:    { label: "Night",    vars: { "--mock-bg": "#050505", "--mock-surface": "#111111", "--mock-text": "#f2f2f2", "--mock-muted": "#8a8a8a", "--mock-accent": "#c8a86a", "--mock-border": "rgba(255,255,255,.14)" } },
    elvui:    { label: "ElvUI",    vars: { "--mock-bg": "#0b0e14", "--mock-surface": "#121722", "--mock-text": "#d8dee9", "--mock-muted": "#7f8ca3", "--mock-accent": "#3fa7ff", "--mock-border": "rgba(63,167,255,.25)" } }
  };
  var themeName = document.getElementById("mock-theme-name");
  document.querySelectorAll("[data-theme-btn]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var theme = THEMES[btn.getAttribute("data-theme-btn")];
      if (!theme) return;
      Object.keys(theme.vars).forEach(function (k) { mock.style.setProperty(k, theme.vars[k]); });
      mock.setAttribute("data-theme", btn.getAttribute("data-theme-btn"));
      if (themeName) themeName.textContent = theme.label;
      document.querySelectorAll("[data-theme-btn]").forEach(function (b) { b.setAttribute("aria-pressed", String(b === btn)); });
    });
  });

  // SystemProfile tiers
  var TIERS = {
    performance: { name: "Performance", scale: "0.71 · 71%", bestFor: "Low FPS or very high pixel count", cvars: "Shadows Low · Particles Low · View distance 4", note: "Performance favours frame rate above all: smaller scale, lighter shadows, shorter view distance." },
    balanced:    { name: "Balanced", scale: "0.85 · 85%", bestFor: "Up to 1080p, steady 60 FPS", cvars: "Shadows Medium · Particles Medium · View distance 7", note: "Balanced is the safe default: native resolution at 1080p with headroom for raids." },
    quality:     { name: "Quality", scale: "1.00 · 100%", bestFor: "1440p at 55+ FPS", cvars: "Shadows High · Particles High · View distance 9", note: "Quality assumes a 1440p display holding 55+ FPS: full scale and richer effects." },
    ultra:       { name: "Ultra", scale: "1.15 · 115%", bestFor: "4K at 55+ FPS", cvars: "Shadows Ultra · Particles Ultra · View distance 10", note: "Ultra is for 4K at 55+ FPS. If your frame rate drops, step down — BadbUI never reads your GPU, so confirm in game." }
  };
  var tierEls = { name: document.getElementById("tier-name"), scale: document.getElementById("tier-scale"), bestFor: document.getElementById("tier-for"), cvars: document.getElementById("tier-cvars"), note: document.getElementById("tier-note") };
  document.querySelectorAll("[data-tier-btn]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var tier = TIERS[btn.getAttribute("data-tier-btn")];
      if (!tier) return;
      if (tierEls.name) tierEls.name.textContent = tier.name;
      if (tierEls.scale) tierEls.scale.textContent = tier.scale;
      if (tierEls.bestFor) tierEls.bestFor.textContent = tier.bestFor;
      if (tierEls.cvars) tierEls.cvars.textContent = tier.cvars;
      if (tierEls.note) tierEls.note.textContent = tier.note;
      document.querySelectorAll("[data-tier-btn]").forEach(function (b) { b.setAttribute("aria-pressed", String(b === btn)); });
    });
  });

  // Opponent panel mock
  var OPPONENTS = [
    { name: "Kaelthir", cls: "Mage", css: "#69ccf0", hp: 82, level: 60 },
    { name: "Brannok", cls: "Warrior", css: "#c79c6e", hp: 64, level: 60 },
    { name: "Selindra", cls: "Priest", css: "#ffffff", hp: 47, level: 60 },
    { name: "Thokk", cls: "Shaman", css: "#0070de", hp: 91, level: 60 }
  ];
  var oppList = document.getElementById("opp-list");
  var oppStatus = document.getElementById("opp-status");
  if (oppList) {
    oppList.innerHTML = OPPONENTS.map(function (o, i) {
      return '<button type="button" class="opp-row" data-opp="' + i + '" aria-pressed="' + (i === 0) + '">' +
        '<span class="dot" style="background:' + o.css + ';color:' + o.css + '"></span>' +
        '<span><b>' + o.name + '</b> <small>· ' + o.cls + " · Lv " + o.level + '</small><span class="bar"><i style="width:' + o.hp + "%;background:" + o.css + '"></i></span></span>' +
        "<small>" + o.hp + "%</small></button>";
    }).join("");
    oppList.querySelectorAll("[data-opp]").forEach(function (row) {
      row.addEventListener("click", function () {
        oppList.querySelectorAll("[data-opp]").forEach(function (r) { r.setAttribute("aria-pressed", String(r === row)); });
        var o = OPPONENTS[Number(row.getAttribute("data-opp"))];
        if (oppStatus) oppStatus.textContent = "Focused: " + o.name + " — " + o.cls + ", " + o.hp + "% health (client percentage API). In a battleground this list comes from nameplates, target and focus.";
      });
    });
    if (oppStatus) oppStatus.textContent = "Focused: Kaelthir — Mage, 82% health (client percentage API). Select another opponent to refocus.";
  }

  // Bag search mock
  var ITEMS = [
    { name: "Major Healing Potion", cat: "Consumable", detail: "×12 · Restores health" },
    { name: "Runecloth", cat: "Trade Goods", detail: "×47 · Cloth" },
    { name: "Arcanite Reaper", cat: "Weapon", detail: "Two-Hand Axe · iLvl 58" },
    { name: "Silk Cloth", cat: "Trade Goods", detail: "×23 · Cloth" },
    { name: "Mooncloth Bag", cat: "Container", detail: "16 slots" },
    { name: "Greater Mana Potion", cat: "Consumable", detail: "×8 · Restores mana" },
    { name: "Shadowfang", cat: "Weapon", detail: "One-Hand Sword · iLvl 24" },
    { name: "Traveler's Backpack", cat: "Container", detail: "16 slots" }
  ];
  var bagList = document.getElementById("bag-list");
  var bagSearch = document.getElementById("bag-search");
  var bagCount = document.getElementById("bag-count");
  function renderBags(query) {
    if (!bagList) return;
    var q = (query || "").trim().toLowerCase();
    var shown = 0;
    bagList.innerHTML = ITEMS.map(function (item) {
      var hit = !q || (item.name + " " + item.cat).toLowerCase().indexOf(q) !== -1;
      if (hit) shown++;
      return '<li' + (hit ? "" : " hidden") + "><span>" + item.name + ' <small>· ' + item.cat + "</small></span><small>" + item.detail + "</small></li>";
    }).join("") || '<li><span>No items match.</span><small>Clear the search</small></li>';
    if (!shown) bagList.innerHTML = '<li><span>No items match “' + q.replace(/</g, "&lt;") + '”.</span><small>Try “potion”</small></li>';
    if (bagCount) bagCount.textContent = String(shown);
  }
  renderBags("");
  if (bagSearch) bagSearch.addEventListener("input", function () { renderBags(bagSearch.value); });
})();
