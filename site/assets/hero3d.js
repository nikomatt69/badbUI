/* BadbUI hero — stylised 3D game-UI diorama. Three.js r160 via CDN (global THREE). */
(function () {
  "use strict";
  var canvas = document.getElementById("hero3d");
  if (!canvas || typeof THREE === "undefined") return;

  var NAVY = 0x050914, AMBER = 0xf5b94d;
  var renderer;
  try {
    renderer = new THREE.WebGLRenderer({ canvas: canvas, antialias: true, alpha: true });
  } catch (e) { return; }
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.setClearColor(NAVY, 0);

  var scene = new THREE.Scene();
  scene.fog = new THREE.Fog(NAVY, 9, 18);
  var camera = new THREE.PerspectiveCamera(42, 1, 0.1, 60);
  camera.position.set(0, 0.6, 8.2);

  scene.add(new THREE.AmbientLight(0x8fa3d8, 0.55));
  var key = new THREE.PointLight(AMBER, 28, 20); key.position.set(2.5, 2.2, 3.5); scene.add(key);
  var rim = new THREE.PointLight(0x5f7fe0, 18, 20); rim.position.set(-3.5, -1, 2); scene.add(rim);
  var top = new THREE.DirectionalLight(0xdfe8ff, 0.7); top.position.set(0, 5, 4); scene.add(top);

  var world = new THREE.Group(); scene.add(world);

  // Translucent UI panels
  var panelMat = new THREE.MeshPhysicalMaterial({
    color: 0x16224a, transparent: true, opacity: 0.42, roughness: 0.25,
    metalness: 0.1, side: THREE.DoubleSide
  });
  var edgeMat = new THREE.LineBasicMaterial({ color: AMBER, transparent: true, opacity: 0.75 });
  var panels = [];
  function panel(w, h, x, y, z, ry) {
    var g = new THREE.Group();
    var mesh = new THREE.Mesh(new THREE.BoxGeometry(w, h, 0.06), panelMat);
    var edges = new THREE.LineSegments(new THREE.EdgesGeometry(mesh.geometry), edgeMat);
    g.add(mesh); g.add(edges);
    // header bar + content lines inside the panel
    var bar = new THREE.Mesh(new THREE.BoxGeometry(w * 0.92, 0.09, 0.02),
      new THREE.MeshBasicMaterial({ color: AMBER, transparent: true, opacity: 0.85 }));
    bar.position.set(0, h / 2 - 0.18, 0.05); g.add(bar);
    for (var i = 0; i < 3; i++) {
      var line = new THREE.Mesh(new THREE.BoxGeometry(w * (0.55 - i * 0.1), 0.045, 0.02),
        new THREE.MeshBasicMaterial({ color: 0xaeb9d8, transparent: true, opacity: 0.5 }));
      line.position.set(-w * 0.16, h / 2 - 0.48 - i * 0.22, 0.05); g.add(line);
    }
    g.position.set(x, y, z); g.rotation.y = ry;
    g.userData.baseY = y; g.userData.phase = Math.random() * Math.PI * 2;
    world.add(g); panels.push(g); return g;
  }
  panel(2.5, 1.7, -2.15, 0.55, -0.4, 0.38);
  panel(2.5, 1.7, 2.15, 0.55, -0.4, -0.38);
  panel(2.0, 1.25, -1.85, -1.35, 0.5, 0.22);
  panel(2.0, 1.25, 1.85, -1.35, 0.5, -0.22);
  panel(3.1, 0.62, 0, -2.15, -0.2, 0); // action bar

  // Rotating amber ring + core
  var ring = new THREE.Mesh(new THREE.TorusGeometry(1.05, 0.045, 16, 96),
    new THREE.MeshStandardMaterial({ color: AMBER, emissive: AMBER, emissiveIntensity: 0.9, roughness: 0.3, metalness: 0.4 }));
  ring.position.set(0, 0.35, 0); world.add(ring);
  var ring2 = new THREE.Mesh(new THREE.TorusGeometry(1.32, 0.018, 12, 96),
    new THREE.MeshBasicMaterial({ color: 0xffcf7a, transparent: true, opacity: 0.55 }));
  ring2.position.copy(ring.position); ring2.rotation.x = Math.PI / 2.6; world.add(ring2);
  var core = new THREE.Mesh(new THREE.IcosahedronGeometry(0.42, 1),
    new THREE.MeshStandardMaterial({ color: AMBER, emissive: 0xd98a1f, emissiveIntensity: 1.1, roughness: 0.25, metalness: 0.3, flatShading: true }));
  core.position.copy(ring.position); world.add(core);

  // Particles
  var COUNT = 420, pos = new Float32Array(COUNT * 3);
  for (var i = 0; i < COUNT; i++) {
    pos[i * 3] = (Math.random() - 0.5) * 10;
    pos[i * 3 + 1] = (Math.random() - 0.5) * 6.5;
    pos[i * 3 + 2] = (Math.random() - 0.5) * 5 - 0.5;
  }
  var pgeo = new THREE.BufferGeometry();
  pgeo.setAttribute("position", new THREE.BufferAttribute(pos, 3));
  var particles = new THREE.Points(pgeo, new THREE.PointsMaterial({
    color: 0xffcf7a, size: 0.035, transparent: true, opacity: 0.75,
    depthWrite: false, blending: THREE.AdditiveBlending
  }));
  scene.add(particles);

  // Floor grid hint
  var grid = new THREE.GridHelper(12, 24, 0x2a3a6e, 0x141f42);
  grid.position.y = -2.9; grid.material.transparent = true; grid.material.opacity = 0.5;
  scene.add(grid);

  // Mouse parallax
  var tx = 0, ty = 0, mx = 0, my = 0;
  window.addEventListener("pointermove", function (e) {
    tx = (e.clientX / window.innerWidth - 0.5) * 2;
    ty = (e.clientY / window.innerHeight - 0.5) * 2;
  }, { passive: true });

  function resize() {
    var w = canvas.clientWidth || canvas.parentElement.clientWidth;
    var h = canvas.clientHeight || canvas.parentElement.clientHeight;
    if (!w || !h) return;
    renderer.setSize(w, h, false);
    camera.aspect = w / h; camera.updateProjectionMatrix();
  }
  window.addEventListener("resize", resize); resize();

  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var running = true, raf = 0, clock = new THREE.Clock();

  function frame() {
    if (!running) return;
    raf = requestAnimationFrame(frame);
    var t = clock.getElapsedTime();
    ring.rotation.z = t * 0.45; ring.rotation.x = Math.sin(t * 0.3) * 0.35;
    ring2.rotation.z = -t * 0.28;
    core.rotation.y = t * 0.7; core.rotation.x = t * 0.25;
    core.position.y = 0.35 + Math.sin(t * 1.3) * 0.09;
    ring.position.y = core.position.y; ring2.position.y = core.position.y;
    for (var j = 0; j < panels.length; j++) {
      var p = panels[j];
      p.position.y = p.userData.baseY + Math.sin(t * 0.7 + p.userData.phase) * 0.09;
      p.rotation.z = Math.sin(t * 0.4 + p.userData.phase) * 0.012;
    }
    particles.rotation.y = t * 0.018;
    mx += (tx - mx) * 0.045; my += (ty - my) * 0.045;
    world.rotation.y = mx * 0.22; world.rotation.x = my * 0.1;
    camera.position.x = mx * 0.45; camera.position.y = 0.6 - my * 0.3;
    camera.lookAt(0, 0, 0);
    renderer.render(scene, camera);
  }
  function start() { if (!running) { running = true; clock.getDelta(); frame(); } }
  function stop() { running = false; if (raf) cancelAnimationFrame(raf); }

  document.addEventListener("visibilitychange", function () {
    if (document.hidden) stop(); else start();
  });
  if (reduce) { // single static frame, no loop
    running = false; renderer.render(scene, camera);
  } else { frame(); }
})();
