// Bridge between Godot (JavaScriptBridge) and the Firebase JS SDK (compat build).
// Loaded at runtime by scripts/firebase/js_backend.gd. All values cross the
// bridge as JSON strings; results are delivered through Godot callbacks.
(function () {
  if (window.UnsoldFB) return;
  const SDK = "https://www.gstatic.com/firebasejs/10.12.2/";
  const libs = ["firebase-app-compat.js", "firebase-auth-compat.js", "firebase-database-compat.js"];

  function loadScript(src) {
    return new Promise((resolve, reject) => {
      const s = document.createElement("script");
      s.src = src;
      s.onload = resolve;
      s.onerror = () => reject(new Error("Failed to load " + src));
      document.head.appendChild(s);
    });
  }

  // Firebase drops nulls and empty containers, so compare normalized values.
  function norm(v) {
    if (v === null || v === undefined) return null;
    if (Array.isArray(v)) {
      const o = {};
      v.forEach((x, i) => { const n = norm(x); if (n !== null) o[i] = n; });
      return Object.keys(o).length ? o : null;
    }
    if (typeof v === "object") {
      const o = {};
      Object.keys(v).sort().forEach((k) => { const n = norm(v[k]); if (n !== null) o[k] = n; });
      return Object.keys(o).length ? o : null;
    }
    if (typeof v === "number") return Math.round(v * 1e6) / 1e6;
    return v;
  }
  const same = (a, b) => JSON.stringify(norm(a)) === JSON.stringify(norm(b));

  let db = null;
  const listeners = {};
  let offset = 0;

  window.UnsoldFB = {
    init(configJson, cb) {
      (async () => {
        try {
          for (const l of libs) await loadScript(SDK + l);
          firebase.initializeApp(JSON.parse(configJson));
          db = firebase.database();
          db.ref(".info/serverTimeOffset").on("value", (s) => { offset = s.val() || 0; });
          // Wait for the persisted session (if any) to be restored.
          await new Promise((resolve) => {
            const off = firebase.auth().onAuthStateChanged(() => { off(); resolve(); });
          });
          cb("ok");
        } catch (e) {
          console.error(e);
          cb("error:" + e.message);
        }
      })();
    },
    // ---- auth: every call answers with JSON {ok, uid, email, name} or {ok:false, error}
    _user(u) {
      return u ? { ok: true, uid: u.uid, email: u.email || "", name: u.displayName || "" }
               : { ok: false, error: "NO_SESSION" };
    },
    _wrap(promise, cb) {
      promise
        .then((u) => cb(JSON.stringify(window.UnsoldFB._user(u))))
        .catch((e) => { console.warn(e); cb(JSON.stringify({ ok: false, error: e.code || e.message })); });
    },
    currentUser(cb) {
      cb(JSON.stringify(window.UnsoldFB._user(firebase.auth().currentUser)));
    },
    signUpEmail(email, password, name, cb) {
      this._wrap(firebase.auth().createUserWithEmailAndPassword(email, password).then(async (c) => {
        if (name) await c.user.updateProfile({ displayName: name });
        return c.user;
      }), cb);
    },
    signInEmail(email, password, cb) {
      this._wrap(firebase.auth().signInWithEmailAndPassword(email, password).then((c) => c.user), cb);
    },
    signInGoogle(cb) {
      const provider = new firebase.auth.GoogleAuthProvider();
      provider.setCustomParameters({ prompt: "select_account" });
      this._wrap(firebase.auth().signInWithPopup(provider).then((c) => c.user), cb);
    },
    resetPassword(email, cb) {
      firebase.auth().sendPasswordResetEmail(email)
        .then(() => cb(JSON.stringify({ ok: true })))
        .catch((e) => cb(JSON.stringify({ ok: false, error: e.code || e.message })));
    },
    signOut(cb) {
      Object.keys(listeners).forEach((id) => window.UnsoldFB.unlisten(id));
      firebase.auth().signOut().then(() => cb("ok")).catch(() => cb("ok"));
    },
    offset() { return offset; },
    get(path, cb) {
      db.ref(path).get().then((s) => cb(JSON.stringify(s.val()))).catch(() => cb("null"));
    },
    set(path, json, cb) {
      db.ref(path).set(JSON.parse(json)).then(() => cb("ok")).catch((e) => cb("error:" + e.message));
    },
    update(path, json, cb) {
      db.ref(path).update(JSON.parse(json)).then(() => cb("ok")).catch((e) => cb("error:" + e.message));
    },
    // Compare-and-set: write newJson only if the current value equals expectedJson.
    cas(path, expectedJson, newJson, cb) {
      const expected = JSON.parse(expectedJson);
      const next = JSON.parse(newJson);
      db.ref(path).transaction((cur) => (same(cur, expected) ? next : undefined), null, false)
        .then((r) => cb(JSON.stringify({ ok: r.committed, value: r.snapshot.val() })))
        .catch((e) => cb(JSON.stringify({ ok: false, value: null, error: e.message })));
    },
    listen(path, id, cb) {
      const ref = db.ref(path);
      const fn = ref.on("value", (s) => cb(JSON.stringify(s.val())));
      listeners[id] = () => ref.off("value", fn);
    },
    unlisten(id) {
      if (listeners[id]) { listeners[id](); delete listeners[id]; }
    },
  };
})();
