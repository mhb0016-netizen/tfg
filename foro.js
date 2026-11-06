// ===== FORO: noticias, general y chats =====
// Usa lo que ya define index.html (sb, user, esAdmin, places, map, openPlace, need, toast, esc, errTxt, badge, $)
(function () {
  const main = document.querySelector("main"); main.id = "vMapa";
  const nav = document.createElement("nav"); nav.id = "nav";
  nav.innerHTML = '<button id="nMapa" class="on">Mapa</button><button id="nForo">Foro</button>';
  document.querySelector("header h1").after(nav);
  const sec = document.createElement("section"); sec.id = "foro"; sec.hidden = true;
  sec.innerHTML = '<div id="fLista"></div><div id="fCont"></div>';
  main.after(sec);

  let canales = [], canal = null, timer = null, firma = "", lugar = null, estados = {}, cd = null, hasta = 0;
  const link = t => esc(t).replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1" target="_blank" rel="noopener noreferrer nofollow">$1</a>');
  const cuando = d => new Date(d).toLocaleString("es-ES", {day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit"});

  function vista(v) {
    const f = v === "foro";
    main.hidden = f; sec.hidden = !f;
    $("nMapa").classList.toggle("on", !f); $("nForo").classList.toggle("on", f);
    if (f) cargarCanales();
    else { clearInterval(timer); timer = null; setTimeout(() => map.invalidateSize({animate: false}), 50); }
  }
  $("nMapa").onclick = () => vista("mapa");
  $("nForo").onclick = () => vista("foro");

  async function cargarEstados() {
    estados = {};
    if (!user) return;
    const { data } = await sb.from("miembros").select("canal_id,estado").eq("user_id", user.id);
    (data || []).forEach(m => estados[m.canal_id] = m.estado);
  }
  function pintarNav() {
    const n = Object.values(estados).filter(e => e === "invitado").length;
    $("nForo").textContent = n ? `Foro (${n})` : "Foro";
  }
  setInterval(async () => { if (user && sec.hidden) { await cargarEstados(); pintarNav(); } }, 60000);

  async function cargarCanales() {
    await cargarEstados(); pintarNav();
    const { data, error } = await sb.from("canales").select("*").order("created_at");
    if (error) { $("fLista").innerHTML = `<p class="msg">No se pudo cargar el foro: ${esc(error.message)}</p>`; return; }
    canales = data || [];
    if (!canal || !canales.find(c => c.id === canal)) canal = (canales.find(c => c.tipo === "general") || canales[0] || {}).id;
    pintarLista(); abrir(canal);
  }

  function pintarLista() {
    const it = (c, extra = "") => `<button class="fc ${c.id === canal ? "on" : ""}" data-c="${c.id}">${esc(c.nombre)}${extra}</button>`;
    const de = t => canales.filter(c => c.tipo === t).map(c => it(c)).join("");
    const chats = canales.filter(c => c.tipo === "chat");
    const inv = chats.filter(c => estados[c.id] === "invitado");
    const mios = chats.filter(c => estados[c.id] === "miembro" || (user && c.creado_por === user.id));
    const otros = esAdmin ? chats.filter(c => !inv.includes(c) && !mios.includes(c)) : [];
    $("fLista").innerHTML = `<h4>Información</h4>${de("noticias")}<h4>Comunidad</h4>${de("general")}
      ${inv.length ? `<h4>Invitaciones</h4>${inv.map(c => it(c, ' <span class="adm">NUEVA</span>')).join("")}` : ""}
      <h4>Mis chats</h4>${!user ? "<p class='msg'>Entra para ver y crear chats.</p>" : mios.map(c => it(c)).join("") || "<p class='msg'>Aún no tienes chats. Crea uno e invita a gente.</p>"}
      ${otros.length ? `<h4>Otros chats (solo admin)</h4>${otros.map(c => it(c)).join("")}` : ""}
      <button class="pri" id="fNuevo" style="margin-top:10px;width:100%">+ Crear chat</button>`;
    $("fLista").querySelectorAll("[data-c]").forEach(b => b.onclick = () => { canal = +b.dataset.c; pintarLista(); abrir(canal); });
    $("fNuevo").onclick = crearChat;
  }

  async function crearChat() {
    if (!need()) return;
    const nombre = (prompt("Nombre del chat (3-40 caracteres):") || "").trim();
    if (!nombre) return;
    const { data, error } = await sb.from("canales").insert({tipo: "chat", nombre}).select().single();
    if (error) return toast(errTxt(error.message));
    canal = data.id; cargarCanales();
    toast("Chat creado. Pulsa «Invitar» para añadir a gente.");
  }

  async function invitar(c) {
    if (!need()) return;
    const nombre = (prompt("Nombre de usuario de la persona a invitar:") || "").trim();
    if (!nombre) return;
    const { data: ps, error: e1 } = await sb.from("profiles").select("id,username").ilike("username", nombre.replace(/[\\%_]/g, "\\$&")).limit(1);
    if (e1) return toast(errTxt(e1.message));
    if (!ps || !ps.length) return toast("No existe ningún usuario con ese nombre.");
    if (user && ps[0].id === user.id) return toast("Ya estás en este chat.");
    const { error } = await sb.from("miembros").insert({canal_id: c.id, user_id: ps[0].id, estado: "invitado"});
    if (error) return toast(/duplicate|23505/i.test(error.message) ? "Esa persona ya está invitada o es miembro." : errTxt(error.message));
    toast("Invitación enviada a " + ps[0].username + ".");
    if ($("fMiem") && !$("fMiem").hidden) mostrarMiembros(c);
  }

  async function mostrarMiembros(c) {
    const box = $("fMiem"); if (!box) return;
    const { data, error } = await sb.from("miembros").select("user_id,estado").eq("canal_id", c.id);
    if (error) { box.innerHTML = `<span class="msg">${esc(error.message)}</span>`; return; }
    const ids = (data || []).map(m => m.user_id);
    const { data: pr } = ids.length ? await sb.from("profiles").select("id,username").in("id", ids) : {data: []};
    const nom = {}; (pr || []).forEach(x => nom[x.id] = x.username);
    const puede = user && (esAdmin || c.creado_por === user.id);
    box.innerHTML = (data || []).map(m => `<div class="fr"><span>${esc(nom[m.user_id] || "Vecino")}${m.user_id === c.creado_por ? " · creador" : ""}${m.estado === "invitado" ? " · invitación pendiente" : ""}</span>${puede && m.user_id !== c.creado_por ? `<button class="lnk" data-ex="${m.user_id}">${m.estado === "invitado" ? "Cancelar invitación" : "Expulsar"}</button>` : ""}</div>`).join("") || '<span class="msg">Sin miembros.</span>';
    box.querySelectorAll("[data-ex]").forEach(b => b.onclick = async () => {
      if (!confirm("¿Seguro?")) return;
      const { data: d, error: e } = await sb.from("miembros").delete().eq("canal_id", c.id).eq("user_id", b.dataset.ex).select();
      if (e || !d || !d.length) return toast(e ? errTxt(e.message) : "No tienes permiso.");
      mostrarMiembros(c);
    });
  }

  const composer = c => `<div class="fx">${c.tipo === "noticias" ? '<input id="fTit" maxlength="100" placeholder="Título de la noticia" style="margin-bottom:6px">' : ""}
    <textarea id="fTxt" rows="2" maxlength="1000" placeholder="${c.tipo === "noticias" ? "Escribe la noticia..." : "Escribe un mensaje..."}"></textarea>
    <div class="fr"><span id="fLug" class="msg"></span><div>${c.tipo !== "noticias" ? '<button id="fSh">Compartir lugar</button> ' : ""}<button class="pri" id="fSend">Enviar</button></div></div>
    ${c.tipo === "general" && !esAdmin ? '<div class="msg">En General puedes enviar un mensaje cada 5 minutos.</div>' : ""}
    <div class="msg" id="fErr"></div></div>`;

  function armar(ms) {
    clearInterval(cd); hasta = Date.now() + ms;
    const tic = () => {
      const b = $("fSend"); if (!b) return clearInterval(cd);
      const r = Math.ceil((hasta - Date.now()) / 1000);
      if (r <= 0) { clearInterval(cd); b.disabled = false; b.textContent = "Enviar"; return; }
      b.disabled = true; b.innerHTML = `Espera <span class="cd">${Math.floor(r / 60)}:${String(r % 60).padStart(2, "0")}</span>`;
    };
    tic(); cd = setInterval(tic, 1000);
  }

  async function abrir(id) {
    clearInterval(timer); clearInterval(cd);
    const c = canales.find(x => x.id === id); if (!c) return;
    firma = "";
    const estado = estados[c.id], esChat = c.tipo === "chat";
    if (esChat && estado === "invitado") {
      $("fCont").innerHTML = `<div class="fh"><b>${esc(c.nombre)}</b></div><div class="fm"><p>Te han invitado a este chat privado.</p><button class="pri" id="fAcc">Aceptar invitación</button> <button id="fRec">Rechazar</button><div class="msg" id="fErr"></div></div>`;
      $("fAcc").onclick = async () => {
        const { data: d, error: e } = await sb.from("miembros").update({estado: "miembro"}).eq("canal_id", c.id).eq("user_id", user.id).select();
        if (e || !d || !d.length) return ($("fErr").textContent = e ? errTxt(e.message) : "No se pudo aceptar.");
        cargarCanales();
      };
      $("fRec").onclick = async () => {
        const { error: e } = await sb.from("miembros").delete().eq("canal_id", c.id).eq("user_id", user.id);
        if (e) return ($("fErr").textContent = errTxt(e.message));
        canal = null; cargarCanales();
      };
      return;
    }
    const esMiembro = !esChat || estado === "miembro" || (user && c.creado_por === user.id);
    const esCreador = user && c.creado_por === user.id;
    const puedeAdm = user && (esAdmin || esCreador);
    const escribe = user && (c.tipo === "general" || (c.tipo === "noticias" && esAdmin) || (esChat && esMiembro));
    $("fCont").innerHTML = `<div class="fh"><b>${esc(c.nombre)}${esChat ? ' <small class="msg">· privado</small>' : ""}</b><span>
        ${esChat && (esMiembro || esAdmin) ? '<button class="lnk" id="fMiemB">Miembros</button>' : ""}
        ${esChat && puedeAdm ? '<button class="lnk" id="fInv">Invitar</button>' : ""}
        ${esChat && esMiembro && !esCreador ? '<button class="lnk" id="fSal">Salir</button>' : ""}
        ${esChat && puedeAdm ? '<button class="lnk" id="fDelC">Eliminar chat</button>' : ""}</span></div>
      <div id="fMiem" class="fx" hidden></div>
      <div id="fMsgs" class="fm"></div>
      ${escribe ? composer(c) : `<div class="fx msg">${c.tipo === "noticias" ? "Solo el equipo publica noticias." : esChat && esAdmin && !esMiembro ? "Estás viendo este chat como administrador. No eres miembro, así que no puedes escribir." : !user ? '<a href="#" id="fEntra">Entra</a> para escribir.' : "No puedes escribir aquí."}</div>`}`;
    if ($("fMiemB")) $("fMiemB").onclick = () => { const b = $("fMiem"); b.hidden = !b.hidden; if (!b.hidden) mostrarMiembros(c); };
    if ($("fInv")) $("fInv").onclick = () => invitar(c);
    if ($("fSal")) $("fSal").onclick = async () => {
      if (!confirm("¿Salir de este chat?")) return;
      const { error: e } = await sb.from("miembros").delete().eq("canal_id", c.id).eq("user_id", user.id);
      if (e) return toast(errTxt(e.message));
      canal = null; cargarCanales();
    };
    if ($("fEntra")) $("fEntra").onclick = e => { e.preventDefault(); need(); };
    if ($("fDelC")) $("fDelC").onclick = async () => {
      if (!confirm("¿Eliminar este chat y todos sus mensajes?")) return;
      const { data, error } = await sb.from("canales").delete().eq("id", c.id).select();
      if (error || !data || !data.length) return toast(error ? errTxt(error.message) : "No tienes permiso para eliminarlo.");
      canal = null; cargarCanales();
    };
    const err = t => { if ($("fErr")) $("fErr").textContent = t; };
    if ($("fSh")) $("fSh").onclick = () => {
      $("fLug").innerHTML = `<select id="fSel"><option value="">Elige un lugar…</option>${places.map(p => `<option value="${p.id}">${esc(p.name)}</option>`).join("")}</select>`;
      if (lugar) $("fSel").value = lugar;
      $("fSel").onchange = () => { lugar = +$("fSel").value || null; };
    };
    if (lugar && $("fSh")) $("fSh").onclick();
    if ($("fSend")) $("fSend").onclick = async () => {
      const texto = $("fTxt").value.trim(), titulo = $("fTit") ? $("fTit").value.trim() : "";
      if (!texto && !lugar) return err("Escribe algo o comparte un lugar.");
      if (c.tipo === "noticias" && !titulo) return err("Pon un título.");
      $("fSend").disabled = true;
      const { error } = await sb.from("mensajes").insert({canal_id: c.id, texto: texto || null, titulo: titulo || null, place_id: lugar});
      $("fSend").disabled = false;
      if (error) {
        if (/espera_general/.test(error.message)) armar((+(/espera_general:(\d+)/.exec(error.message) || [])[1] || 300) * 1000);
        return err(errTxt(error.message));
      }
      if (c.tipo === "general" && !esAdmin) armar(5 * 60 * 1000);
      lugar = null; $("fTxt").value = ""; if ($("fTit")) $("fTit").value = ""; if ($("fLug")) $("fLug").textContent = "";
      err(""); firma = ""; refrescar(true);
    };
    if (c.tipo === "general" && user && !esAdmin && $("fSend")) {
      const { data: ult } = await sb.from("mensajes").select("created_at").eq("canal_id", c.id).eq("user_id", user.id).order("created_at", {ascending: false}).limit(1);
      if (ult && ult.length) { const falta = new Date(ult[0].created_at).getTime() + 5 * 60 * 1000 - Date.now(); if (falta > 0) armar(falta); }
    }
    await refrescar(true);
    timer = setInterval(refrescar, 5000);
  }

  async function refrescar(bajar) {
    const id = canal, c = canales.find(x => x.id === id);
    const { data, error } = await sb.from("mensajes")
      .select("id,titulo,texto,created_at,user_id,place_id,profiles(username,rol),places(name,category)")
      .eq("canal_id", id).order("id", {ascending: false}).limit(100);
    const box = $("fMsgs");
    if (error || !box || id !== canal) return;
    const msgs = (data || []).reverse(), f = msgs.map(m => m.id).join(",");
    if (f === firma) return;
    firma = f;
    const abajo = bajar === true || box.scrollHeight - box.scrollTop - box.clientHeight < 80;
    box.innerHTML = msgs.map(m => {
      const quien = (m.profiles && m.profiles.username) || "Vecino", adm = m.profiles && m.profiles.rol === "admin";
      const propio = user && m.user_id === user.id;
      const cls = c && c.tipo === "noticias" ? "centro" : propio ? "mio" : "otro";
      const borra = user && (propio || esAdmin || (c && c.creado_por === user.id));
      return `<div class="bub ${cls}"><div class="bb">
        ${cls !== "mio" ? `<div class="au"><b>${esc(quien)}</b>${adm ? '<span class="adm">ADMIN</span>' : ""}</div>` : ""}
        ${m.titulo ? `<h3>${esc(m.titulo)}</h3>` : ""}${m.texto ? `<div class="tx">${link(m.texto)}</div>` : ""}
        ${m.place_id && m.places ? `<button class="lug" data-lugar="${m.place_id}">${badge(m.places.category, 26)} <span><b>${esc(m.places.name)}</b><br><small class="msg">Ver en el mapa</small></span></button>` : ""}
        <div class="mt"><span>${cuando(m.created_at)}</span>${borra ? `<button class="lnk" data-dm="${m.id}">Borrar</button>` : ""}</div></div></div>`;
    }).join("") || '<p class="msg">Todavía no hay mensajes.</p>';
    box.querySelectorAll("[data-dm]").forEach(b => b.onclick = async () => {
      if (!confirm("¿Borrar este mensaje?")) return;
      const { data: d, error: e } = await sb.from("mensajes").delete().eq("id", +b.dataset.dm).select();
      if (e || !d || !d.length) return toast(e ? errTxt(e.message) : "No tienes permiso para borrarlo.");
      firma = ""; refrescar();
    });
    box.querySelectorAll("[data-lugar]").forEach(b => b.onclick = () => {
      const pid = +b.dataset.lugar;
      if (!places.find(p => p.id === pid)) return toast("Ese lugar ya no está disponible.");
      vista("mapa"); openPlace(pid);
    });
    if (abajo) box.scrollTop = box.scrollHeight;
  }

  window.foroCompartir = id => { lugar = id; canal = null; vista("foro"); };
  window.foroUsuarioCambio = async () => { if (!sec.hidden) cargarCanales(); else { await cargarEstados(); pintarNav(); } };
  window.foroVista = vista;
})();