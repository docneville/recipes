// nav.js — shared hamburger menu + breadcrumbs (recipes-b28.5, recipes-b28.6)
//
// Every page includes this after the supabase-js CDN script, then calls
// RecipesNav.init({ sb, breadcrumbs }) once it has its own `sb` client and
// knows its breadcrumb trail. Injects a hamburger button + slide-out panel
// into <header>, and a breadcrumb trail into <main> (if breadcrumbs given).
// Menu contents adapt to signed-in/out state via the passed `sb` client -
// no separate client of its own, so it always agrees with the page's own
// session check.

(function () {
  const MENU_ITEMS_SIGNED_IN = [
    { label: "Home", href: "index.html" },
    { label: "Your Recipes", href: "app.html" },
    { label: "+ Add Recipe", href: "add-recipe.html" },
    { label: "📷 Import from Photo", href: "import.html" },
    { label: "Profile", href: "profile.html" },
  ];

  function injectStyles() {
    if (document.getElementById("rc-nav-styles")) return;
    const style = document.createElement("style");
    style.id = "rc-nav-styles";
    style.textContent = `
      .rc-hamburger {
        position: absolute;
        top: 1.5rem;
        left: 1rem;
        background: none;
        border: 1px solid var(--rc-border);
        border-radius: 8px;
        width: 40px;
        height: 40px;
        font-size: 1.25rem;
        line-height: 1;
        cursor: pointer;
        color: var(--rc-text);
        margin: 0;
      }
      .rc-hamburger:hover { background: var(--rc-bg); }
      .rc-nav-overlay {
        display: none;
        position: fixed;
        inset: 0;
        background: rgba(0,0,0,0.35);
        z-index: 40;
      }
      .rc-nav-overlay.open { display: block; }
      .rc-nav-panel {
        position: fixed;
        top: 0;
        left: 0;
        bottom: 0;
        width: min(280px, 80vw);
        background: #fff;
        z-index: 41;
        box-shadow: 2px 0 12px rgba(0,0,0,0.15);
        transform: translateX(-100%);
        transition: transform 0.2s ease;
        padding: 1.25rem 1rem;
        overflow-y: auto;
      }
      .rc-nav-panel.open { transform: translateX(0); }
      .rc-nav-panel h2 {
        font-size: 1.1rem;
        margin: 0 0 1rem;
      }
      .rc-nav-panel a, .rc-nav-panel button.rc-nav-link {
        display: block;
        padding: 0.65rem 0.5rem;
        color: var(--rc-text);
        text-decoration: none;
        border-radius: 8px;
        font-size: 1rem;
        background: none;
        border: none;
        width: 100%;
        text-align: left;
        cursor: pointer;
        margin: 0;
      }
      .rc-nav-panel a:hover, .rc-nav-panel button.rc-nav-link:hover {
        background: var(--rc-bg);
      }
      .rc-nav-panel a.active {
        background: var(--rc-bg);
        font-weight: 600;
        color: var(--rc-accent-dark);
      }
      .rc-nav-panel hr {
        border: none;
        border-top: 1px solid var(--rc-border);
        margin: 0.75rem 0;
      }
      .rc-breadcrumbs {
        font-size: 0.85rem;
        color: var(--rc-muted);
        margin-bottom: 1rem;
      }
      .rc-breadcrumbs a {
        color: var(--rc-accent-dark);
        text-decoration: none;
      }
      .rc-breadcrumbs a:hover { text-decoration: underline; }
      .rc-breadcrumbs .sep { margin: 0 0.35rem; }
    `;
    document.head.appendChild(style);
  }

  function currentPage() {
    return window.location.pathname.split("/").pop() || "index.html";
  }

  function buildPanel(signedIn) {
    const panel = document.createElement("div");
    panel.className = "rc-nav-panel";
    panel.id = "rcNavPanel";

    const heading = document.createElement("h2");
    heading.textContent = "Menu";
    panel.appendChild(heading);

    if (signedIn) {
      const page = currentPage();
      MENU_ITEMS_SIGNED_IN.forEach((item) => {
        const a = document.createElement("a");
        a.href = item.href;
        a.textContent = item.label;
        if (item.href === page) a.classList.add("active");
        panel.appendChild(a);
      });
      const hr = document.createElement("hr");
      panel.appendChild(hr);
      const signOutBtn = document.createElement("button");
      signOutBtn.type = "button";
      signOutBtn.className = "rc-nav-link";
      signOutBtn.textContent = "Sign out";
      signOutBtn.id = "rcNavSignOut";
      panel.appendChild(signOutBtn);
    } else {
      const a = document.createElement("a");
      a.href = "index.html";
      a.textContent = "Home";
      panel.appendChild(a);
    }

    return panel;
  }

  function renderBreadcrumbs(container, items) {
    if (!container) return;
    if (!items || items.length === 0) {
      container.innerHTML = "";
      container.style.display = "none";
      return;
    }
    container.style.display = "block";
    container.innerHTML = items
      .map((item, i) => {
        const isLast = i === items.length - 1;
        const label = item.href && !isLast
          ? `<a href="${item.href}">${item.label}</a>`
          : `<span>${item.label}</span>`;
        return i === 0 ? label : `<span class="sep">/</span>${label}`;
      })
      .join("");
  }

  window.RecipesNav = {
    _sb: null,
    _breadcrumbsContainer: null,

    async init({ sb, breadcrumbs }) {
      injectStyles();
      this._sb = sb;

      const header = document.querySelector("header");
      if (header && !document.getElementById("rcHamburgerBtn")) {
        header.style.position = "relative";

        const btn = document.createElement("button");
        btn.type = "button";
        btn.id = "rcHamburgerBtn";
        btn.className = "rc-hamburger";
        btn.setAttribute("aria-label", "Menu");
        btn.textContent = "☰";
        header.prepend(btn);

        const overlay = document.createElement("div");
        overlay.className = "rc-nav-overlay";
        overlay.id = "rcNavOverlay";
        document.body.appendChild(overlay);

        const { data: { session } } = await sb.auth.getSession();
        const panel = buildPanel(!!session);
        document.body.appendChild(panel);

        const open = () => {
          panel.classList.add("open");
          overlay.classList.add("open");
        };
        const close = () => {
          panel.classList.remove("open");
          overlay.classList.remove("open");
        };

        btn.addEventListener("click", open);
        overlay.addEventListener("click", close);

        const signOutBtn = document.getElementById("rcNavSignOut");
        if (signOutBtn) {
          signOutBtn.addEventListener("click", async () => {
            await sb.auth.signOut();
            window.location.href = "index.html";
          });
        }
      }

      if (breadcrumbs !== undefined) {
        const main = document.querySelector("main");
        const container = document.createElement("nav");
        container.className = "rc-breadcrumbs";
        container.setAttribute("aria-label", "Breadcrumb");
        if (main) main.prepend(container);
        this._breadcrumbsContainer = container;
        renderBreadcrumbs(container, breadcrumbs);
      }
    },

    setBreadcrumbs(items) {
      renderBreadcrumbs(this._breadcrumbsContainer, items);
    },
  };
})();
